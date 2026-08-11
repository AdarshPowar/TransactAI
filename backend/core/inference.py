"""
TransactAI Inference Pipeline
Loads the trained DistilBERT model from core/model.py and performs
hybrid prediction using:
1. Rule-based classifier
2. DistilBERT transformer model
3. Sentence transformer embeddings (fallback)
"""

from pathlib import Path
import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from .preprocessor import TransactionPreprocessor
from .model import TransactionClassifier as ModelTransactionClassifier


BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models"
LOG_DIR = BASE_DIR / "logs" / "predictions"
logger = logging.getLogger("transactai.inference")


def _prediction_logging_enabled() -> bool:
    return os.getenv("TRANSACTAI_LOG_PREDICTIONS", "0").strip().lower() in {"1", "true", "yes"}


def _log_prediction(model_used: str, category: str, confidence: float, latency_ms: float) -> None:
    if not _prediction_logging_enabled():
        return
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "model_used": model_used,
        "category": category,
        "confidence": float(confidence),
        "latency_ms": float(latency_ms),
    }
    with open(LOG_DIR / "predictions.jsonl", "a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False) + "\n")


class TransactionClassifier:
    """
    Main inference engine that wraps the DistilBERT-based TransactionClassifier
    from core/model.py. This provides a consistent interface for the API.
    """

    def __init__(self, model_dir: Optional[str] = None):
        """
        Initialize the classifier. Tries to load a saved model, or creates
        an uninitialized classifier if no model exists yet.
        """
        print("[INFO] Initializing TransactAI inference pipeline...")

        self.preprocessor = TransactionPreprocessor()
        self.classifier = ModelTransactionClassifier()

        # Try to load saved model
        model_path = Path(model_dir) if model_dir else MODEL_DIR / "classifier"
        
        if model_path.exists():
            try:
                print(f"[INFO] Loading saved model from: {model_path}")
                self.classifier.load(dir_path=str(model_path.parent), name=model_path.name)
                print("[INFO] Model loaded successfully.")
            except Exception as e:
                print(f"[WARN] Failed to load saved model: {e}")
                print("[WARN] Classifier will need to be trained before use.")
        else:
            print(f"[WARN] Model directory not found: {model_path}")
            print("[WARN] Classifier will need to be trained before use.")

        print("[INFO] Inference pipeline initialized.")

    def predict(self, raw_text: str, clean_text: Optional[str] = None) -> Dict[str, Any]:
        """
        Performs hybrid classification using:
        1) Rule-based patterns
        2) DistilBERT transformer
        3) Sentence transformer embeddings (fallback)

        Returns:
            Dict with keys: category, confidence, strategy, metadata
        """
        if self.classifier.model is None or self.classifier.tokenizer is None:
            # Fallback to rule-based only if model not loaded
            from .rules import RuleEngine
            rule_engine = RuleEngine()
            match = rule_engine.evaluate(raw_text, clean_text, min_confidence=0.5)
            if match:
                return {
                    "category": match.category,
                    "confidence": float(match.confidence),
                    "strategy": "RULE",
                    "ml_prob": None,
                }
            return {
                "category": "Others",
                "confidence": 0.35,
                "strategy": "FALLBACK",
                "ml_prob": None,
            }

        # Use the model's predict method
        category, confidence, metadata = self.classifier.predict(raw_text, clean_text)
        
        return {
            "category": category,
            "confidence": float(confidence),
            "strategy": metadata.get("strategy", "ML"),
            "ml_prob": float(confidence),
            "metadata": metadata,
        }

    def predict_batch(
        self, raw_texts: list[str], clean_texts: Optional[list[Optional[str]]] = None
    ) -> list[Dict[str, Any]]:
        """
        Predict categories for a batch of texts.
        """
        if self.classifier.model is None or self.classifier.tokenizer is None:
            # Fallback to rule-based only
            from .rules import RuleEngine
            rule_engine = RuleEngine()
            results = []
            for raw_text in raw_texts:
                match = rule_engine.evaluate(raw_text, None, min_confidence=0.5)
                if match:
                    results.append({
                        "category": match.category,
                        "confidence": float(match.confidence),
                        "strategy": "RULE",
                        "ml_prob": None,
                    })
                else:
                    results.append({
                        "category": "Others",
                        "confidence": 0.35,
                        "strategy": "FALLBACK",
                        "ml_prob": None,
                    })
            return results

        # Use the model's predict_batch method
        batch_results = self.classifier.predict_batch(raw_texts, clean_texts)
        
        return [
            {
                "category": category,
                "confidence": float(confidence),
                "strategy": metadata.get("strategy", "ML"),
                "ml_prob": float(confidence),
                "metadata": metadata,
            }
            for category, confidence, metadata in batch_results
        ]


class TransactionPredictor:
    """Reusable production predictor for trained DistilBERT transaction models."""

    def __init__(
        self,
        model_dir: Optional[str] = None,
        enable_latency_logging: Optional[bool] = None,
        temperature: Optional[float] = None,
    ):
        self.preprocessor = TransactionPreprocessor()
        self.classifier = ModelTransactionClassifier()
        model_path = Path(model_dir) if model_dir else MODEL_DIR / "classifier"
        self.classifier.load(dir_path=str(model_path.parent), name=model_path.name)
        if temperature is not None:
            self.classifier.set_temperature(temperature)
        self.enable_latency_logging = _prediction_logging_enabled() if enable_latency_logging is None else enable_latency_logging

    def predict(self, sms_text: str) -> Dict[str, Any]:
        if not isinstance(sms_text, str) or not sms_text.strip():
            raise ValueError("sms_text must be a non-empty string.")

        start = time.perf_counter()
        clean_text = self.preprocessor.clean(sms_text)
        category, confidence, _metadata = self.classifier.predict(sms_text, clean_text)
        top3 = self.classifier.predict_top_k(sms_text, clean_text, k=3)
        valid_labels = set(self.classifier.get_labels())
        if category not in valid_labels:
            raise RuntimeError(f"Model predicted unknown category '{category}'. Valid labels: {sorted(valid_labels)}")
        latency_ms = (time.perf_counter() - start) * 1000.0
        if self.enable_latency_logging:
            _log_prediction("pytorch", category, confidence, latency_ms)

        return {
            "category": category,
            "confidence": round(float(confidence), 4),
            "top3_predictions": top3,
        }

    def predict_top_k(self, sms_text: str, k: int = 3) -> List[Dict[str, Any]]:
        if not isinstance(sms_text, str) or not sms_text.strip():
            raise ValueError("sms_text must be a non-empty string.")
        clean_text = self.preprocessor.clean(sms_text)
        return self.classifier.predict_top_k(sms_text, clean_text, k=k)

    def explain(self, sms_text: str, top_k: int = 10) -> Dict[str, Any]:
        if not isinstance(sms_text, str) or not sms_text.strip():
            raise ValueError("sms_text must be a non-empty string.")
        clean_text = self.preprocessor.clean(sms_text)
        return self.classifier.explain(sms_text, clean_text, top_k=top_k)


class ONNXTransactionPredictor:
    """ONNX Runtime predictor with the same schema as TransactionPredictor."""

    def __init__(self, model_dir: Optional[str] = None, enable_latency_logging: Optional[bool] = None):
        try:
            import onnxruntime as ort
            import numpy as np
            from transformers import AutoTokenizer
        except Exception as exc:
            raise ImportError("onnxruntime, numpy, and transformers are required for ONNX inference.") from exc

        self._np = np
        self.preprocessor = TransactionPreprocessor()
        self.model_dir = Path(model_dir) if model_dir else MODEL_DIR / "classifier_onnx"
        model_path = self.model_dir / "model.onnx"
        if not model_path.exists():
            raise FileNotFoundError(f"ONNX model not found at {model_path}")

        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        available = set(ort.get_available_providers())
        active_providers = [provider for provider in providers if provider in available] or ["CPUExecutionProvider"]
        self.session = ort.InferenceSession(str(model_path), providers=active_providers)
        self.tokenizer = AutoTokenizer.from_pretrained(self.model_dir)
        self.id2label = self._load_id2label()
        self.enable_latency_logging = _prediction_logging_enabled() if enable_latency_logging is None else enable_latency_logging

    def _load_id2label(self) -> Dict[int, str]:
        id2label_path = self.model_dir / "id2label.json"
        if id2label_path.exists():
            with open(id2label_path, encoding="utf-8") as handle:
                payload = json.load(handle)
            return {int(key): str(value) for key, value in payload.items()}
        config_path = self.model_dir / "config.json"
        with open(config_path, encoding="utf-8") as handle:
            config = json.load(handle)
        id2label = config.get("id2label")
        if not id2label:
            raise FileNotFoundError("ONNX model config does not contain id2label mapping.")
        return {int(key): str(value) for key, value in id2label.items()}

    def _predict_probs(self, sms_text: str):
        clean_text = self.preprocessor.clean(sms_text)
        inputs = self.tokenizer(
            clean_text,
            truncation=True,
            padding=True,
            max_length=256,
            return_tensors="np",
        )
        ort_inputs = {
            "input_ids": inputs["input_ids"].astype("int64"),
            "attention_mask": inputs["attention_mask"].astype("int64"),
        }
        logits = self.session.run(None, ort_inputs)[0][0]
        logits = logits - self._np.max(logits)
        exp = self._np.exp(logits)
        return exp / self._np.sum(exp)

    def predict_top_k(self, sms_text: str, k: int = 3) -> List[Dict[str, Any]]:
        if not isinstance(sms_text, str) or not sms_text.strip():
            raise ValueError("sms_text must be a non-empty string.")
        probs = self._predict_probs(sms_text)
        top_indices = probs.argsort()[-min(k, len(probs)):][::-1]
        return [
            {"category": self.id2label[int(index)], "confidence": float(probs[int(index)])}
            for index in top_indices
        ]

    def predict(self, sms_text: str) -> Dict[str, Any]:
        start = time.perf_counter()
        top3 = self.predict_top_k(sms_text, k=3)
        best = top3[0]
        latency_ms = (time.perf_counter() - start) * 1000.0
        if self.enable_latency_logging:
            _log_prediction("onnx", best["category"], best["confidence"], latency_ms)
        return {
            "category": best["category"],
            "confidence": round(float(best["confidence"]), 4),
            "top3_predictions": top3,
        }


def create_predictor(runtime: Optional[str] = None, model_dir: Optional[str] = None):
    selected = (runtime or os.getenv("TRANSACTAI_INFERENCE_BACKEND", "pytorch")).strip().lower()
    if selected in {"onnx", "onnxruntime"}:
        return ONNXTransactionPredictor(model_dir=model_dir)
    if selected in {"pytorch", "torch"}:
        return TransactionPredictor(model_dir=model_dir)
    raise ValueError(f"Unsupported inference backend: {selected}")
