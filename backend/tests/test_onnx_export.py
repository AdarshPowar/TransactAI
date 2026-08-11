import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, patch
import torch

from training.train_model import verify_onnx_model, export_to_onnx


class ONNXExportTests(unittest.TestCase):
    def test_verify_onnx_model_file_not_found(self):
        with self.assertRaises(FileNotFoundError):
            verify_onnx_model(Path("/non/existent/path/model.onnx"))

    @patch("onnxruntime.InferenceSession")
    @patch("onnx.checker.check_model")
    @patch("onnx.load")
    def test_verify_onnx_model_success(self, mock_load, mock_check, mock_session):
        with TemporaryDirectory() as tmp_dir:
            model_path = Path(tmp_dir) / "model.onnx"
            model_path.write_bytes(b"dummy onnx content")

            verify_onnx_model(model_path)
            mock_load.assert_called_once_with(str(model_path))
            mock_check.assert_called_once()
            mock_session.assert_called_once_with(str(model_path), providers=["CPUExecutionProvider"])

    @patch("training.train_model.verify_onnx_model")
    @patch("torch.onnx.export")
    def test_export_to_onnx_generates_all_files(self, mock_torch_export, mock_verify):
        with TemporaryDirectory() as tmp_dir:
            output_dir = Path(tmp_dir) / "classifier_onnx"
            
            mock_classifier = MagicMock()
            mock_classifier.model = MagicMock()
            mock_classifier.tokenizer = MagicMock()
            mock_classifier.device = "cpu"
            mock_classifier.id2label = {0: "FOOD", 1: "SHOPPING"}
            mock_classifier.label2id = {"FOOD": 0, "SHOPPING": 1}
            mock_classifier.get_labels.return_value = ["FOOD", "SHOPPING"]
            mock_classifier.rule_threshold = 0.8
            mock_classifier.ml_threshold = 0.7
            mock_classifier.embed_threshold = 0.85
            mock_classifier.max_length = 128
            mock_classifier.base_model = "distilbert-base-uncased"
            mock_classifier.embedder_model = "all-MiniLM-L6-v2"
            mock_classifier.use_sentence_fallback = True
            mock_classifier.fallback_category = "MISCELLANEOUS"
            mock_classifier.temperature = 1.0

            # Mock tokenizer output
            mock_classifier.tokenizer.return_value = {
                "input_ids": torch.tensor([[1, 2, 3]]),
                "attention_mask": torch.tensor([[1, 1, 1]]),
            }

            export_to_onnx(mock_classifier, output_dir, max_length=128)

            # Check that required files are created or saved via tokenizer/config save_pretrained
            mock_torch_export.assert_called_once()
            mock_classifier.tokenizer.save_pretrained.assert_called_once_with(output_dir)
            mock_classifier.model.config.save_pretrained.assert_called_once_with(output_dir)
            mock_verify.assert_called_once_with(output_dir / "model.onnx")

            self.assertTrue((output_dir / "id2label.json").exists())
            self.assertTrue((output_dir / "label2id.json").exists())
            self.assertTrue((output_dir / "metadata.json").exists())


if __name__ == "__main__":
    unittest.main()
