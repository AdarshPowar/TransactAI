import importlib
import unittest


class TrainingEntrypointTests(unittest.TestCase):
    def test_root_training_module_can_be_imported(self) -> None:
        module = importlib.import_module("training.train_model")
        self.assertTrue(callable(module.main))


if __name__ == "__main__":
    unittest.main()
