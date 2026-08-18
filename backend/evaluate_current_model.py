"""
TransactAI - Current DistilBERT Model Evaluation

Evaluates the currently saved model against the same dataset/split
used by the training pipeline.

Expected:
    Dataset: data/training_dataset.xlsx
    Model:   models/classifier

Run:
    python evaluate_current_model.py
"""

import os
import random
import warnings

import numpy as np
import pandas as pd
import torch

from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    classification_report,
    confusion_matrix,
    balanced_accuracy_score,
    matthews_corrcoef,
)

from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
)

from core.preprocessor import TransactionPreprocessor


# ============================================================
# CONFIGURATION
# ============================================================

SEED = 42

DATASET_PATH = os.path.join(
    "data",
    "training_dataset.xlsx"
)

MODEL_PATH = os.path.join(
    "models",
    "classifier"
)

# IMPORTANT:
# Your actual Excel file uses Description, not Message.
TEXT_COLUMN = "Description"
LABEL_COLUMN = "Category"

MAX_LENGTH = 256

# Evaluate only the test set by default.
# Set to False if you want validation + test.
EVALUATE_VALIDATION = True

BATCH_SIZE = 16


# ============================================================
# REPRODUCIBILITY
# ============================================================

def set_seed(seed=SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)

    if torch.cuda.is_available():
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)

    # Make CUDA behavior as reproducible as practical
    if torch.backends.cudnn.is_available():
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False


# ============================================================
# DEVICE
# ============================================================

def get_device():
    if torch.cuda.is_available():
        device = torch.device("cuda")

        print(f"CUDA available: YES")
        print(f"GPU: {torch.cuda.get_device_name(0)}")

        try:
            props = torch.cuda.get_device_properties(0)
            memory_gb = props.total_memory / (1024 ** 3)
            print(f"GPU Memory: {memory_gb:.2f} GB")
        except Exception:
            pass

        return device

    print("CUDA available: NO")
    print("Using CPU")

    return torch.device("cpu")


# ============================================================
# DATASET LOADING
# ============================================================

def load_dataset():
    print()
    print("[1/6] Loading dataset...")

    if not os.path.exists(DATASET_PATH):
        raise FileNotFoundError(
            f"Dataset not found:\n{os.path.abspath(DATASET_PATH)}"
        )

    df = pd.read_excel(DATASET_PATH)

    print(f"Raw rows: {len(df)}")

    print(f"Columns found: {list(df.columns)}")

    # --------------------------------------------------------
    # Automatically detect text column if necessary
    # --------------------------------------------------------

    possible_text_columns = [
        "Description",
        "notification_text",
        "message",
        "text",
        "Message",
    ]

    possible_label_columns = [
        "Category",
        "category",
        "label",
    ]

    if TEXT_COLUMN not in df.columns:

        found_text = None

        for col in possible_text_columns:
            if col in df.columns:
                found_text = col
                break

        if found_text is None:
            raise KeyError(
                f"Could not find transaction text column.\n"
                f"Available columns: {list(df.columns)}"
            )

        print(
            f"Using detected text column: {found_text}"
        )

        text_column = found_text

    else:
        text_column = TEXT_COLUMN

    # --------------------------------------------------------
    # Automatically detect label column
    # --------------------------------------------------------

    if LABEL_COLUMN not in df.columns:

        found_label = None

        for col in possible_label_columns:
            if col in df.columns:
                found_label = col
                break

        if found_label is None:
            raise KeyError(
                f"Could not find category column.\n"
                f"Available columns: {list(df.columns)}"
            )

        print(
            f"Using detected label column: {found_label}"
        )

        label_column = found_label

    else:
        label_column = LABEL_COLUMN

    # --------------------------------------------------------
    # Standardize names
    # --------------------------------------------------------

    df = df.rename(
        columns={
            text_column: "Description",
            label_column: "Category",
        }
    )

    df = df[["Description", "Category"]].copy()

    # Convert to strings
    df["Description"] = (
        df["Description"]
        .fillna("")
        .astype(str)
        .str.strip()
    )

    df["Category"] = (
        df["Category"]
        .fillna("")
        .astype(str)
        .str.strip()
    )

    # --------------------------------------------------------
    # Remove empty messages
    # --------------------------------------------------------

    before = len(df)

    df = df[df["Description"] != ""].copy()

    empty_removed = before - len(df)

    if empty_removed:
        print(f"Removed empty messages: {empty_removed}")

    # --------------------------------------------------------
    # Remove empty labels
    # --------------------------------------------------------

    before = len(df)

    df = df[df["Category"] != ""].copy()

    empty_labels_removed = before - len(df)

    if empty_labels_removed:
        print(
            f"Removed empty labels: {empty_labels_removed}"
        )

    # --------------------------------------------------------
    # Remove duplicate message + label pairs
    # Same behavior as training pipeline
    # --------------------------------------------------------

    before = len(df)

    df = df.drop_duplicates(
        subset=["Description", "Category"],
        keep="first"
    ).reset_index(drop=True)

    duplicate_pairs_removed = before - len(df)

    print(
        f"Duplicate message-label pairs removed: "
        f"{duplicate_pairs_removed}"
    )

    # --------------------------------------------------------
    # Remove duplicate messages
    # Same behavior as training pipeline
    # --------------------------------------------------------

    before = len(df)

    df = df.drop_duplicates(
        subset=["Description"],
        keep="first"
    ).reset_index(drop=True)

    duplicate_messages_removed = before - len(df)

    print(
        f"Duplicate messages removed: "
        f"{duplicate_messages_removed}"
    )

    print(f"Final evaluation dataset: {len(df)}")

    print()
    print("Categories:")
    for category, count in (
        df["Category"]
        .value_counts()
        .sort_index()
        .items()
    ):
        print(
            f"  {category:<25} {count:>7}"
        )

    return df


