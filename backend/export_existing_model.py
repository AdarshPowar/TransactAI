import shutil
from pathlib import Path

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification

SOURCE = Path("models/classifier")
OUTPUT = Path("models/classifier_onnx")
OUTPUT.mkdir(parents=True, exist_ok=True)

print("=" * 70)
print("TRANSactAI - EXISTING MODEL -> ONNX EXPORT")
print("=" * 70)

print(f"Source : {SOURCE.resolve()}")
print(f"Output : {OUTPUT.resolve()}")

# ------------------------------------------------------------
# 1. Load existing trained model
# ------------------------------------------------------------
print("\n[1/4] Loading existing classifier...")

tokenizer = AutoTokenizer.from_pretrained(str(SOURCE))
model = AutoModelForSequenceClassification.from_pretrained(str(SOURCE))
model.eval()
model.cpu()

print("Model loaded successfully.")

# ------------------------------------------------------------
# 2. Copy inference metadata/tokenizer files
# ------------------------------------------------------------
print("\n[2/4] Copying tokenizer/config files...")

files_to_copy = [
    "config.json",
    "id2label.json",
    "label2id.json",
    "metadata.json",
    "special_tokens_map.json",
    "tokenizer_config.json",
    "tokenizer.json",
    "vocab.txt",
]

for filename in files_to_copy:
    src = SOURCE / filename
    dst = OUTPUT / filename

    if src.exists():
        shutil.copy2(src, dst)
        print(f"  copied: {filename}")
    else:
        print(f"  skipped: {filename} (not found)")

# ------------------------------------------------------------
# 3. Export to ONNX
# ------------------------------------------------------------
print("\n[3/4] Exporting model to ONNX...")

output_path = OUTPUT / "model.onnx"

# Use a small dummy sequence for tracing.
# Dynamic axes allow other sequence lengths during inference.
dummy_text = "upi payment of 500 rupees"

inputs = tokenizer(
    dummy_text,
    return_tensors="pt",
    padding="max_length",
    truncation=True,
    max_length=256,
)

input_ids = inputs["input_ids"]
attention_mask = inputs["attention_mask"]


class ONNXWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
        )
        return outputs.logits


wrapper = ONNXWrapper(model)
wrapper.eval()

with torch.no_grad():
    torch.onnx.export(
        wrapper,
        (input_ids, attention_mask),
        str(output_path),
        input_names=["input_ids", "attention_mask"],
        output_names=["logits"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "sequence"},
            "attention_mask": {0: "batch", 1: "sequence"},
            "logits": {0: "batch"},
        },
        opset_version=17,
        do_constant_folding=True,
    )

print(f"ONNX model created: {output_path}")

# ------------------------------------------------------------
# 4. Basic size check
# ------------------------------------------------------------
print("\n[4/4] Checking output...")

if not output_path.exists():
    raise RuntimeError("ONNX export failed: model.onnx was not created.")

size_mb = output_path.stat().st_size / (1024 * 1024)

print(f"ONNX size: {size_mb:.2f} MB")
print("\nEXPORT SUCCESSFUL")
print("=" * 70)
