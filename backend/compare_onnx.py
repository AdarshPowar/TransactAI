from pathlib import Path
import numpy as np
import onnxruntime as ort
from transformers import AutoTokenizer

MODEL_DIR = Path("models/classifier")
ONNX_DIR = Path("models/classifier_onnx")

tokenizer = AutoTokenizer.from_pretrained(str(MODEL_DIR))

fp32 = ort.InferenceSession(
    str(ONNX_DIR / "model.onnx"),
    providers=["CPUExecutionProvider"]
)

int8 = ort.InferenceSession(
    str(ONNX_DIR / "model.int8.onnx"),
    providers=["CPUExecutionProvider"]
)

tests = [
    "UPI payment of Rs 250 to Swiggy",
    "Rs 500 credited to your account via UPI",
    "Salary credited successfully",
    "ATM cash withdrawal of Rs 2000",
    "Payment of Rs 1200 at Amazon",
    "Recharge of Rs 299 successful",
    "Rs 750 debited from your bank account",
    "Electricity bill payment successful",
    "Received Rs 500 from Rahul",
    "Paid Rs 350 at restaurant",
]

print("=" * 80)
print("FP32 ONNX vs INT8 ONNX COMPARISON")
print("=" * 80)

input_names = {x.name for x in int8.get_inputs()}

for text in tests:
    encoded = tokenizer(
        text,
        return_tensors="np",
        padding="max_length",
        truncation=True,
        max_length=256,
    )

    inputs = {
        "input_ids": encoded["input_ids"].astype(np.int64),
        "attention_mask": encoded["attention_mask"].astype(np.int64),
    }

    fp32_logits = fp32.run(["logits"], inputs)[0]
    int8_logits = int8.run(["logits"], inputs)[0]

    fp32_pred = int(np.argmax(fp32_logits[0]))
    int8_pred = int(np.argmax(int8_logits[0]))

    fp32_probs = np.exp(fp32_logits[0] - np.max(fp32_logits[0]))
    fp32_probs /= fp32_probs.sum()

    int8_probs = np.exp(int8_logits[0] - np.max(int8_logits[0]))
    int8_probs /= int8_probs.sum()

    fp32_conf = float(np.max(fp32_probs))
    int8_conf = float(np.max(int8_probs))

    status = "MATCH" if fp32_pred == int8_pred else "DIFFERENT"

    print(f"\nText: {text}")
    print(f"FP32 : class={fp32_pred}, confidence={fp32_conf:.4f}")
    print(f"INT8 : class={int8_pred}, confidence={int8_conf:.4f}")
    print(f"      {status}")

print("\n" + "=" * 80)
print("COMPARISON COMPLETE")
print("=" * 80)