# ============================================================
# PREPROCESSING
# ============================================================

def preprocess_dataset(df):
    print()
    print("[2/6] Cleaning transaction messages...")

    processor = TransactionPreprocessor()

    df = df.copy()

    df["clean_text"] = processor.clean_batch(
        df["Description"].tolist(),
        max_workers=4
    )

    print("Text preprocessing completed.")

    return df


# ============================================================
# TRAIN / VALIDATION / TEST SPLIT
# ============================================================

def split_dataset(df):
    print()
    print("[3/6] Recreating training split...")

    # EXACT same split logic as train_model.py
    train_df, temp_df = train_test_split(
        df,
        test_size=0.3,
        random_state=SEED,
        stratify=df["Category"],
    )

    val_df, test_df = train_test_split(
        temp_df,
        test_size=0.5,
        random_state=SEED,
        stratify=temp_df["Category"],
    )

    train_df = train_df.reset_index(drop=True)
    val_df = val_df.reset_index(drop=True)
    test_df = test_df.reset_index(drop=True)

    print()
    print("Split sizes:")
    print(f"  Train      : {len(train_df)}")
    print(f"  Validation : {len(val_df)}")
    print(f"  Test       : {len(test_df)}")

    # --------------------------------------------------------
    # Leakage checks
    # --------------------------------------------------------

    train_texts = set(train_df["Description"])
    val_texts = set(val_df["Description"])
    test_texts = set(test_df["Description"])

    train_val_overlap = train_texts.intersection(val_texts)
    train_test_overlap = train_texts.intersection(test_texts)
    val_test_overlap = val_texts.intersection(test_texts)

    print()
    print("Data leakage checks:")

    print(
        f"  Train / Validation overlap: "
        f"{len(train_val_overlap)}"
    )

    print(
        f"  Train / Test overlap: "
        f"{len(train_test_overlap)}"
    )

    print(
        f"  Validation / Test overlap: "
        f"{len(val_test_overlap)}"
    )

    if (
        train_val_overlap
        or train_test_overlap
        or val_test_overlap
    ):
        warnings.warn(
            "Potential data leakage detected!"
        )

    return train_df, val_df, test_df


# ============================================================
# MODEL LOADING
# ============================================================

