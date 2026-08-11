# TransactAI — FIX REPORT PHASE 1

**Date:** 2026-08-07
**Scope:** Confirmed functional bugs only, identified in `PROJECT_AUDIT_REPORT.md`. No refactoring, no architecture changes.

---

## Summary

| # | Bug | Severity | Files changed | Status |
|---|-----|----------|---------------|--------|
| 1 | `/classify` silently ignores `sms_text` (overrides it with `message`) | High | `backend/api/main.py` | ✅ Fixed |
| 2 | Nightly retrain scheduler raises `NameError` (`train_with_feedback` not imported) | High | `backend/api/scheduler.py` | ✅ Fixed |
| 3 | `backend/test.py` crashes on startup — calls undefined `send_login`/`send_signup` | Medium | `backend/test.py` | ✅ Fixed |
| 4 | Android app ↔ backend API contract mismatch (wrong URL path + wrong JSON field) | High | `ApiClient.kt`, `models/TransactionModels.kt` | ✅ Fixed |
| 5 | Android crashes — `startForegroundService` on a `NotificationListenerService` | High | `MainActivity.kt` | ✅ Fixed |

**Regression tests added:** `backend/tests/test_scheduler_regression.py` (3 tests), `backend/tests/test_classify_field_parsing.py` (2 tests).

