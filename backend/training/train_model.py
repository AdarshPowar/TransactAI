"""Production-ready training pipeline for the hybrid transaction classifier."""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import torch
from imblearn.over_sampling import ADASYN, RandomOverSampler, SMOTE
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    matthews_corrcoef,
    precision_recall_fscore_support,
)
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.utils.class_weight import compute_class_weight
from tqdm import tqdm

try:
    from backend.core.model import TransactionClassifier
    from backend.core.preprocessor import TransactionPreprocessor
except ModuleNotFoundError:  # pragma: no cover - legacy import fallback
    from core.model import TransactionClassifier
    from core.preprocessor import TransactionPreprocessor


SEED = 42
ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
MODEL_DIR = ROOT / "models"
OUTPUTS_DIR = ROOT / "outputs"
METRICS_DIR = OUTPUTS_DIR / "metrics"
OUTPUT_PLOTS_DIR = OUTPUTS_DIR / "plots"
EXPORT_DIR = OUTPUTS_DIR / "model"
ONNX_DIR = MODEL_DIR / "classifier_onnx"
BENCHMARK_DIR = OUTPUTS_DIR / "benchmarks"
README_DIR = OUTPUTS_DIR / "readme"
REPORT_DIR = OUTPUTS_DIR / "report"
LOG_DIR = ROOT / "logs"
RUNS_DIR = ROOT / "runs"
PLOTS_DIR = MODEL_DIR / "plots"

logger = logging.getLogger("transactai.training")


@dataclass
class TrainingConfig:
    """Configuration for the training pipeline."""

    epochs: int = 3
    batch_size: int = 16
    learning_rate: float = 2e-5
    weight_decay: float = 0.01
    warmup_ratio: float = 0.06
    max_length: int = 256
    seed: int = SEED
    gradient_accumulation_steps: int = 1
    eval_steps: int = 50
    save_steps: int = 50
    logging_steps: int = 50
    oversampling: str = "random"
    class_weights: bool = False
    fp16: Optional[bool] = None
    resume: bool = False
    datasets: List[str] = field(default_factory=lambda: ["training_dataset.xlsx"])
    allowed_categories: Optional[List[str]] = None
    optimizer: str = "adamw"
    lr_scheduler_type: str = "cosine"
    label_smoothing_factor: float = 0.0
    find_lr: bool = False
    quantize: bool = False
    export_onnx: bool = True
    experiment_name: Optional[str] = None
    cache_dir: Optional[str] = None
    max_grad_norm: float = 1.0
    early_stopping_patience: int = 3
    enable_versioning: bool = True
    enable_torch_compile: bool = False


def configure_logging(log_path: Optional[Path] = None) -> None:
    log_path = log_path or LOG_DIR / "training.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)
    logger.propagate = False


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Train the TransactAI DistilBERT classifier")
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--learning-rate", type=float, default=2e-5)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--warmup-ratio", type=float, default=0.06)
    parser.add_argument("--max-length", type=int, default=256)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--oversampling", choices=["none", "random", "smote", "adasyn"], default="random")
    parser.add_argument("--class-weights", action="store_true", help="Use balanced class weights")
    parser.add_argument("--dataset", action="append", default=None, help="Dataset file to load; can be used multiple times")
    parser.add_argument("--resume", action="store_true", help="Resume from the latest checkpoint if available")
    parser.add_argument("--fp16", action="store_true", help="Force FP16 usage when CUDA is available")
    parser.add_argument("--no-fp16", dest="fp16", action="store_false", help="Disable FP16 even when CUDA is available")
    parser.add_argument("--optimizer", choices=["adamw", "adam", "sgd"], default="adamw")
    parser.add_argument("--lr-scheduler-type", choices=["cosine", "linear", "polynomial"], default="cosine")
    parser.add_argument("--label-smoothing", type=float, default=0.0)
    parser.add_argument("--find-lr", action="store_true")
    parser.add_argument("--quantize", action="store_true")
    parser.add_argument("--export-onnx", dest="export_onnx", action="store_true")
    parser.add_argument("--no-export-onnx", dest="export_onnx", action="store_false")
    parser.add_argument("--experiment-name", default=None)
    parser.add_argument("--cache-dir", default=None)
    parser.add_argument("--no-versioning", dest="enable_versioning", action="store_false")
    parser.add_argument("--torch-compile", dest="enable_torch_compile", action="store_true")
    parser.set_defaults(fp16=None)
    parser.set_defaults(export_onnx=True)
    return parser


def _set_seed(seed: int = SEED) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False


def _detect_column(columns: Sequence[str], candidates: Sequence[str]) -> Optional[str]:
    column_set = set(columns)
    lowercase_map = {col.lower(): col for col in columns}
    for candidate in candidates:
        if candidate in column_set:
            return candidate
        lowered = candidate.lower()
        if lowered in lowercase_map:
            return lowercase_map[lowered]
    return None


def _resolve_dataset_path(path_value: str) -> Path:
    candidate = Path(path_value)
    if candidate.is_absolute():
        return candidate
    if (DATA_DIR / candidate).exists():
        return DATA_DIR / candidate
    return candidate


