"""
Regression tests for the /classify request-field parsing fix.

The endpoint previously read the fallback field and then unconditionally
overwrote it with a second assignment::

    text = payload.get("sms_text") or payload.get("message")
    text = payload.get("message")   # <-- BUG: sms_text ignored

So a request that sent only ``sms_text`` (and no ``message``) was rejected
with HTTP 400, even though the documented schema accepts either field.

The fix removed the second assignment, so the first non-empty of
``sms_text`` / ``message`` wins.

Why these are source-level guards: ``api.main`` cannot be imported inside
a unit test without a live PostgreSQL — it opens a psycopg2 connection
pool at import time, and ``api.budget`` executes a ``CREATE TABLE`` via
``engine.begin()`` at import time. These assertions therefore pin down the
exact regression in the source of ``classify()`` instead.
"""

import unittest
from pathlib import Path

MAIN_PY = Path(__file__).resolve().parent.parent / "api" / "main.py"


class ClassifyFieldParsingRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = MAIN_PY.read_text(encoding="utf-8")

    def test_requires_both_fields_are_considered(self) -> None:
        # The correct fallback expression (sms_text first, then message)
        # must still be present.
        self.assertIn(
            'payload.get("sms_text") or payload.get("message")',
            self.source,
        )

    def test_no_unconditional_override_statement(self) -> None:
        # The buggy second assignment `text = payload.get("message")` that
        # silently discarded sms_text must be gone.
        self.assertNotIn('text = payload.get("message")', self.source)


if __name__ == "__main__":
    unittest.main()