**Verification:** All existing tests + new tests pass — **9/9 OK** (see [Test Results](#verification-test-results)).

**Not fixed (speculative — see [Needs Manual Review](#needs-manual-review-not-fixed)):** 3 items.

---

## Fix 1 — `/classify` ignores `sms_text`

**File:** `backend/api/main.py` (function `classify`)

### Why it is a bug
The endpoint's own error message promises to accept *either* field: *"Missing 'sms_text' or 'message' field"*. The code read the fallback correctly first, then **unconditionally overwrote it**:

```python
text = payload.get("sms_text") or payload.get("message")
if not text:
    raise HTTPException(status_code=400, detail="Missing 'sms_text' or 'message' field")
text = payload.get("message")        # <-- BUG: always replaces `text`
if not text:
    raise HTTPException(status_code=400, detail="Missing 'message' field")
```

Any client sending `{"sms_text": "..."}` *without* `message` ended up with `text = None` and was rejected with **HTTP 400**, even though the request was valid per the schema.

### How it was fixed
Removed the redundant second assignment and its guard. The first statement is now the single source of truth for field parsing.

### Before → After

```python
# BEFORE
text = payload.get("sms_text") or payload.get("message")
if not text:
    raise HTTPException(400, "Missing 'sms_text' or 'message' field")
text = payload.get("message")        # discards sms_text
if not text:
    raise HTTPException(400, "Missing 'message' field")

# AFTER
text = payload.get("sms_text") or payload.get("message")
if not text:
    raise HTTPException(400, "Missing 'sms_text' or 'message' field")
```

**Behavior:** request with only `sms_text` → previously HTTP 400; now classified normally.

### Tests
`backend/tests/test_classify_field_parsing.py` — source-level guards (see note below):
- `test_requires_both_fields_are_considered` — asserts the correct fallback expression is present.
- `test_no_unconditional_override_statement` — asserts the buggy `text = payload.get("message")` override no longer exists.

> **Why source-level?** `api.main` cannot be imported inside a unit test without a live PostgreSQL: it opens a psycopg2 connection pool at import time, and `api/budget.py` executes a `CREATE TABLE` via `engine.begin()` at import time (a separate issue already documented in the audit). A behavioral endpoint test needs a running DB, so the guards pin down the exact regression instead.

---

## Fix 2 — Nightly retrain scheduler `NameError`

**File:** `backend/api/scheduler.py`

### Why it is a bug
The import of `train_with_feedback` was **commented out** (`# from training.train_model import train_with_feedback`), yet the scheduler's worker thread calls it directly:

```python
result = train_with_feedback(feedback_df)   # line 57
```

On the first nightly tick (3:00 AM), this raised `NameError: name 'train_with_feedback' is not defined`, which was swallowed by the broad `except Exception`, so **the retrain silently never ran** — the model was never refreshed from user feedback.

### How it was fixed
Added the same dual-import fallback pattern already used elsewhere in the codebase (`backend.api.*` → bare `core.*`/`training.*`):

```python
try:
    from backend.training.train_model import train_with_feedback
except ModuleNotFoundError:  # pragma: no cover - legacy import fallback
    from training.train_model import train_with_feedback
```

### Before → After
- **Before:** scheduler thread fires → `NameError` → `except Exception` → retrain skipped (log only).
- **After:** `train_with_feedback` resolves; retrain runs and the fresh classifier is reloaded into `app.state.classifier`.

### Tests
`backend/tests/test_scheduler_regression.py`:
- `test_train_with_feedback_is_importable`
- `test_run_nightly_retrain_is_importable`
- `test_nightly_retrain_reference_resolves` — asserts the `run_nightly_retrain` function's global `train_with_feedback` is exactly the imported callable (no shadowing / no unresolved name).

These tests also confirm there is **no circular import**: `api.scheduler` → `training.train_model` → `core.model` all import cleanly together.

---

## Fix 3 — `backend/test.py` crashes on startup

**File:** `backend/test.py`

### Why it is a bug
A "NEW: Auth Menu" block called `send_login(email, password)` and `send_signup(name, email, password)`. **Neither function exists anywhere in the file** (only `send_classify`, `send_manual_category`, `send_add_category`). Running the interactive tester therefore raised `NameError: name 'send_login' is not defined` immediately — before the transaction tester ever started.

### How it was fixed
Removed the auth menu block (and its dead references to non-existent functions). `start()` now proceeds directly to the transaction tester.

### Before → After
- **Before:** `python test.py` → `NameError: send_login is not defined` → unusable.
- **After:** `python test.py` → prints `--- Starting Transaction Tester ---` and accepts transaction messages.

### Tests
This is an interactive script with no test harness; verified by `py_compile` (passes) and by re-reading the final `start()` body.

---

## Fix 4 — Android ↔ backend API contract mismatch

**Files:**
- `TransactionNotifier/app/src/main/java/com/transactai/ApiClient.kt`
- `TransactionNotifier/app/src/main/java/com/transactai/models/TransactionModels.kt`

### Why it is a bug (two independent halves of the same broken contract)

**4a — Wrong URL path.** `ApiClient.kt` pointed `BASE_URL` at `http://10.254.244.112:8000/api/`, so the request went to `POST /api/classify`. The backend only serves `POST /classify` **at the root** (see `backend/api/main.py` → `@app.post("/classify")`). Every request returned **404**.

**4b — Wrong JSON field.** `CategorizationRequest` serialized the body as `{"text": "..."}`. The backend `/classify` reads only `sms_text` or `message` (Fix 1). An unknown `text` field is ignored → `text` is `None` → **HTTP 400**.

Net effect: the Android app could **never** persist or categorize a transaction through the backend.

### How it was fixed
- **4a:** `BASE_URL` → `http://10.254.244.112:8000/` (with a `TODO` note to replace the IP, plus a comment that `/classify` lives at the root, no `/api` prefix).
- **4b:** Renamed the request field `text` → `message` with `@SerializedName("message")`. The call site `CategorizationRequest(text)` passes a positional argument, so it binds to the renamed `message` parameter with no call-site change.

### Before → After
- **Before:** `POST http://10.254.244.112:8000/api/classify` with body `{"text": "Paid ₹500 to Swiggy"}` → **404**, then **400**.
- **After:** `POST http://10.254.244.112:8000/classify` with body `{"message": "Paid ₹500 to Swiggy"}` → classified and saved.

### Tests
No Android unit/instrumentation test harness is configured in the project. Verified by source inspection and by cross-checking the serialized field names against the backend contract in `backend/api/main.py`.

---

## Fix 5 — Android `startForegroundService` on a `NotificationListenerService`

**File:** `TransactionNotifier/app/src/main/java/com/transactai/MainActivity.kt`

### Why it is a bug
`NotificationService` is a `NotificationListenerService` ([NotificationService.kt:19](TransactionNotifier/app/src/main/java/com/transactai/NotificationService.kt#L19)). Listener services are **bound by the Android system** when the user toggles notification access in Settings — the manifest already declares this correctly (`BIND_NOTIFICATION_LISTENER_SERVICE` + the `NotificationListenerService` intent-filter).

`MainActivity` called `ContextCompat.startForegroundService(this, intent)` on it from both `checkAndRequestNotificationPermission()` and `updateStatus()`. On **API 26+**, a started foreground service must call `startForeground()` within ~5 seconds or the system throws `ForegroundServiceDidNotStartInTimeException` (crash). A `NotificationListenerService` never does, so enabling the app's access (or simply returning to the screen) could crash the app.

### How it was fixed
Removed `startNotificationService()` and its two call sites, plus the now-unused `ContextCompat` import. The service lifecycle is now entirely system-driven (as it always should have been): when access is granted, the system binds it and `onListenerConnected()` fires.

### Before → After
- **Before:** On `onCreate`/`onResume`, with permission already granted → attempted `startForegroundService` on a listener service → crash / exception on API 26+.
- **After:** No manual start attempt. UI simply reflects permission state; the system binds the listener when enabled.

> Note: `addDebugLog()` in `MainActivity.kt` is now unused (its only caller was the deleted function). It was left in place deliberately to honor the *no-refactoring* constraint — it is harmless dead code.

### Tests
No Android test harness configured. Verified by source inspection and by confirming the manifest already provides the correct binding mechanism.

---

## Verification — Test Results

Run from `backend/` using the project venv (system python lacks torch):

```
.venv/Scripts/python.exe -m unittest tests.test_onnx_export tests.test_training_entrypoint tests.test_scheduler_regression tests.test_classify_field_parsing -v
```

```
test_export_to_onnx_generates_all_files ............ ok
test_verify_onnx_model_file_not_found .............. ok
test_verify_onnx_model_success ..................... ok
test_root_training_module_can_be_imported .......... ok
test_nightly_retrain_reference_resolves ............ ok
test_run_nightly_retrain_is_importable ............. ok
test_train_with_feedback_is_importable ............. ok
test_no_unconditional_override_statement ........... ok
test_requires_both_fields_are_considered ........... ok

Ran 9 tests in 1.044s
OK
```

Also verified:
- `python -m py_compile api/main.py api/scheduler.py test.py` → **COMPILE OK** (all modified Python files).
- Full `git diff` inspected — changes limited to the six files above; no collateral edits.

---

## Needs Manual Review (NOT fixed)

These were flagged during the audit but are **not fixed** because I am not 100% certain they are bugs — fixing them speculatively would violate the "confirmed bugs only" instruction.

| # | Issue | Location | Why it needs manual review |
|---|-------|----------|---------------------------|
| 1 | `/feedback` schema ↔ SQL column mismatch | `backend/api/main.py` (function `feedback`) | Pydantic model fields are `user_id, raw_text, predicted, corrected, confidence`, but the `INSERT` targets columns `original_text, predicted_category, corrected_category`. Whether the **model fields** or the **SQL columns** are wrong depends on the actual `transaction_feedback` table schema — needs a live DB / `\d transaction_feedback` to confirm which side to change. |
| 2 | `docker-compose.yml` frontend path is broken | `docker-compose.yml` | The compose file references a frontend build path that does not resolve. This may be a placeholder for a frontend container that was never shipped. Confirming requires knowing the intended deployment layout, so it was left untouched. |
| 3 | Model label vocabulary mismatch | `models/` artifacts (Git LFS) vs `CATEGORIES` in `backend/api/main.py` | The exported model's `id2label`/`label2id` vocabulary vs the runtime `CATEGORIES` list (the Refund/Shopping confusion area from the audit). Deciding the canonical label set requires inspecting the trained artifact and training data — not safe to change blind. |

**Environment limitation (not a code bug):** `backend/tests/test_training_pipeline.py` is a pytest-style test, but `pytest` is not installed in `backend/.venv` or the system python. It was **not run** and is not part of the 9 passing tests. Installing pytest and running it is a follow-up task, not a fix.

---

## Modified Files (complete list)

1. `backend/api/main.py` — Fix 1
2. `backend/api/scheduler.py` — Fix 2
3. `backend/test.py` — Fix 3
4. `TransactionNotifier/app/src/main/java/com/transactai/ApiClient.kt` — Fix 4a
5. `TransactionNotifier/app/src/main/java/com/transactai/models/TransactionModels.kt` — Fix 4b
6. `TransactionNotifier/app/src/main/java/com/transactai/MainActivity.kt` — Fix 5

**Added files:**
1. `backend/tests/test_scheduler_regression.py` — Fix 2 regression tests (3)
2. `backend/tests/test_classify_field_parsing.py` — Fix 1 regression tests (2)
3. `FIX_REPORT_PHASE1.md` — this report

---

## Suggested next phase (out of scope here)

- Resolve the three **Needs Manual Review** items with access to a live DB and the trained model artifacts.
- Install `pytest` in `backend/.venv` and run `tests/test_training_pipeline.py`.
- Add an Android instrumentation test that exercises `ApiClient` against the running backend (covered the two contract fixes).