def _load_dataframe(path: Path, text_candidates: Sequence[str], label_candidates: Sequence[str]) -> Optional[pd.DataFrame]:
    if not path.exists():
        logger.warning("Dataset missing: %s", path)
        return None

    try:
        if path.suffix.lower() in (".xlsx", ".xls"):
            df = pd.read_excel(path, engine="openpyxl")
        else:
            df = pd.read_csv(path, low_memory=False)
    except Exception as exc:  # pragma: no cover - defensive logging
        logger.error("Failed to load %s: %s", path, exc)
        return None

    text_col = _detect_column(df.columns, text_candidates)
    label_col = _detect_column(df.columns, label_candidates)
    if text_col is None or label_col is None:
        logger.warning("Skipping %s: missing expected text/label columns", path.name)
        return None

    subset = df[[text_col, label_col]].rename(columns={text_col: "Description", label_col: "Category"})
    subset = subset.dropna(subset=["Description", "Category"])
    subset["Description"] = subset["Description"].astype(str).str.strip()
    subset["Category"] = subset["Category"].astype(str).str.strip()
    subset = subset[subset["Description"].str.len() > 0]
    logger.info("Loaded %s rows from %s", len(subset), path.name)
    return subset


def _save_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)


def _get_dataset_hash(frames: Sequence[pd.DataFrame]) -> str:
    combined = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    payload = f"rows={len(combined)}|categories={sorted(combined['Category'].astype(str).tolist())[:100]}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def prepare_dataset(config: TrainingConfig) -> Tuple[pd.DataFrame, Dict[str, Any]]:
    frames: List[pd.DataFrame] = []
    resolved_paths = [_resolve_dataset_path(path_value) for path_value in config.datasets]
    logger.info("Loading datasets: %s", [str(path) for path in resolved_paths])

    for path in resolved_paths:
        frame = _load_dataframe(path, ["notification_text", "message", "text", "Description"], ["category", "Category", "label"])
        if frame is not None and not frame.empty:
            frames.append(frame)

    if not frames:
        raise RuntimeError("No datasets could be loaded. Please ensure the requested files exist.")

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.reset_index(drop=True)

    # Basic cleaning and validation.
    combined["Description"] = combined["Description"].fillna("").astype(str).str.strip()
    combined["Category"] = combined["Category"].fillna("").astype(str).str.strip()
    initial_count = len(combined)

    empty_mask = combined["Description"].eq("")
    if empty_mask.any():
        logger.warning("Dropping %s empty rows", int(empty_mask.sum()))
        combined = combined[~empty_mask].reset_index(drop=True)

    if config.allowed_categories is not None:
        allowed_categories = set(config.allowed_categories)
        invalid_categories = sorted({category for category in combined["Category"].unique() if category not in allowed_categories})
        if invalid_categories:
            raise ValueError(f"Dataset contains labels outside allowed_categories: {invalid_categories}")

    duplicate_pairs = combined.duplicated(subset=["Description", "Category"], keep=False)
    duplicate_pair_count = int(duplicate_pairs.sum())
    if duplicate_pair_count:
        logger.info("Removing %s duplicate message-label pairs", duplicate_pair_count)
        combined = combined.drop_duplicates(subset=["Description", "Category"], keep="first").reset_index(drop=True)

    duplicate_messages = combined["Description"].duplicated(keep=False)
    duplicate_message_count = int(duplicate_messages.sum())
    if duplicate_message_count:
        logger.warning("Found %s duplicate messages after cleaning; keeping the first copy per message", duplicate_message_count)
        combined = combined.drop_duplicates(subset=["Description"], keep="first").reset_index(drop=True)

    valid = combined["Category"].value_counts()
    keep_labels = valid[valid >= 2].index
    dropped_rare = int(len(valid) - len(keep_labels))
    if dropped_rare:
        logger.warning("Dropping %s rare categories (<2 samples)", dropped_rare)
        combined = combined[combined["Category"].isin(keep_labels)].reset_index(drop=True)

    stats = {
        "initial_samples": int(initial_count),
        "final_samples": int(len(combined)),
        "duplicate_message_pairs_removed": int(duplicate_pair_count),
        "duplicate_messages_removed": int(duplicate_message_count),
        "empty_rows_removed": int(initial_count - len(combined)),
        "category_distribution": {k: int(v) for k, v in combined["Category"].value_counts().to_dict().items()},
        "average_message_length": float(combined["Description"].str.len().mean()) if not combined.empty else 0.0,
        "longest_message_length": int(combined["Description"].str.len().max()) if not combined.empty else 0,
        "shortest_message_length": int(combined["Description"].str.len().min()) if not combined.empty else 0,
        "unique_messages": int(combined["Description"].nunique()),
        "unique_samples": int(len(combined)),
    }
    logger.info("Dataset statistics: %s", stats)
    return combined, stats


def validate_label_encoder(label_encoder: LabelEncoder, train_labels: Sequence[str]) -> None:
    classes = list(label_encoder.classes_)
    if len(classes) != len(set(classes)):
        raise ValueError("LabelEncoder contains duplicate class names.")
    missing = sorted(set(train_labels) - set(classes))
    extra = sorted(set(classes) - set(train_labels))
    if missing or extra:
        raise ValueError(f"LabelEncoder must be built only from training labels. Missing={missing}, extra={extra}")


def validate_splits(
    train_df: pd.DataFrame,
    val_df: pd.DataFrame,
    test_df: pd.DataFrame,
    label_encoder: LabelEncoder,
) -> None:
    split_map = {"train": train_df, "validation": val_df, "test": test_df}
    for name, split in split_map.items():
        if split.empty:
            raise ValueError(f"{name} split is empty.")
        if split["Category"].isna().any() or split["Category"].astype(str).str.strip().eq("").any():
            raise ValueError(f"{name} split contains empty labels.")
        dupes = split["Description"].duplicated(keep=False)
        if dupes.any():
            examples = split.loc[dupes, "Description"].head(3).tolist()
            raise ValueError(f"{name} split contains duplicate messages: {examples}")

    train_labels = set(train_df["Category"])
    for name, split in {"validation": val_df, "test": test_df}.items():
        unseen = sorted(set(split["Category"]) - train_labels)
        if unseen:
            raise ValueError(f"{name} split contains labels unseen during training: {unseen}")

    validate_label_encoder(label_encoder, train_df["Category"].tolist())


