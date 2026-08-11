import json
import time
from pathlib import Path
from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

router = APIRouter()
BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models"
OUTPUTS_DIR = BASE_DIR / "outputs"

class PredictRequest(BaseModel):
    text: str


def _get_classifier(request: Request):
    if not hasattr(request.app.state, "classifier") or request.app.state.classifier is None:
        raise HTTPException(status_code=503, detail="Classifier not loaded. Please train the model first.")
    return request.app.state.classifier


def _with_latency(start: float, payload: Dict[str, Any]) -> Dict[str, Any]:
    payload["latency_ms"] = round((time.perf_counter() - start) * 1000.0, 3)
    return payload


@router.get("/health")
def health(request: Request):
    return {
        "status": "ok",
        "model_loaded": bool(getattr(request.app.state, "classifier", None)),
    }


@router.get("/model")
def model_info():
    metadata_path = OUTPUTS_DIR / "model" / "model_metadata.json"
    if metadata_path.exists():
        with open(metadata_path, encoding="utf-8") as handle:
            return json.load(handle)
    return {
        "model_dir": str(MODEL_DIR / "classifier"),
        "onnx_dir": str(MODEL_DIR / "classifier_onnx"),
        "metadata_available": False,
    }


@router.get("/benchmark")
def benchmark():
    benchmark_path = OUTPUTS_DIR / "benchmarks" / "benchmark.json"
    if not benchmark_path.exists():
        raise HTTPException(status_code=404, detail="Benchmark file not found. Train the model to generate it.")
    with open(benchmark_path, encoding="utf-8") as handle:
        return json.load(handle)


@router.post("/predict")
def predict(req: PredictRequest, request: Request):
    """
    Prediction endpoint. Requires classifier to be loaded in app.state.classifier.
    """
    classifier = _get_classifier(request)
    start = time.perf_counter()
    try:
        result = classifier.predict(req.text)
        return _with_latency(start, result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


@router.post("/predict_top3")
def predict_top3(req: PredictRequest, request: Request):
    classifier = _get_classifier(request)
    start = time.perf_counter()
    try:
        if hasattr(classifier, "predict_top_k"):
            top3 = classifier.predict_top_k(req.text, k=3)
        elif hasattr(classifier, "classifier") and hasattr(classifier.classifier, "predict_top_k"):
            clean_text = classifier.preprocessor.clean(req.text)
            top3 = classifier.classifier.predict_top_k(req.text, clean_text, k=3)
        else:
            prediction = classifier.predict(req.text)
            top3 = [{"category": prediction["category"], "confidence": prediction["confidence"]}]
        best = top3[0]
        return _with_latency(
            start,
            {
                "category": best["category"],
                "confidence": float(best["confidence"]),
                "top3_predictions": top3,
            },
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Top-3 prediction failed: {str(e)}")