def load_model(device):
    print()
    print("[4/6] Loading current DistilBERT model...")

    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(
            f"Model not found:\n{os.path.abspath(MODEL_PATH)}"
        )

    print(
        f"Model directory: "
        f"{os.path.abspath(MODEL_PATH)}"
    )

    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_PATH
    )

    model = AutoModelForSequenceClassification.from_pretrained(
        MODEL_PATH
    )

    model.to(device)

    model.eval()

    print(
        f"Number of labels: "
        f"{model.config.num_labels}"
    )

    print(
        f"Model type: "
        f"{model.config.model_type}"
    )

    # --------------------------------------------------------
    # Print labels
    # --------------------------------------------------------

    if hasattr(model.config, "id2label"):

        print()
        print("Model labels:")

        for idx in range(model.config.num_labels):

            label = model.config.id2label.get(
                idx,
                str(idx)
            )

            print(
                f"  {idx:2d} -> {label}"
            )

    return tokenizer, model


# ============================================================
# PREDICTION
# ============================================================

def predict(
    texts,
    tokenizer,
    model,
    device,
    batch_size=BATCH_SIZE,
):
    predictions = []
    probabilities = []

    total = len(texts)

    for start in range(
        0,
        total,
        batch_size
    ):

        batch = texts[
            start:start + batch_size
        ]

        encoded = tokenizer(
            batch,
            padding=True,
            truncation=True,
            max_length=MAX_LENGTH,
            return_tensors="pt",
        )

        encoded = {
            key: value.to(device)
            for key, value in encoded.items()
        }

        with torch.no_grad():

            outputs = model(
                **encoded
            )

            logits = outputs.logits

            probs = torch.softmax(
                logits,
                dim=-1
            )

            preds = torch.argmax(
                probs,
                dim=-1
            )

        predictions.extend(
            preds.cpu().numpy().tolist()
        )

        probabilities.extend(
            probs.cpu().numpy().tolist()
        )

        completed = min(
            start + batch_size,
            total
        )

        percent = (
            completed / total
        ) * 100

        print(
            f"\r  Evaluated: "
            f"{completed}/{total} "
            f"({percent:.1f}%)",
            end="",
            flush=True,
        )

    print()

    return (
        np.array(predictions),
        np.array(probabilities)
    )


# ============================================================
# EVALUATION
# ============================================================