def preprocess_texts(df: pd.DataFrame, processor: TransactionPreprocessor) -> pd.DataFrame:
    df = df.copy()
    df["clean_text"] = processor.clean_batch(df["Description"].tolist(), max_workers=4)
    return df


def split_dataset(df: pd.DataFrame, config: TrainingConfig) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, Dict[str, Any]]:
    train_df, temp_df = train_test_split(
        df,
        test_size=0.3,
        random_state=config.seed,
        stratify=df["Category"],
    )
    val_df, test_df = train_test_split(
        temp_df,
        test_size=0.5,
        random_state=config.seed,
        stratify=temp_df["Category"],
    )

    def _ensure_disjoint(left: pd.DataFrame, right: pd.DataFrame, label: str) -> None:
        overlap = set(left["Description"]).intersection(right["Description"])
        if overlap:
            raise RuntimeError(f"Duplicate texts found between {label} splits; aborting to avoid leakage.")

    _ensure_disjoint(train_df, val_df, "train/val")
    _ensure_disjoint(train_df, test_df, "train/test")
    _ensure_disjoint(val_df, test_df, "val/test")

    split_stats = {
        "train": {
            "samples": int(len(train_df)),
            "category_distribution": {k: int(v) for k, v in train_df["Category"].value_counts().to_dict().items()},
        },
        "validation": {
            "samples": int(len(val_df)),
            "category_distribution": {k: int(v) for k, v in val_df["Category"].value_counts().to_dict().items()},
        },
        "test": {
            "samples": int(len(test_df)),
            "category_distribution": {k: int(v) for k, v in test_df["Category"].value_counts().to_dict().items()},
        },
    }
    logger.info("Split statistics: %s", split_stats)
    return train_df.reset_index(drop=True), val_df.reset_index(drop=True), test_df.reset_index(drop=True), split_stats


def oversample_training(train_df: pd.DataFrame, config: TrainingConfig) -> Tuple[List[str], List[str]]:
    if config.oversampling == "none":
        return train_df["clean_text"].tolist(), train_df["Category"].tolist()

    if config.oversampling == "random":
        sampler = RandomOverSampler(random_state=config.seed, sampling_strategy="not majority")
    elif config.oversampling == "smote":
        logger.warning("SMOTE is not suitable for raw text data; falling back to RandomOverSampler")
        sampler = RandomOverSampler(random_state=config.seed, sampling_strategy="not majority")
    elif config.oversampling == "adasyn":
        logger.warning("ADASYN is not suitable for raw text data; falling back to RandomOverSampler")
        sampler = RandomOverSampler(random_state=config.seed, sampling_strategy="not majority")
    else:
        raise ValueError(f"Unsupported oversampling strategy: {config.oversampling}")

    X_resampled, y_resampled = sampler.fit_resample(train_df[["clean_text"]], train_df["Category"])
    return X_resampled["clean_text"].tolist(), y_resampled.tolist()


def compute_class_weights(labels: Sequence[str]) -> Optional[Dict[str, float]]:
    labels_array = np.array(labels)
    classes = sorted(set(labels_array))
    if len(classes) < 2:
        return None
    weights = compute_class_weight("balanced", classes=classes, y=labels_array)
    return {label: float(weight) for label, weight in zip(classes, weights)}


def compute_metrics(y_true: Sequence[str], y_pred: Sequence[str], labels: Sequence[str]) -> Dict[str, Any]:
    unknown_preds = sorted(set(y_pred) - set(labels))
    if unknown_preds:
        raise ValueError(f"Predictions contain labels not present in the training label encoder: {unknown_preds}")
    unseen_true = sorted(set(y_true) - set(labels))
    if unseen_true:
        raise ValueError(f"Evaluation data contains labels not present in the training label encoder: {unseen_true}")
    active_labels = [label for label in labels if label in set(y_true) or label in set(y_pred)]
    report = classification_report(
        y_true,
        y_pred,
        labels=active_labels,
        target_names=active_labels,
        output_dict=True,
        zero_division=0,
    )
    cm = confusion_matrix(y_true, y_pred, labels=labels)
    precision, recall, f1, _ = precision_recall_fscore_support(y_true, y_pred, labels=active_labels, average="weighted", zero_division=0)
    macro_precision, macro_recall, _, _ = precision_recall_fscore_support(y_true, y_pred, labels=active_labels, average="macro", zero_division=0)
    macro_f1 = f1_score(y_true, y_pred, labels=active_labels, average="macro", zero_division=0)
    balanced_acc = balanced_accuracy_score(y_true, y_pred)
    mcc = matthews_corrcoef(y_true, y_pred)
    acc = accuracy_score(y_true, y_pred)
    per_class = {
        label: float(acc_value)
        for label, acc_value in zip(labels, cm.diagonal() / np.maximum(cm.sum(axis=1), 1))
    }
    return {
        "accuracy": float(acc),
        "precision": float(precision),
        "recall": float(recall),
        "macro_precision": float(macro_precision),
        "macro_recall": float(macro_recall),
        "weighted_f1": float(f1),
        "macro_f1": float(macro_f1),
        "balanced_accuracy": float(balanced_acc),
        "matthews_corrcoef": float(mcc),
        "confusion_matrix": cm.tolist(),
        "per_class_accuracy": per_class,
        "classification_report": report,
        "per_class_metrics": {label: report[label] for label in labels if label in report},
    }


