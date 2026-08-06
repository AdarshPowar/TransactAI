# core/model.py
#
# Hybrid classifier that layers:
#   1. Deterministic rule engine for high-confidence shortcuts.
#   2. DistilBERT fine-tuned sequence classifier.
#   3. SentenceTransformer centroids for cosine-based fallbacks.
# The code keeps the training/prediction signatures stable so the CLI
# pipeline (`python -m training.train_model`) can orchestrate end-to-end runs.

from __future__ import annotations

import importlib
import json
import os
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np
import torch
import torch.nn.functional as F
from sklearn.metrics import accuracy_score, f1_score, precision_recall_fscore_support
from torch.utils.data import Dataset
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    DataCollatorWithPadding,
    EarlyStoppingCallback,
    Trainer,
    TrainingArguments,
)

try:
    from datasets import Dataset as HFDataset
except ImportError:  # pragma: no cover - optional dependency fallback
    HFDataset = None

try:
    from backend.core.preprocessor import TransactionPreprocessor
    from backend.core.rules import RuleEngine, RuleMatch
except ModuleNotFoundError:  # pragma: no cover - legacy import fallback
    from core.preprocessor import TransactionPreprocessor
    from core.rules import RuleEngine, RuleMatch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CACHE_DIR = PROJECT_ROOT / "backend" / ".cache" / "hf_datasets"


class _TextClassificationDataset(Dataset):
    """Minimal HF-friendly dataset for plain text + integer labels."""

    def __init__(self, texts: Sequence[str], labels: Sequence[int], tokenizer, max_length: int):
        self.texts = list(texts)
        self.labels = list(labels)
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self) -> int:
        return len(self.texts)

    def __getitem__(self, idx: int) -> Dict[str, torch.Tensor]:
        encoding = self.tokenizer(
            self.texts[idx],
            truncation=True,
            max_length=self.max_length,
        )
        encoding["labels"] = self.labels[idx]
        return encoding