def evaluate_split(
    name,
    df,
    tokenizer,
    model,
    device,
):
    print()
    print("=" * 70)
    print(f"{name.upper()} SET EVALUATION")
    print("=" * 70)

    texts = df["clean_text"].tolist()

    labels = df["Category"].tolist()

    # --------------------------------------------------------
    # Label mapping
    # --------------------------------------------------------

    id2label = model.config.id2label

    label2id = {
        str(label): int(idx)
        for idx, label in id2label.items()
    }

    unknown_labels = sorted(
        set(labels) - set(label2id.keys())
    )

    if unknown_labels:
        raise ValueError(
            "Dataset contains labels that do not exist "
            f"in the model:\n{unknown_labels}"
        )

    true_ids = np.array([
        label2id[label]
        for label in labels
    ])

    # --------------------------------------------------------
    # Predictions
    # --------------------------------------------------------

    pred_ids, probabilities = predict(
        texts,
        tokenizer,
        model,
        device,
    )

    # --------------------------------------------------------
    # Metrics
    # --------------------------------------------------------

    accuracy = accuracy_score(
        true_ids,
        pred_ids
    )

    precision = precision_score(
        true_ids,
        pred_ids,
        average="weighted",
        zero_division=0,
    )

    recall = recall_score(
        true_ids,
        pred_ids,
        average="weighted",
        zero_division=0,
    )

    weighted_f1 = f1_score(
        true_ids,
        pred_ids,
        average="weighted",
        zero_division=0,
    )

    macro_f1 = f1_score(
        true_ids,
        pred_ids,
        average="macro",
        zero_division=0,
    )

    balanced_acc = balanced_accuracy_score(
        true_ids,
        pred_ids
    )

    mcc = matthews_corrcoef(
        true_ids,
        pred_ids
    )

    # --------------------------------------------------------
    # Print overall metrics
    # --------------------------------------------------------

    print()
    print("OVERALL METRICS")
    print("-" * 70)

    print(
        f"Accuracy           : {accuracy:.6f} "
        f"({accuracy * 100:.2f}%)"
    )

    print(
        f"Weighted Precision : {precision:.6f} "
        f"({precision * 100:.2f}%)"
    )

    print(
        f"Weighted Recall    : {recall:.6f} "
        f"({recall * 100:.2f}%)"
    )

    print(
        f"Weighted F1        : {weighted_f1:.6f} "
        f"({weighted_f1 * 100:.2f}%)"
    )

    print(
        f"Macro F1           : {macro_f1:.6f} "
        f"({macro_f1 * 100:.2f}%)"
    )

    print(
        f"Balanced Accuracy  : {balanced_acc:.6f} "
        f"({balanced_acc * 100:.2f}%)"
    )

    print(
        f"Matthews Corrcoef  : {mcc:.6f}"
    )

    # --------------------------------------------------------
    # Classification report
    # --------------------------------------------------------

    labels_sorted = sorted(
        set(true_ids) | set(pred_ids)
    )

    target_names = [
        str(id2label[int(i)])
        for i in labels_sorted
    ]

    print()
    print("PER-CLASS CLASSIFICATION REPORT")
    print("-" * 70)

    report = classification_report(
        true_ids,
        pred_ids,
        labels=labels_sorted,
        target_names=target_names,
        digits=4,
        zero_division=0,
    )

    print(report)

    # --------------------------------------------------------
    # Confusion matrix
    # --------------------------------------------------------

    cm = confusion_matrix(
        true_ids,
        pred_ids,
        labels=range(
            model.config.num_labels
        ),
    )

    print()
    print("CONFUSION MATRIX")
    print("-" * 70)

    label_names = [
        str(
            id2label.get(
                i,
                str(i)
            )
        )
        for i in range(
            model.config.num_labels
        )
    ]

    # Header
    print(
        "Actual \\ Pred".ljust(25),
        end=""
    )

    for label in label_names:
        print(
            label[:12].rjust(13),
            end=""
        )

    print()

    for i, row in enumerate(cm):

        print(
            label_names[i][:24].ljust(25),
            end=""
        )

        for value in row:

            print(
                str(int(value)).rjust(13),
                end=""
            )

        print()

    # --------------------------------------------------------
    # Most uncertain predictions
    # --------------------------------------------------------

    confidence = probabilities.max(
        axis=1
    )

    uncertain_indices = np.argsort(
        confidence
    )[:20]

    print()
    print("20 MOST UNCERTAIN PREDICTIONS")
    print("-" * 70)

    for idx in uncertain_indices:

        actual = labels[idx]

        predicted_id = int(
            pred_ids[idx]
        )

        predicted = id2label.get(
            predicted_id,
            str(predicted_id)
        )

        conf = confidence[idx]

        original_text = df.iloc[idx][
            "Description"
        ]

        print()
        print(
            f"Confidence : {conf:.4f}"
        )

        print(
            f"Actual     : {actual}"
        )

        print(
            f"Predicted  : {predicted}"
        )

        print(
            f"Message    : {original_text}"
        )

    # --------------------------------------------------------
    # Misclassified examples
    # --------------------------------------------------------

    wrong_indices = np.where(
        true_ids != pred_ids
    )[0]

    print()
    print(
        f"MISCLASSIFIED EXAMPLES "
        f"({len(wrong_indices)} total)"
    )

    print("-" * 70)

    for idx in wrong_indices[:30]:

        actual = labels[idx]

        predicted_id = int(
            pred_ids[idx]
        )

        predicted = id2label.get(
            predicted_id,
            str(predicted_id)
        )

        conf = confidence[idx]

        original_text = df.iloc[idx][
            "Description"
        ]

        print()
        print(
            f"Actual     : {actual}"
        )

        print(
            f"Predicted  : {predicted}"
        )

        print(
            f"Confidence : {conf:.4f}"
        )

        print(
            f"Message    : {original_text}"
        )

    return {
        "accuracy": float(accuracy),
        "precision": float(precision),
        "recall": float(recall),
        "weighted_f1": float(weighted_f1),
        "macro_f1": float(macro_f1),
        "balanced_accuracy": float(balanced_acc),
        "matthews_corrcoef": float(mcc),
        "confusion_matrix": cm.tolist(),
    }


# ============================================================
# MAIN
# ============================================================