def evaluate_split(model: TransactionClassifier, df: pd.DataFrame, split_name: str, labels: Sequence[str]) -> Dict[str, Any]:
    clean_texts = df["clean_text"].tolist() if "clean_text" in df.columns else None
    raw_texts = df["Description"].tolist()
    batch_results = model.predict_batch(raw_texts, clean_texts)
    preds = [category for category, _conf, _meta in batch_results]
    metrics = compute_metrics(df["Category"].tolist(), preds, labels)
    logger.info("=== %s Report ===", split_name)
    logger.info("%s", classification_report(df["Category"].tolist(), preds, zero_division=0))
    return metrics


def save_training_plots(history: Sequence[Dict[str, Any]], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    if not history:
        return

    def extract(metric_name: str):
        x = []
        y = []
        for entry in history:
            if metric_name in entry and entry.get("epoch") is not None:
                x.append(entry["epoch"])
                y.append(entry[metric_name])
        return x, y

    # ---------------- Loss ----------------
    train_loss_x, train_loss_y = extract("loss")
    val_loss_x, val_loss_y = extract("eval_loss")

    if train_loss_y or val_loss_y:
        plt.figure(figsize=(8, 5))
        if train_loss_y:
            plt.plot(train_loss_x, train_loss_y, label="train_loss")
        if val_loss_y:
            plt.plot(val_loss_x, val_loss_y, label="val_loss")
        plt.xlabel("Epoch")
        plt.ylabel("Loss")
        plt.title("Training and Validation Loss")
        plt.legend()
        plt.tight_layout()
        plt.savefig(output_dir / "loss_vs_epoch.png", dpi=200)
        plt.savefig(output_dir / "loss.png", dpi=200)
        plt.close()

    # ---------------- Accuracy ----------------
    val_acc_x, val_acc_y = extract("eval_accuracy")

    if val_acc_y:
        plt.figure(figsize=(8, 5))
        plt.plot(val_acc_x, val_acc_y, label="val_accuracy")
        plt.xlabel("Epoch")
        plt.ylabel("Accuracy")
        plt.title("Training and Validation Accuracy")
        plt.legend()
        plt.tight_layout()
        plt.savefig(output_dir / "accuracy_vs_epoch.png", dpi=200)
        plt.savefig(output_dir / "accuracy.png", dpi=200)
        plt.close()

    # ---------------- Weighted F1 ----------------
    val_f1_x, val_f1_y = extract("eval_weighted_f1")

    if val_f1_y:
        plt.figure(figsize=(8, 5))
        plt.plot(val_f1_x, val_f1_y, label="val_weighted_f1")
        plt.xlabel("Epoch")
        plt.ylabel("Weighted F1")
        plt.title("Weighted F1 Over Epochs")
        plt.legend()
        plt.tight_layout()
        plt.savefig(output_dir / "weighted_f1_vs_epoch.png", dpi=200)
        plt.savefig(output_dir / "f1.png", dpi=200)
        plt.close()

    lr_x, lr_y = extract("learning_rate")
    if lr_y:
        plt.figure(figsize=(8, 5))
        plt.plot(lr_x, lr_y, label="learning_rate")
        plt.xlabel("Epoch")
        plt.ylabel("Learning Rate")
        plt.title("Learning Rate Schedule")
        plt.legend()
        plt.tight_layout()
        plt.savefig(output_dir / "learning_rate_curve.png", dpi=200)
        plt.savefig(output_dir / "learning_rate.png", dpi=200)
        plt.close()

def save_confusion_matrix_image(cm: Sequence[Sequence[float]], labels: Sequence[str], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(8, 6))
    plt.imshow(cm, interpolation="nearest", cmap="Blues")
    plt.title("Confusion Matrix")
    plt.colorbar()
    tick_marks = range(len(labels))
    plt.xticks(tick_marks, labels, rotation=45, ha="right")
    plt.yticks(tick_marks, labels)
    for row_idx, row in enumerate(cm):
        for col_idx, value in enumerate(row):
            plt.text(col_idx, row_idx, int(value), ha="center", va="center", color="black")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def save_normalized_confusion_matrix_image(cm: Sequence[Sequence[float]], labels: Sequence[str], output_path: Path) -> None:
    matrix = np.array(cm, dtype=float)
    row_sums = matrix.sum(axis=1, keepdims=True)
    normalized = np.divide(matrix, np.maximum(row_sums, 1.0))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(8, 6))
    plt.imshow(normalized, interpolation="nearest", cmap="Blues", vmin=0.0, vmax=1.0)
    plt.title("Normalized Confusion Matrix")
    plt.colorbar()
    tick_marks = range(len(labels))
    plt.xticks(tick_marks, labels, rotation=45, ha="right")
    plt.yticks(tick_marks, labels)
    for row_idx, row in enumerate(normalized):
        for col_idx, value in enumerate(row):
            plt.text(col_idx, row_idx, f"{value:.2f}", ha="center", va="center", color="black")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300)
    plt.close()


