"""
Regression tests for the nightly-retrain scheduler import fix.

The scheduler previously had `train_with_feedback` commented out in its
imports (``# from training.train_model import train_with_feedback``), so
the first call to ``run_nightly_retrain()`` at 3:00 AM raised
``NameError: name 'train_with_feedback' is not defined`` and the retrain
never ran.

These tests import the real module — exercising the dual-import fallback
(``backend.*`` -> bare ``core.*`` / ``training.*``) — and assert the
symbols that were previously missing are now importable and callable.

No database is needed: ``api.db`` only builds a lazy SQLAlchemy engine at
import time and never opens a connection during import.
"""

import importlib
import os
import unittest


class SchedulerRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # api/db.py raises RuntimeError at import time without these env
        # vars. Values are only used to build a lazy engine — no connection
        # is opened during import.
        os.environ.setdefault("DB_HOST", "localhost")
        os.environ.setdefault("DB_USER", "test_user")
        os.environ.setdefault("DB_PORT", "6543")
        os.environ.setdefault("DB_NAME", "test_db")
        os.environ.setdefault("DB_PASS", "test")

    def test_train_with_feedback_is_importable(self) -> None:
        scheduler = importlib.import_module("api.scheduler")
        self.assertTrue(callable(scheduler.train_with_feedback))

    def test_run_nightly_retrain_is_importable(self) -> None:
        scheduler = importlib.import_module("api.scheduler")
        self.assertTrue(callable(scheduler.run_nightly_retrain))

    def test_nightly_retrain_reference_resolves(self) -> None:
        # The exact call site that used to NameError must resolve: the
        # scheduler thread body invokes train_with_feedback(feedback_df).
        scheduler = importlib.import_module("api.scheduler")
        self.assertIs(scheduler.run_nightly_retrain.__globals__["train_with_feedback"],
                      scheduler.train_with_feedback)


if __name__ == "__main__":
    unittest.main()