def main():

    print("=" * 70)
    print(
        "TRANSACTAI - CURRENT DISTILBERT MODEL EVALUATION"
    )
    print("=" * 70)

    set_seed(SEED)

    device = get_device()

    print()
    print(
        f"Dataset: {DATASET_PATH}"
    )

    print(
        f"Model:   {MODEL_PATH}"
    )

    print(
        f"Seed:    {SEED}"
    )

    print(
        f"Max length: {MAX_LENGTH}"
    )

    print(
        f"Batch size: {BATCH_SIZE}"
    )

    # --------------------------------------------------------
    # 1. Dataset
    # --------------------------------------------------------

    df = load_dataset()

    # --------------------------------------------------------
    # 2. Preprocess
    # --------------------------------------------------------

    df = preprocess_dataset(df)

    # --------------------------------------------------------
    # 3. Split
    # --------------------------------------------------------

    train_df, val_df, test_df = split_dataset(df)

    # --------------------------------------------------------
    # 4. Load model
    # --------------------------------------------------------

    tokenizer, model = load_model(
        device
    )

    # --------------------------------------------------------
    # 5. Validation
    # --------------------------------------------------------

    validation_results = None

    if EVALUATE_VALIDATION:

        validation_results = evaluate_split(
            "Validation",
            val_df,
            tokenizer,
            model,
            device,
        )

    # --------------------------------------------------------
    # 6. Test
    # --------------------------------------------------------

    test_results = evaluate_split(
        "Test",
        test_df,
        tokenizer,
        model,
        device,
    )

    # --------------------------------------------------------
    # Final summary
    # --------------------------------------------------------

    print()
    print("=" * 70)
    print("FINAL MODEL SUMMARY")
    print("=" * 70)

    if validation_results is not None:

        print()
        print("VALIDATION")
        print(
            f"Accuracy    : "
            f"{validation_results['accuracy'] * 100:.2f}%"
        )

        print(
            f"Precision   : "
            f"{validation_results['precision'] * 100:.2f}%"
        )

        print(
            f"Recall      : "
            f"{validation_results['recall'] * 100:.2f}%"
        )

        print(
            f"Weighted F1 : "
            f"{validation_results['weighted_f1'] * 100:.2f}%"
        )

        print(
            f"Macro F1    : "
            f"{validation_results['macro_f1'] * 100:.2f}%"
        )

    print()
    print("TEST")
    print(
        f"Accuracy    : "
        f"{test_results['accuracy'] * 100:.2f}%"
    )

    print(
        f"Precision   : "
        f"{test_results['precision'] * 100:.2f}%"
    )

    print(
        f"Recall      : "
        f"{test_results['recall'] * 100:.2f}%"
    )

    print(
        f"Weighted F1 : "
        f"{test_results['weighted_f1'] * 100:.2f}%"
    )

    print(
        f"Macro F1    : "
        f"{test_results['macro_f1'] * 100:.2f}%"
    )

    print(
        f"Balanced Acc: "
        f"{test_results['balanced_accuracy'] * 100:.2f}%"
    )

    print(
        f"MCC         : "
        f"{test_results['matthews_corrcoef']:.6f}"
    )

    # --------------------------------------------------------
    # Overfitting check
    # --------------------------------------------------------

    if validation_results is not None:

        val_acc = validation_results[
            "accuracy"
        ]

        test_acc = test_results[
            "accuracy"
        ]

        val_f1 = validation_results[
            "weighted_f1"
        ]

        test_f1 = test_results[
            "weighted_f1"
        ]

        print()
        print("GENERALIZATION CHECK")
        print("-" * 70)

        print(
            f"Validation → Test accuracy difference: "
            f"{abs(val_acc - test_acc) * 100:.2f} percentage points"
        )

        print(
            f"Validation → Test F1 difference: "
            f"{abs(val_f1 - test_f1) * 100:.2f} percentage points"
        )

        if abs(val_acc - test_acc) < 0.02:

            print(
                "Result: Validation and test accuracy are "
                "very close."
            )

            print(
                "This is a good sign for generalization."
            )

        elif abs(val_acc - test_acc) < 0.05:

            print(
                "Result: There is a moderate validation/test gap."
            )

            print(
                "Inspect per-class metrics for possible "
                "generalization problems."
            )

        else:

            print(
                "WARNING: Large validation/test gap detected."
            )

            print(
                "This may indicate distribution differences "
                "or overfitting."
            )

    print()
    print("=" * 70)
    print("EVALUATION COMPLETE")
    print("=" * 70)


if __name__ == "__main__":
    main()