def save_per_class_f1_image(per_class_metrics: Dict[str, Dict[str, float]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    labels = list(per_class_metrics.keys())
    f1_scores = [float(per_class_metrics[label].get("f1-score", 0.0)) for label in labels]
    if not labels:
        return
    plt.figure(figsize=(10, 5))
    plt.bar(labels, f1_scores)
    plt.xticks(rotation=45, ha="right")
    plt.ylim(0, 1)
    plt.ylabel("F1")
    plt.title("Per-class F1")
    plt.tight_layout()
    plt.savefig(output_path, dpi=200)
    plt.close()


def get_latest_checkpoint(output_dir: Path) -> Optional[Path]:
    if not output_dir.exists():
        return None
    checkpoints = sorted([path for path in output_dir.iterdir() if path.is_dir() and path.name.startswith("checkpoint")])
    return checkpoints[-1] if checkpoints else None


def create_experiment_dir(base_dir: Path, experiment_name: Optional[str]) -> Path:
    if experiment_name:
        experiment_dir = base_dir / experiment_name
    else:
        experiment_dir = base_dir / f"experiment_{len(list(base_dir.glob('experiment_*')))+1:03d}"
    experiment_dir.mkdir(parents=True, exist_ok=True)
    return experiment_dir


def save_training_summary(path: Path, summary: Dict[str, Any]) -> None:
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")


def benchmark_prediction(model: TransactionClassifier, texts: Sequence[str], clean_texts: Sequence[str], repeats: int = 20) -> Dict[str, float]:
    import time as py_time

    if not texts:
        return {"average_latency_ms": 0.0, "throughput_samples_per_sec": 0.0, "samples_per_sec": 0.0}
    start = py_time.perf_counter()
    for _ in range(repeats):
        model.predict_batch(list(texts), list(clean_texts))
    elapsed = py_time.perf_counter() - start
    avg_latency_ms = (elapsed / repeats) * 1000.0
    batch_latency_ms = (elapsed / repeats) * 1000.0
    throughput = (len(texts) * repeats) / max(elapsed, 1e-9)
    single_start = py_time.perf_counter()
    for text, clean in zip(list(texts)[:1], list(clean_texts)[:1]):
        model.predict(text, clean)
    single_latency_ms = (py_time.perf_counter() - single_start) * 1000.0
    return {
        "average_latency_ms": float(single_latency_ms),
        "batch_latency_ms": float(batch_latency_ms),
        "throughput_samples_per_sec": float(throughput),
        "samples_per_sec": float(throughput),
    }


def collect_resource_benchmarks(model_dir: Path, training_time: float, inference_benchmark: Dict[str, float]) -> Dict[str, Any]:
    gpu_memory_mb = None
    if torch.cuda.is_available():
        gpu_memory_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
    cpu_memory_mb = None
    try:
        import psutil
        cpu_memory_mb = psutil.Process(os.getpid()).memory_info().rss / (1024 ** 2)
    except Exception:
        cpu_memory_mb = None
    model_size_mb = sum(path.stat().st_size for path in model_dir.glob("**/*") if path.is_file()) / (1024 ** 2)
    return {
        "training_time_seconds": float(training_time),
        "gpu_peak_memory_mb": None if gpu_memory_mb is None else float(gpu_memory_mb),
        "cpu_memory_mb": None if cpu_memory_mb is None else float(cpu_memory_mb),
        "model_size_mb": float(model_size_mb),
        "inference": inference_benchmark,
    }


def verify_onnx_model(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"ONNX model file not found at {path}")

    import onnx
    import onnxruntime as ort

    model = onnx.load(str(path))
    onnx.checker.check_model(model)
    ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])


def export_to_onnx(classifier: TransactionClassifier, output_dir: Path, max_length: int) -> None:
    if classifier.model is None or classifier.tokenizer is None:
        raise RuntimeError("Cannot export ONNX model before classifier model/tokenizer are loaded.")

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "model.onnx"

    try:
        classifier.model.eval()
        sample = classifier.tokenizer(
            "sample transaction sms",
            return_tensors="pt",
            max_length=max_length,
            padding="max_length",
            truncation=True,
        )
        inputs = tuple(tensor.to(classifier.device) for tensor in (sample["input_ids"], sample["attention_mask"]))
        torch.onnx.export(
            classifier.model,
            inputs,
            output_path,
            input_names=["input_ids", "attention_mask"],
            output_names=["logits"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "sequence"},
                "attention_mask": {0: "batch", 1: "sequence"},
                "logits": {0: "batch"},
            },
            opset_version=14,
        )
        classifier.tokenizer.save_pretrained(output_dir)
        if hasattr(classifier.tokenizer, "backend_tokenizer") and classifier.tokenizer.backend_tokenizer is not None:
            tokenizer_json_path = output_dir / "tokenizer.json"
            if not tokenizer_json_path.exists():
                classifier.tokenizer.backend_tokenizer.save(str(tokenizer_json_path))

        classifier.model.config.id2label = classifier.id2label
        classifier.model.config.label2id = classifier.label2id
        classifier.model.config.save_pretrained(output_dir)

        _save_json(output_dir / "id2label.json", classifier.id2label)
        _save_json(output_dir / "label2id.json", classifier.label2id)
        metadata = {
            "labels": classifier.get_labels(),
            "rule_threshold": classifier.rule_threshold,
            "ml_threshold": classifier.ml_threshold,
            "embed_threshold": classifier.embed_threshold,
            "max_length": classifier.max_length,
            "base_model": classifier.base_model,
            "embedder_model": classifier.embedder_model,
            "use_sentence_fallback": classifier.use_sentence_fallback,
            "fallback_category": classifier.fallback_category,
            "temperature": classifier.temperature,
            "export_format": "onnx",
            "export_backend": "torch.onnx.export",
        }
        _save_json(output_dir / "metadata.json", metadata)

        verify_onnx_model(output_path)

        try:
            rel_location = output_path.relative_to(ROOT).as_posix()
        except ValueError:
            rel_location = str(output_path)

        print("==================================================")
        print("ONNX export completed successfully")
        print()
        print("Location:")
        print(rel_location)
        print()
        print("Model verification:")
        print("PASSED")
        print()
        print("==================================================")
    except Exception as exc:
        logger.exception("ONNX export failed: %s", exc)
        raise