class TransactionClassifier:
    """Trainable classifier with optional sentence-transformer fallback."""

    def __init__(
        self,
        base_model: str = "distilbert-base-uncased",
        embedder_model: str = "sentence-transformers/all-MiniLM-L6-v2",
        max_length: int = 256,
        rule_threshold: float = 0.90,
        ml_threshold: float = 0.70,
        embed_threshold: float = 0.60,
        use_sentence_fallback: bool = True,
        device: Optional[str] = None,
        rule_engine: Optional[RuleEngine] = None,
    ):
        self.base_model = base_model
        self.embedder_model = embedder_model
        self.max_length = max_length
        self.rule_threshold = rule_threshold
        self.ml_threshold = ml_threshold
        self.embed_threshold = embed_threshold
        self.use_sentence_fallback = use_sentence_fallback
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.fallback_category = "Others"
        self.temperature = 1.0

        self.preprocessor = TransactionPreprocessor()
        self.rule_engine = rule_engine or RuleEngine()

        self.tokenizer = None
        self.model = None
        self.embedder = None
        self.label2id: Dict[str, int] = {}
        self.id2label: Dict[int, str] = {}
        self.centroid_labels: List[str] = []
        self.centroid_matrix: Optional[torch.Tensor] = None

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #
    def _ensure_label_maps(self, labels: Sequence[str]):
        if self.label2id:
            return
        unique = sorted(set(labels))
        self.label2id = {label: idx for idx, label in enumerate(unique)}
        self.id2label = {idx: label for label, idx in self.label2id.items()}

    def _metrics_fn(self):
        def compute_metrics(eval_pred):
            logits, labels = eval_pred
            preds = np.argmax(logits, axis=-1)
            precision, recall, f1, _ = precision_recall_fscore_support(
                labels, preds, average="weighted", zero_division=0
            )
            macro_f1 = f1_score(labels, preds, average="macro", zero_division=0)
            acc = accuracy_score(labels, preds)
            return {
                "accuracy": acc,
                "weighted_f1": f1,
                "macro_f1": macro_f1,
                "precision": precision,
                "recall": recall,
            }

        return compute_metrics

    def _auto_batch_size(self, requested: int) -> int:
        if requested <= 0:
            raise ValueError("batch_size must be >= 1")
        if not torch.cuda.is_available() or "cuda" not in self.device:
            return requested
        try:
            props = torch.cuda.get_device_properties(torch.device(self.device))
            total_gb = props.total_memory / (1024 ** 3)
        except Exception:
            return min(requested, 16)

        if total_gb < 6:
            return min(requested, 8)
        if total_gb < 10:
            return min(requested, 16)
        if total_gb < 14:
            return min(requested, 24)
        return requested

    def _resolve_cache_dir(self, cache_dir: Optional[str]) -> Path:
        if cache_dir is None:
            resolved_cache_dir = DEFAULT_CACHE_DIR
        else:
            raw_cache_dir = str(cache_dir).strip()
            if not raw_cache_dir:
                resolved_cache_dir = DEFAULT_CACHE_DIR
            else:
                candidate_path = Path(raw_cache_dir)
                if not candidate_path.is_absolute():
                    resolved_cache_dir = (PROJECT_ROOT / candidate_path).resolve()
                else:
                    resolved_cache_dir = candidate_path.resolve()

        if resolved_cache_dir.exists() and not resolved_cache_dir.is_dir():
            raise ValueError(f"Invalid cache directory '{resolved_cache_dir}': path exists but is not a directory.")

        try:
            resolved_cache_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise ValueError(f"Invalid cache directory '{resolved_cache_dir}': {exc}") from exc

        if not resolved_cache_dir.exists() or not resolved_cache_dir.is_dir():
            raise ValueError(f"Invalid cache directory '{resolved_cache_dir}': directory could not be created.")

        return resolved_cache_dir

    def _validate_hf_dataset_schema(self, dataset, split_name: str) -> None:
        column_names = list(dataset.column_names)
        if column_names.count("labels") != 1:
            raise ValueError(
                f"{split_name} dataset must contain exactly one 'labels' column; "
                f"found {column_names.count('labels')} in columns {column_names}."
            )

        required_columns = {"input_ids", "attention_mask", "labels"}
        missing_columns = sorted(required_columns - set(column_names))
        if missing_columns:
            raise ValueError(
                f"{split_name} dataset is missing required columns: {missing_columns}. "
                f"Current columns: {column_names}."
            )

    def _create_datasets(
        self,
        texts: Sequence[str],
        labels: Sequence[str],
        val_data: Optional[Tuple[Sequence[str], Sequence[str]]] = None,
        cache_dir: Optional[str] = None,
    ):
        train_ids = [self.label2id[label] for label in labels]
        resolved_cache_dir = self._resolve_cache_dir(cache_dir)
        train_ds = self._build_hf_dataset(texts, train_ids, resolved_cache_dir, split_name="train")
        self._validate_hf_dataset_schema(train_ds, "train")

        val_ds = None
        if val_data:
            val_texts, val_labels = val_data
            val_ids = [self.label2id[label] for label in val_labels]
            val_ds = self._build_hf_dataset(val_texts, val_ids, resolved_cache_dir, split_name="validation")
            self._validate_hf_dataset_schema(val_ds, "validation")
        return train_ds, val_ds

    def _build_hf_dataset(self, texts: Sequence[str], labels: Sequence[int], cache_dir: Optional[str], split_name: str):
        if not texts:
            return None
        if HFDataset is None:
            raise ImportError("datasets is required for cached Hugging Face dataset creation. Install it via `pip install datasets`.")

        resolved_cache_dir = self._resolve_cache_dir(cache_dir)
        os.environ["HF_DATASETS_CACHE"] = str(resolved_cache_dir)
        hf_dataset = HFDataset.from_dict({"text": list(texts), "labels": list(labels)})
        hf_dataset = hf_dataset.map(
            lambda batch: self.tokenizer(
                batch["text"],
                truncation=True,
                max_length=self.max_length,
                padding=False,
            ),
            batched=True,
            batch_size=1000,
            remove_columns=["text"],
            cache_file_name=str(resolved_cache_dir / f"{split_name}.arrow"),
            num_proc=1,
        )
        return hf_dataset

    def _ensure_embedder(self):
        if self.embedder is not None or not self.use_sentence_fallback:
            return self.embedder
        try:
            st_module = importlib.import_module("sentence_transformers")
        except ImportError as exc:
            raise ImportError(
                "sentence-transformers is required for embedding fallback. "
                "Install it via `pip install sentence-transformers`."
            ) from exc

        SentenceTransformerCls = getattr(st_module, "SentenceTransformer")
        embed_device = self.device if "cuda" in self.device else "cpu"
        self.embedder = SentenceTransformerCls(self.embedder_model, device=embed_device)
        return self.embedder

    def _encode_embeddings(self, texts: Sequence[str]) -> Optional[torch.Tensor]:
        if not texts or not self.use_sentence_fallback:
            return None
        embedder = self._ensure_embedder()
        if embedder is None:
            return None
        with torch.inference_mode():
            return embedder.encode(
                list(texts),
                batch_size=64,
                normalize_embeddings=True,
                convert_to_tensor=True,
                show_progress_bar=False,
            ).to(self.device)

    def _build_label_centroids(self, texts: Sequence[str], labels: Sequence[str]):
        if not self.use_sentence_fallback:
            self.centroid_matrix = None
            self.centroid_labels = []
            return

        vectors = self._encode_embeddings(texts)
        if vectors is None:
            return

        by_label: Dict[str, List[int]] = {label: [] for label in self.label2id}
        for idx, label in enumerate(labels):
            if label in by_label:
                by_label[label].append(idx)

        centroids: List[torch.Tensor] = []
        centroid_labels: List[str] = []
        for label, indices in by_label.items():
            if not indices:
                continue
            centroid = vectors[indices].mean(dim=0)
            centroid = F.normalize(centroid, dim=-1)
            centroids.append(centroid)
            centroid_labels.append(label)

        if centroids:
            self.centroid_matrix = torch.stack(centroids).to(self.device)
            self.centroid_labels = centroid_labels

    def _predict_transformer(self, clean_texts: Sequence[str]):
        inputs = self.tokenizer(
            list(clean_texts),
            truncation=True,
            padding=True,
            max_length=self.max_length,
            return_tensors="pt",
        )
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        with torch.inference_mode():
            logits = self.model(**inputs).logits
            if self.temperature <= 0:
                raise ValueError("temperature must be > 0.")
            logits = logits / self.temperature
            probs = torch.softmax(logits, dim=-1)

        conf, ids = torch.max(probs, dim=-1)
        categories = [self.id2label[int(i)] for i in ids.cpu().tolist()]
        return categories, conf.cpu().tolist(), probs.cpu()

    def _predict_embeddings(self, clean_texts: Sequence[str]):
        if not self.use_sentence_fallback or self.centroid_matrix is None:
            return [None] * len(clean_texts), [0.0] * len(clean_texts)
        vectors = self._encode_embeddings(clean_texts)
        if vectors is None:
            return [None] * len(clean_texts), [0.0] * len(clean_texts)
        similarities = torch.matmul(vectors, self.centroid_matrix.T)
        best_scores, best_idx = torch.max(similarities, dim=-1)

        cats = []
        for idx in best_idx.cpu().tolist():
            if 0 <= idx < len(self.centroid_labels):
                cats.append(self.centroid_labels[idx])
            else:
                cats.append(None)
        return cats, best_scores.cpu().tolist()

    def _combine_with_embeddings(
        self,
        rule_match: Optional[RuleMatch],
        ml_category: str,
        ml_conf: float,
        embed_category: Optional[str],
        embed_conf: float,
    ) -> Tuple[str, float, str]:
        if rule_match and rule_match.category not in self.label2id:
            rule_match = None
        if ml_category not in self.label2id:
            ml_category = self.fallback_category
            ml_conf = min(ml_conf, 0.35)
        if embed_category is not None and embed_category not in self.label2id:
            embed_category = None
            embed_conf = 0.0
        rule_conf = rule_match.confidence if rule_match else 0.0

        if embed_category is None or embed_conf < self.embed_threshold:
            if ml_conf >= self.ml_threshold:
                return ml_category, ml_conf, "ML"
            if rule_conf >= 0.5:
                return rule_match.category, rule_conf, "RULE_LOW"
            return self.fallback_category, 0.35, "FALLBACK"

        if embed_category == ml_category:
            boosted = min(0.5 * ml_conf + 0.3 * embed_conf + 0.2 * rule_conf, 0.99)
            return ml_category, boosted, "HYBRID"

        if embed_conf > ml_conf:
            blended = min(0.6 * embed_conf + 0.2 * ml_conf + 0.2 * rule_conf, 0.95)
            return embed_category, blended, "EMBED_FALLBACK"

        if ml_conf >= self.ml_threshold:
            return ml_category, ml_conf, "ML"
        return self.fallback_category, max(ml_conf, embed_conf) * 0.9, "FALLBACK"

    def _assert_ready(self):
        if self.model is None or self.tokenizer is None:
            raise RuntimeError("Model/tokenizer not loaded. Call train() or load() first.")

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #
    def train(
        self,
        texts: Iterable[str],
        labels: Iterable[str],
        val_data: Optional[Tuple[Sequence[str], Sequence[str]]] = None,
        output_dir: str = "models/classifier_ckpts",
        epochs: int = 3,
        batch_size: int = 16,
        learning_rate: float = 2e-5,
        weight_decay: float = 0.01,
        warmup_ratio: float = 0.06,
        logging_steps: int = 50,
        max_length: Optional[int] = None,
        use_fp16: Optional[bool] = None,
        class_weights: Optional[Dict[str, float]] = None,
        resume_from_checkpoint: Optional[str] = None,
        training_args_overrides: Optional[Dict[str, Any]] = None,
        callbacks: Optional[List[Any]] = None,
        cache_dir: Optional[str] = None,
        optimizer_name: str = "adamw",
        lr_scheduler_type: str = "cosine",
        label_smoothing_factor: float = 0.0,
        dataloader_num_workers: Optional[int] = None,
        dataloader_pin_memory: Optional[bool] = None,
        persistent_workers: Optional[bool] = None,
        prefetch_factor: Optional[int] = None,
        use_gradient_checkpointing: bool = True,
        use_torch_compile: bool = False,
    ):
        texts = list(texts)
        labels = list(labels)
        if not texts:
            raise ValueError("Dataset is empty — cannot train.")

        self.max_length = max_length or self.max_length
        self._ensure_label_maps(labels)

        self.tokenizer = AutoTokenizer.from_pretrained(self.base_model)
        self.model = AutoModelForSequenceClassification.from_pretrained(
            self.base_model,
            num_labels=len(self.label2id),
            id2label={str(idx): label for idx, label in self.id2label.items()},
            label2id=self.label2id,
        ).to(self.device)

        if use_gradient_checkpointing and hasattr(self.model, "gradient_checkpointing_enable"):
            self.model.gradient_checkpointing_enable()
        if use_torch_compile and hasattr(torch, "compile"):
            self.model = torch.compile(self.model)

        train_ds, val_ds = self._create_datasets(texts, labels, val_data, cache_dir=cache_dir)
        collator = DataCollatorWithPadding(self.tokenizer)

        fp16_flag = use_fp16 if use_fp16 is not None else torch.cuda.is_available()
        auto_batch = self._auto_batch_size(batch_size)

        class_weights_tensor = None
        if class_weights:
            weights = [class_weights.get(self.id2label[idx], 1.0) for idx in range(len(self.id2label))]
            class_weights_tensor = torch.tensor(weights, dtype=torch.float32, device=self.device)

        if optimizer_name.lower() not in {"adamw", "adam", "sgd"}:
            raise ValueError(f"Unsupported optimizer: {optimizer_name}")

        class WeightedTrainer(Trainer):
            def __init__(self, *args, class_weight_tensor=None, **kwargs):
                super().__init__(*args, **kwargs)
                self.class_weight_tensor = class_weight_tensor

            def compute_loss(self, model, inputs, return_outputs=False, **kwargs):
                labels = inputs.pop("labels")
                outputs = model(**inputs)
                logits = outputs.get("logits")
                if self.class_weight_tensor is None:
                    loss_fct = torch.nn.CrossEntropyLoss()
                    loss = loss_fct(logits.view(-1, model.config.num_labels), labels.view(-1))
                else:
                    loss_fct = torch.nn.CrossEntropyLoss(weight=self.class_weight_tensor.to(model.device))
                    loss = loss_fct(logits.view(-1, model.config.num_labels), labels.view(-1))
                return (loss, outputs) if return_outputs else loss

        args_overrides = training_args_overrides or {}
        chosen_precision = "bf16" if torch.cuda.is_available() and torch.cuda.is_bf16_supported() else "fp16" if fp16_flag else "no"
        early_stopping_patience = int(args_overrides.get("early_stopping_patience", 3))
        args = TrainingArguments(
            output_dir=output_dir,
            learning_rate=learning_rate,
            per_device_train_batch_size=auto_batch,
            per_device_eval_batch_size=auto_batch,
            num_train_epochs=epochs,
            weight_decay=weight_decay,
            warmup_ratio=warmup_ratio,
            logging_steps=logging_steps,
            evaluation_strategy="epoch" if val_ds else "no",
            save_strategy="epoch",
            save_total_limit=2,
            load_best_model_at_end=bool(val_ds),
            metric_for_best_model="eval_weighted_f1",
            greater_is_better=True,
            fp16=(chosen_precision == "fp16"),
            bf16=(chosen_precision == "bf16"),
            report_to=args_overrides.get("report_to", ["tensorboard"]),
            gradient_accumulation_steps=args_overrides.get("gradient_accumulation_steps", 1),
            eval_steps=args_overrides.get("eval_steps", 50),
            save_steps=args_overrides.get("save_steps", 50),
            logging_strategy=args_overrides.get("logging_strategy", "steps"),
            lr_scheduler_type=lr_scheduler_type,
            label_smoothing_factor=label_smoothing_factor,
            max_grad_norm=args_overrides.get("max_grad_norm", 1.0),
            dataloader_num_workers=dataloader_num_workers if dataloader_num_workers is not None else 0,
            dataloader_pin_memory=dataloader_pin_memory if dataloader_pin_memory is not None else torch.cuda.is_available(),
            dataloader_persistent_workers=bool(persistent_workers) if dataloader_num_workers else False,
            dataloader_prefetch_factor=prefetch_factor if dataloader_num_workers else None,
            **{k: v for k, v in args_overrides.items() if k not in {"gradient_accumulation_steps", "eval_steps", "save_steps", "logging_strategy", "report_to", "evaluation_strategy", "eval_strategy", "save_strategy", "save_total_limit", "load_best_model_at_end", "metric_for_best_model", "greater_is_better", "max_grad_norm", "early_stopping_patience"}},
        )

        callback_list = list(callbacks or [])
        if val_ds:
            callback_list.append(EarlyStoppingCallback(early_stopping_patience=early_stopping_patience, early_stopping_threshold=0.0))

        trainer = WeightedTrainer(
            model=self.model,
            args=args,
            train_dataset=train_ds,
            eval_dataset=val_ds,
            data_collator=collator,
            compute_metrics=self._metrics_fn(),
            class_weight_tensor=class_weights_tensor,
            callbacks=callback_list,
        )

        trainer.train(resume_from_checkpoint=resume_from_checkpoint)
        self.model.eval()

        self._build_label_centroids(texts, labels)
        return trainer

    def predict(
        self,
        raw_text: str,
        clean_text: Optional[str] = None,
    ) -> Tuple[str, float, Dict[str, Any]]:
        return self.predict_batch([raw_text], [clean_text] if clean_text is not None else None)[0]

    def predict_batch(
        self,
        raw_texts: Sequence[str],
        clean_texts: Optional[Sequence[Optional[str]]] = None,
    ) -> List[Tuple[str, float, Dict[str, Any]]]:
        self._assert_ready()

        if not raw_texts:
            return []
        raw_texts = list(raw_texts)
        if clean_texts is not None and len(clean_texts) != len(raw_texts):
            raise ValueError("clean_texts must match raw_texts length.")

        if clean_texts is None:
            clean_texts = [self.preprocessor.clean(text) for text in raw_texts]
        else:
            clean_texts = [
                clean if clean else self.preprocessor.clean(raw)
                for raw, clean in zip(raw_texts, clean_texts)
            ]

        outputs: List[Optional[Tuple[str, float, Dict[str, Any]]]] = [None] * len(raw_texts)
        rule_matches: List[Optional[RuleMatch]] = [None] * len(raw_texts)
        pending_indices: List[int] = []

        for idx, (raw, clean) in enumerate(zip(raw_texts, clean_texts)):
            match = self.rule_engine.evaluate(raw, clean, min_confidence=0.5)
            if match and match.category not in self.label2id:
                match = None
            rule_matches[idx] = match
            if match and match.confidence >= self.rule_threshold:
                outputs[idx] = (
                    match.category,
                    match.confidence,
                    {
                        "strategy": "RULE",
                        "clean_text": clean,
                        "rule": match.to_dict(),
                    },
                )
            else:
                pending_indices.append(idx)

        if pending_indices:
            pending_clean = [clean_texts[i] for i in pending_indices]
            ml_cats, ml_conf, ml_probs = self._predict_transformer(pending_clean)
            low_conf_indices: List[int] = []
            low_conf_texts: List[str] = []
            ml_results: Dict[int, Dict[str, Any]] = {}

            for local_idx, global_idx in enumerate(pending_indices):
                cat = ml_cats[local_idx]
                conf = ml_conf[local_idx]
                prob_vec = ml_probs[local_idx].tolist()
                ml_results[global_idx] = {"category": cat, "confidence": conf, "probs": prob_vec}

                if conf >= self.ml_threshold:
                    outputs[global_idx] = (
                        cat,
                        conf,
                        {
                            "strategy": "ML",
                            "clean_text": clean_texts[global_idx],
                            "rule": rule_matches[global_idx].to_dict()
                            if rule_matches[global_idx]
                            else None,
                            "ml": ml_results[global_idx],
                        },
                    )
                else:
                    low_conf_indices.append(global_idx)
                    low_conf_texts.append(clean_texts[global_idx])

            if low_conf_indices:
                embed_cats, embed_conf = self._predict_embeddings(low_conf_texts)
                for idx_in_list, global_idx in enumerate(low_conf_indices):
                    embed_cat = embed_cats[idx_in_list]
                    embed_score = embed_conf[idx_in_list]
                    ml_info = ml_results[global_idx]

                    final_cat, final_conf, strategy = self._combine_with_embeddings(
                        rule_matches[global_idx],
                        ml_info["category"],
                        ml_info["confidence"],
                        embed_cat,
                        embed_score,
                    )

                    outputs[global_idx] = (
                        final_cat,
                        final_conf,
                        {
                            "strategy": strategy,
                            "clean_text": clean_texts[global_idx],
                            "rule": rule_matches[global_idx].to_dict()
                            if rule_matches[global_idx]
                            else None,
                            "ml": ml_info,
                            "embedding": {"category": embed_cat, "score": embed_score}
                            if embed_cat
                            else None,
                        },
                    )

        for idx, result in enumerate(outputs):
            if result is None:
                match = rule_matches[idx]
                fallback = self.fallback_category if self.fallback_category in self.label2id else next(iter(self.label2id))
                outputs[idx] = (
                    fallback,
                    0.35,
                    {
                        "strategy": "FALLBACK",
                        "clean_text": clean_texts[idx],
                        "rule": match.to_dict() if match else None,
                    },
                )

        return outputs  # type: ignore[return-value]

    def predict_top_k(
        self,
        raw_text: str,
        clean_text: Optional[str] = None,
        k: int = 3,
    ) -> List[Dict[str, Any]]:
        self._assert_ready()
        if k < 1:
            raise ValueError("k must be >= 1.")
        clean = clean_text or self.preprocessor.clean(raw_text)
        inputs = self.tokenizer(
            [clean],
            truncation=True,
            padding=True,
            max_length=self.max_length,
            return_tensors="pt",
        )
        inputs = {key: value.to(self.device) for key, value in inputs.items()}
        with torch.inference_mode():
            logits = self.model(**inputs).logits
            if self.temperature <= 0:
                raise ValueError("temperature must be > 0.")
            probs = torch.softmax(logits / self.temperature, dim=-1)[0]
        top_k = min(k, len(self.id2label))
        scores, indices = torch.topk(probs, k=top_k)
        return [
            {"category": self.id2label[int(index)], "confidence": float(score)}
            for score, index in zip(scores.cpu().tolist(), indices.cpu().tolist())
        ]

    def set_temperature(self, temperature: float) -> None:
        if temperature <= 0:
            raise ValueError("temperature must be > 0.")
        self.temperature = float(temperature)

    def explain(self, raw_text: str, clean_text: Optional[str] = None, top_k: int = 10) -> Dict[str, Any]:
        self._assert_ready()
        try:
            from captum.attr import LayerIntegratedGradients
        except Exception as exc:
            raise ImportError("captum is required for token importance explanations.") from exc

        clean = clean_text or self.preprocessor.clean(raw_text)
        encoded = self.tokenizer(
            clean,
            truncation=True,
            padding=True,
            max_length=self.max_length,
            return_tensors="pt",
        )
        input_ids = encoded["input_ids"].to(self.device)
        attention_mask = encoded["attention_mask"].to(self.device)

        def forward_func(ids, mask):
            return self.model(input_ids=ids, attention_mask=mask).logits

        with torch.inference_mode():
            pred_id = int(torch.argmax(forward_func(input_ids, attention_mask), dim=-1)[0])

        lig = LayerIntegratedGradients(forward_func, self.model.distilbert.embeddings)
        attributions = lig.attribute(
            inputs=input_ids,
            additional_forward_args=(attention_mask,),
            target=pred_id,
            n_steps=16,
        )
        scores = attributions.sum(dim=-1).squeeze(0).detach().cpu().tolist()
        tokens = self.tokenizer.convert_ids_to_tokens(input_ids.squeeze(0).detach().cpu().tolist())
        token_scores = [
            {"token": token, "importance": float(score)}
            for token, score in zip(tokens, scores)
            if token not in {"[CLS]", "[SEP]", "[PAD]"}
        ]
        token_scores = sorted(token_scores, key=lambda item: abs(item["importance"]), reverse=True)
        return {
            "category": self.id2label[pred_id],
            "token_importance": token_scores[:top_k],
            "top_contributing_words": [item["token"] for item in token_scores[:top_k]],
        }

    def get_labels(self) -> List[str]:
        return list(self.label2id.keys())

    def save(self, dir_path: str = "models", name: str = "classifier"):
        self._assert_ready()
        path = Path(dir_path) / name
        path.mkdir(parents=True, exist_ok=True)

        self.model.save_pretrained(path)
        self.tokenizer.save_pretrained(path)

        metadata = {
            "labels": self.get_labels(),
            "rule_threshold": self.rule_threshold,
            "ml_threshold": self.ml_threshold,
            "embed_threshold": self.embed_threshold,
            "max_length": self.max_length,
            "base_model": self.base_model,
            "embedder_model": self.embedder_model,
            "use_sentence_fallback": self.use_sentence_fallback,
            "fallback_category": self.fallback_category,
            "temperature": self.temperature,
        }
        with open(path / "metadata.json", "w", encoding="utf-8") as fh:
            json.dump(metadata, fh, indent=2)

        with open(path / "label2id.json", "w", encoding="utf-8") as fh:
            json.dump(self.label2id, fh, indent=2)
        with open(path / "id2label.json", "w", encoding="utf-8") as fh:
            json.dump(self.id2label, fh, indent=2)

        if self.centroid_matrix is not None and self.centroid_labels:
            torch.save(
                {
                    "labels": self.centroid_labels,
                    "embeddings": self.centroid_matrix.detach().cpu(),
                },
                path / "label_centroids.pt",
            )

    def load(self, dir_path: str = "models", name: str = "classifier"):
        path = Path(dir_path) / name
        if not path.exists():
            raise FileNotFoundError(f"Saved model not found at {path}")

        self.tokenizer = AutoTokenizer.from_pretrained(path)
        self.model = AutoModelForSequenceClassification.from_pretrained(path).to(self.device)
        self.model.eval()

        meta_path = path / "metadata.json"
        if not meta_path.exists():
            raise FileNotFoundError("metadata.json missing — cannot restore classifier state.")
        with open(meta_path, encoding="utf-8") as fh:
            metadata = json.load(fh)

        label2_path = path / "label2id.json"
        id2_path = path / "id2label.json"
        if label2_path.exists() and id2_path.exists():
            with open(label2_path, encoding="utf-8") as fh:
                stored_label2id = json.load(fh)
            with open(id2_path, encoding="utf-8") as fh:
                stored_id2label = json.load(fh)
            self.label2id = {str(k): int(v) for k, v in stored_label2id.items()}
            # ensure ints keys
            self.id2label = {int(k): str(v) for k, v in stored_id2label.items()}
        else:
            labels = metadata.get("labels", [])
            self.label2id = {label: idx for idx, label in enumerate(labels)}
            self.id2label = {idx: label for label, idx in enumerate(labels)}
        self.rule_threshold = metadata.get("rule_threshold", self.rule_threshold)
        self.ml_threshold = metadata.get("ml_threshold", self.ml_threshold)
        self.embed_threshold = metadata.get("embed_threshold", self.embed_threshold)
        self.max_length = metadata.get("max_length", self.max_length)
        self.base_model = metadata.get("base_model", self.base_model)
        self.embedder_model = metadata.get("embedder_model", self.embedder_model)
        self.use_sentence_fallback = metadata.get(
            "use_sentence_fallback",
            self.use_sentence_fallback,
        )
        self.fallback_category = metadata.get("fallback_category", self.fallback_category)
        self.temperature = float(metadata.get("temperature", self.temperature))

        centroids_path = path / "label_centroids.pt"
        if centroids_path.exists():
            payload = torch.load(centroids_path, map_location=self.device)
            self.centroid_labels = payload.get("labels", [])
            embeddings = payload.get("embeddings")
            if embeddings is not None:
                self.centroid_matrix = embeddings.to(self.device)
        else:
            self.centroid_labels = []
            self.centroid_matrix = None

