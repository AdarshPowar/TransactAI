from pathlib import Path
from onnxruntime.quantization import quantize_dynamic, QuantType

source = Path("models/classifier_onnx/model.onnx")
output = Path("models/classifier_onnx/model.int8.onnx")

print("=" * 70)
print("TRANSactAI - ONNX INT8 QUANTIZATION")
print("=" * 70)

if not source.exists():
    raise FileNotFoundError(f"Source model not found: {source}")

print(f"Source : {source.resolve()}")
print(f"Size   : {source.stat().st_size / (1024 * 1024):.2f} MB")

print("\n[1/2] Quantizing to INT8...")

quantize_dynamic(
    model_input=str(source),
    model_output=str(output),
    weight_type=QuantType.QInt8,
    per_channel=True,
    reduce_range=False,
)

print("\n[2/2] Checking output...")

if not output.exists():
    raise RuntimeError("Quantization failed: output model was not created.")

size_mb = output.stat().st_size / (1024 * 1024)

print(f"INT8 model: {output.resolve()}")
print(f"INT8 size : {size_mb:.2f} MB")

print("\nQUANTIZATION SUCCESSFUL")
print("=" * 70)