def next_model_version_dir(model_root: Path) -> Path:
    existing = []
    for path in model_root.iterdir() if model_root.exists() else []:
        if path.is_dir() and path.name.startswith("v") and path.name[1:].isdigit():
            existing.append(int(path.name[1:]))
    return model_root / f"v{(max(existing) if existing else 0) + 1}"


def copy_model_dir(source: Path, destination: Path) -> None:
    if destination.exists():
        import shutil
        shutil.rmtree(destination)
    import shutil
    shutil.copytree(source, destination)


def save_benchmark_markdown(path: Path, benchmark: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# TransactAI Benchmark",
        "",
        f"- Training time: {benchmark.get('training_time_seconds', 0):.2f}s",
        f"- Inference latency: {benchmark.get('inference', {}).get('average_latency_ms', 0):.2f} ms",
        f"- Batch latency: {benchmark.get('inference', {}).get('batch_latency_ms', 0):.2f} ms",
        f"- Throughput: {benchmark.get('inference', {}).get('throughput_samples_per_sec', 0):.2f} samples/sec",
        f"- GPU memory: {benchmark.get('gpu_peak_memory_mb')}",
        f"- CPU RAM: {benchmark.get('cpu_memory_mb')}",
        f"- Model size: {benchmark.get('model_size_mb', 0):.2f} MB",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate_project_report(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# TransactAI Model Report",
        "",
        "## Dataset Statistics",
        json.dumps(payload.get("dataset_statistics", {}), indent=2),
        "",
        "## Training Metrics",
        json.dumps(payload.get("metrics", {}), indent=2),
        "",
        "## Benchmark",
        json.dumps(payload.get("benchmark", {}), indent=2),
        "",
        "## Artifacts",
        f"- Confusion matrix: {payload.get('confusion_matrix')}",
        f"- Normalized confusion matrix: {payload.get('normalized_confusion_matrix')}",
        f"- Training plots: {payload.get('plots_dir')}",
        f"- TensorBoard logs: {payload.get('tensorboard_dir')}",
        "",
        "## Model Information",
        json.dumps(payload.get("model_metadata", {}), indent=2),
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def train(config: Optional[TrainingConfig] = None, feedback_df: Optional[pd.DataFrame] = None) -> Dict[str, Any]:
    config = config or TrainingConfig()
    _set_seed(config.seed)
    configure_logging(LOG_DIR / "training.log")

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    for path in (METRICS_DIR, OUTPUT_PLOTS_DIR, EXPORT_DIR, ONNX_DIR, BENCHMARK_DIR, README_DIR, REPORT_DIR):
        path.mkdir(parents=True, exist_ok=True)
    PLOTS_DIR.mkdir(parents=True, exist_ok=True)
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    experiment_dir = create_experiment_dir(RUNS_DIR, config.experiment_name)
    experiment_dir.mkdir(parents=True, exist_ok=True)

    start_time = time.time()
    logger.info("=== Loading datasets ===")
    base_df, dataset_stats = prepare_dataset(config)

    if feedback_df is not None and not feedback_df.empty:
        if {"Description", "Category"}.difference(feedback_df.columns):
            raise RuntimeError("feedback_df must contain 'Description' and 'Category' columns")
        logger.info("Appending %s feedback rows", len(feedback_df))
        base_df = pd.concat([base_df, feedback_df], ignore_index=True)

    base_df = base_df.drop_duplicates(subset=["Description", "Category"]).reset_index(drop=True)
    if base_df.empty:
        raise RuntimeError("Dataset empty after filtering.")

    processor = TransactionPreprocessor()
    logger.info("=== Cleaning text corpus ===")
    preprocess_start = time.time()
    df = preprocess_texts(base_df, processor)
    preprocess_time = time.time() - preprocess_start

    logger.info("=== Splitting data ===")
    train_df, val_df, test_df, split_stats = split_dataset(df, config)
    logger.info("Split sizes -> train: %s | val: %s | test: %s", len(train_df), len(val_df), len(test_df))

    label_encoder = LabelEncoder()
    label_encoder.fit(train_df["Category"].tolist())
    labels = list(label_encoder.classes_)
    validate_splits(train_df, val_df, test_df, label_encoder)

    train_texts, train_labels = oversample_training(train_df, config)
    class_weights = compute_class_weights(train_labels) if config.class_weights else None
    logger.info("Using class weights: %s", bool(class_weights))

    classifier = TransactionClassifier(device="cuda" if torch.cuda.is_available() else "cpu")
    classifier.fallback_category = str(train_df["Category"].mode().iloc[0])

    training_output_dir = MODEL_DIR / "classifier_ckpts"
    training_output_dir.mkdir(parents=True, exist_ok=True)
    resume_from_checkpoint = None
    if config.resume:
        resume_from_checkpoint = get_latest_checkpoint(training_output_dir)
        if resume_from_checkpoint:
            logger.info("Resuming from %s", resume_from_checkpoint)

    train_start = time.time()
    logger.info("=== Training DistilBERT head ===")
    trainer = classifier.train(
        texts=train_texts,
        labels=train_labels,
        val_data=(val_df["clean_text"].tolist(), val_df["Category"].tolist()),
        output_dir=str(training_output_dir),
        epochs=config.epochs,
        batch_size=config.batch_size,
        learning_rate=config.learning_rate,
        weight_decay=config.weight_decay,
        warmup_ratio=config.warmup_ratio,
        logging_steps=config.logging_steps,
        max_length=config.max_length,
        use_fp16=config.fp16 if config.fp16 is not None else torch.cuda.is_available(),
        class_weights=class_weights,
        resume_from_checkpoint=str(resume_from_checkpoint) if resume_from_checkpoint else None,
        training_args_overrides={
            "gradient_accumulation_steps": config.gradient_accumulation_steps,
            "eval_steps": config.eval_steps,
            "save_steps": config.save_steps,
            "logging_strategy": "steps",
            "evaluation_strategy": "epoch",
            "save_strategy": "epoch",
            "save_total_limit": 2,
            "load_best_model_at_end": True,
            "metric_for_best_model": "eval_weighted_f1",
            "greater_is_better": True,
            "max_grad_norm": config.max_grad_norm,
            "early_stopping_patience": config.early_stopping_patience,
            "logging_dir": str(experiment_dir),
            "report_to": ["tensorboard"],
        },
        callbacks=None,
        cache_dir=config.cache_dir,
        optimizer_name=config.optimizer,
        lr_scheduler_type=config.lr_scheduler_type,
        label_smoothing_factor=config.label_smoothing_factor,
        use_gradient_checkpointing=True,
        dataloader_pin_memory=torch.cuda.is_available(),
        persistent_workers=False,
        prefetch_factor=None,
        use_torch_compile=config.enable_torch_compile,
    )
    train_time = time.time() - train_start

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    version_dir = next_model_version_dir(MODEL_DIR) if config.enable_versioning else MODEL_DIR / "classifier"
    classifier.save(dir_path=str(MODEL_DIR), name=version_dir.name)
    copy_model_dir(version_dir, MODEL_DIR / "latest")
    if version_dir.resolve() != (MODEL_DIR / "classifier").resolve():
        copy_model_dir(version_dir, MODEL_DIR / "classifier")
    classifier.save(dir_path=str(EXPORT_DIR.parent), name=EXPORT_DIR.name)
    label_encoder_payload = {"classes": labels, "source": "training_split_only"}
    _save_json(EXPORT_DIR / "label_encoder.json", label_encoder_payload)

    logger.info("=== Evaluating ===")
    eval_start = time.time()
    val_metrics = evaluate_split(classifier, val_df, "Validation", labels)
    test_metrics = evaluate_split(classifier, test_df, "Holdout Test", labels)
    eval_time = time.time() - eval_start

    history = []
    if trainer is not None and hasattr(trainer, "state") and hasattr(trainer.state, "log_history"):
        history = trainer.state.log_history

    metrics = {
        "val": val_metrics,
        "test": test_metrics,
        "comparison": {
            "validation_accuracy": val_metrics["accuracy"],
            "test_accuracy": test_metrics["accuracy"],
            "validation_weighted_f1": val_metrics["weighted_f1"],
            "test_weighted_f1": test_metrics["weighted_f1"],
            "validation_macro_f1": val_metrics["macro_f1"],
            "test_macro_f1": test_metrics["macro_f1"],
        },
        "timing": {
            "data_loading": 0.0,
            "preprocessing": preprocess_time,
            "training": train_time,
            "evaluation": eval_time,
            "total": time.time() - start_time,
        },
    }

    metrics_path = MODEL_DIR / "classifier_metrics.json"
    outputs_metrics_path = METRICS_DIR / "metrics.json"
    classification_report_path = MODEL_DIR / "classification_report.json"
    training_history_path = MODEL_DIR / "training_history.json"
    dataset_stats_path = MODEL_DIR / "dataset_statistics.json"
    split_stats_path = MODEL_DIR / "split_statistics.json"
    metadata_path = MODEL_DIR / "model_metadata.json"
    output_metadata_path = EXPORT_DIR / "model_metadata.json"

    _save_json(metrics_path, metrics)
    _save_json(outputs_metrics_path, metrics)
    _save_json(classification_report_path, {
        "validation": val_metrics["classification_report"],
        "test": test_metrics["classification_report"],
    })
    _save_json(training_history_path, history)
    _save_json(dataset_stats_path, dataset_stats)
    _save_json(split_stats_path, split_stats)

    git_commit = None
    try:
        git_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, stderr=subprocess.STDOUT).decode().strip()
    except Exception:
        git_commit = None

    if config.quantize:
        try:
            import torch.quantization as quantization
            logger.info("Quantization requested")
        except Exception as exc:
            logger.warning("Quantization skipped: %s", exc)

    benchmark = benchmark_prediction(classifier, test_df["Description"].head(100).tolist(), test_df["clean_text"].head(100).tolist())
    metadata = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "training_date": datetime.now(timezone.utc).isoformat(),
        "dataset_hash": _get_dataset_hash([df]),
        "dataset_size": int(len(df)),
        "git_commit": git_commit,
        "git_hash": git_commit,
        "transformer_model": classifier.base_model,
        "number_of_classes": int(len(labels)),
        "gpu_used": bool(torch.cuda.is_available()),
        "pytorch_version": torch.__version__,
        "cuda_version": torch.version.cuda,
        "training_config": {
            "epochs": config.epochs,
            "batch_size": config.batch_size,
            "learning_rate": config.learning_rate,
            "weight_decay": config.weight_decay,
            "warmup_ratio": config.warmup_ratio,
            "max_length": config.max_length,
            "seed": config.seed,
            "oversampling": config.oversampling,
            "class_weights": config.class_weights,
            "fp16": config.fp16 if config.fp16 is not None else torch.cuda.is_available(),
            "optimizer": config.optimizer,
            "lr_scheduler_type": config.lr_scheduler_type,
            "label_smoothing_factor": config.label_smoothing_factor,
            "find_lr": config.find_lr,
            "quantize": config.quantize,
            "export_onnx": config.export_onnx,
        },
        "metrics": metrics["comparison"],
        "benchmark": benchmark,
        "experiment_dir": str(experiment_dir),
    }
    _save_json(metadata_path, metadata)
    _save_json(output_metadata_path, metadata)
    _save_json(EXPORT_DIR / "training_config.json", metadata["training_config"])
    _save_json(EXPORT_DIR / "metrics.json", metrics)
    _save_json(EXPORT_DIR / "training_history.json", {"history": history})

    if config.export_onnx:
        export_to_onnx(classifier, ONNX_DIR, config.max_length)

    save_training_plots(history, PLOTS_DIR)
    save_training_plots(history, OUTPUT_PLOTS_DIR)
    save_confusion_matrix_image(test_metrics["confusion_matrix"], labels, PLOTS_DIR / "confusion_matrix.png")
    save_confusion_matrix_image(test_metrics["confusion_matrix"], labels, OUTPUT_PLOTS_DIR / "confusion_matrix.png")
    save_normalized_confusion_matrix_image(test_metrics["confusion_matrix"], labels, OUTPUT_PLOTS_DIR / "confusion_matrix_normalized.png")
    save_per_class_f1_image(test_metrics["per_class_metrics"], OUTPUT_PLOTS_DIR / "per_class_f1.png")

    benchmark_payload = collect_resource_benchmarks(EXPORT_DIR, train_time, benchmark)
    _save_json(BENCHMARK_DIR / "benchmark.json", benchmark_payload)
    save_benchmark_markdown(BENCHMARK_DIR / "benchmark.md", benchmark_payload)
    readme_payload = {
        "dataset_statistics": dataset_stats,
        "class_distribution": dataset_stats["category_distribution"],
        "training_summary": {
            "training_time_seconds": round(train_time, 2),
            "device": classifier.device,
            "cuda_available": torch.cuda.is_available(),
        },
        "evaluation_summary": metrics["comparison"],
        "hyperparameters": metadata["training_config"],
    }
    _save_json(README_DIR / "readme_support.json", readme_payload)
    generate_project_report(
        REPORT_DIR / "README.md",
        {
            "dataset_statistics": dataset_stats,
            "metrics": metrics["comparison"],
            "benchmark": benchmark_payload,
            "confusion_matrix": str(OUTPUT_PLOTS_DIR / "confusion_matrix.png"),
            "normalized_confusion_matrix": str(OUTPUT_PLOTS_DIR / "confusion_matrix_normalized.png"),
            "plots_dir": str(OUTPUT_PLOTS_DIR),
            "tensorboard_dir": str(experiment_dir),
            "model_metadata": metadata,
        },
    )

    summary = {
        "dataset_statistics": dataset_stats,
        "hyperparameters": metadata["training_config"],
        "hardware": {
            "cuda_available": torch.cuda.is_available(),
            "device": classifier.device,
        },
        "training_time_seconds": round(train_time, 2),
        "metrics": metrics["comparison"],
        "best_checkpoint": str(training_output_dir),
        "model_version": str(version_dir),
        "confusion_matrix_image": str(PLOTS_DIR / "confusion_matrix.png"),
    }
    save_training_summary(experiment_dir / "training_summary.md", summary)

    logger.info("=== Training pipeline completed successfully ===")
    logger.info("Final metrics: %s", metrics["comparison"])

    print("\n=== Final Summary ===")
    print(f"Dataset Size: {len(df)}")
    print(f"Training Time: {train_time:.2f}s")
    print(f"Validation Accuracy: {val_metrics['accuracy']:.4f}")
    print(f"Test Accuracy: {test_metrics['accuracy']:.4f}")
    print(f"Weighted F1: {test_metrics['weighted_f1']:.4f}")
    print(f"Macro F1: {test_metrics['macro_f1']:.4f}")
    print(f"Model Size: {sum(p.stat().st_size for p in MODEL_DIR.glob('**/*') if p.is_file()) / 1024:.2f} KB")
    print(f"GPU Used: {'yes' if torch.cuda.is_available() else 'no'}")
    print(f"Peak RAM: n/a")
    print(f"Peak GPU Memory: n/a")
    return {
        "model_dir": str(MODEL_DIR / "classifier"),
        "metrics_path": str(metrics_path),
        "classification_report_path": str(classification_report_path),
        "training_history_path": str(training_history_path),
        "dataset_stats_path": str(dataset_stats_path),
        "split_stats_path": str(split_stats_path),
        "model_metadata_path": str(metadata_path),
        "onnx_dir": str(ONNX_DIR),
        "benchmark_path": str(BENCHMARK_DIR / "benchmark.json"),
        "report_path": str(REPORT_DIR / "README.md"),
    }


def train_with_feedback(feedback_df: Optional[pd.DataFrame] = None) -> Dict[str, Any]:
    return train(feedback_df=feedback_df)


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    config = TrainingConfig(
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
        weight_decay=args.weight_decay,
        warmup_ratio=args.warmup_ratio,
        max_length=args.max_length,
        seed=args.seed,
        oversampling=args.oversampling,
        class_weights=args.class_weights,
        fp16=args.fp16,
        resume=args.resume,
        datasets=args.dataset or ["training_dataset.xlsx"],
        optimizer=args.optimizer,
        lr_scheduler_type=args.lr_scheduler_type,
        label_smoothing_factor=args.label_smoothing,
        find_lr=args.find_lr,
        quantize=args.quantize,
        export_onnx=args.export_onnx,
        experiment_name=args.experiment_name,
        cache_dir=args.cache_dir,
        enable_versioning=args.enable_versioning,
        enable_torch_compile=args.enable_torch_compile,
    )
    train(config=config)


if __name__ == "__main__":
    train()

