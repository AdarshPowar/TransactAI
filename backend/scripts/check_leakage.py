"""
check_leakage.py

Checks a train/test split (or a single labeled dataset you split yourself)
for duplicate / near-duplicate SMS messages that could be inflating
accuracy numbers via data leakage.

USAGE
-----
If you already have separate train/test CSVs:

    python check_leakage.py --train data/train.csv --test data/test.csv \
        --text-col message --label-col category

If you have ONE combined CSV and split it inside your training script
(e.g. train_test_split), point both --train and --test at the same file
and pass --split-inside to have this script redo an 80/20 split with the
same random_state you use, OR just run it on the full file with
--dedupe-only to see how much duplication exists overall.

    python check_leakage.py --train data/all_sms.csv --dedupe-only \
        --text-col message --label-col category

WHAT IT DOES
------------
1. Exact-duplicate check: normalizes each message (lowercase, collapse
   whitespace, strip common variable substrings like amounts/dates/refs)
   and looks for exact matches across train vs test.
2. Near-duplicate check: same normalization but also strips ALL digits,
   to catch cases where only the amount/OTP/date differs between two
   otherwise-identical template messages.
3. Per-class breakdown: reports accuracy-relevant stats per category so
   you can see if a class is trivially "solved" via leakage.
4. Prints a clear leakage % and a verdict.

It does not require sklearn or your model — it only inspects the data.
"""

import argparse
import re
import sys
from collections import Counter

try:
    import pandas as pd
except ImportError:
    sys.exit("This script needs pandas. Install with: pip install pandas")


def normalize_exact(text: str) -> str:
    """Lowercase + collapse whitespace. Catches identical messages."""
    text = str(text).lower().strip()
    text = re.sub(r"\s+", " ", text)
    return text


def normalize_template(text: str) -> str:
    """
    Aggressive normalization meant to catch 'same template, different
    amount/date/ref number' messages — the most common source of
    synthetic-data leakage in SMS classifiers.
    """
    text = str(text).lower().strip()
    text = re.sub(r"\s+", " ", text)
    # strip amounts like rs.98, inr 1,200.50, ₹500
    text = re.sub(r"(rs\.?|inr|₹)\s?[\d,]+(\.\d+)?", "<amt>", text)
    # strip all remaining digits (dates, OTPs, ref numbers, phone numbers)
    text = re.sub(r"\d+", "<num>", text)
    return text


def load(path: str, text_col: str, label_col: str) -> pd.DataFrame:
    if path.lower().endswith((".xlsx", ".xls")):
        try:
            df = pd.read_excel(path)
        except ImportError:
            sys.exit(
                "Reading .xlsx requires openpyxl. Install with:\n"
                "    pip install openpyxl"
            )
        missing = [c for c in (text_col, label_col) if c not in df.columns]
        if missing:
            sys.exit(
                f"Column(s) {missing} not found in {path}. "
                f"Available columns: {list(df.columns)}"
            )
        df = df[[text_col, label_col]].dropna()
        df.columns = ["text", "label"]
        return df

    df = None
    last_err = None
    skipped_note = None
    for enc in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        try:
            df = pd.read_csv(path, encoding=enc)
            break
        except UnicodeDecodeError as e:
            last_err = e
            continue
        except pd.errors.ParserError as e:
            last_err = e
            # Rows probably have unescaped commas inside the message text.
            # Retry more leniently, skipping the rows that don't parse.
            try:
                before_count = sum(1 for _ in open(path, encoding=enc, errors="ignore")) - 1
                df = pd.read_csv(
                    path, encoding=enc, engine="python", on_bad_lines="skip"
                )
                skipped = before_count - len(df)
                if skipped > 0:
                    skipped_note = (
                        f"WARNING: {skipped} row(s) in {path} could not be parsed "
                        f"(likely unescaped commas inside the message text) and were "
                        f"skipped. Consider re-exporting this CSV with proper quoting."
                    )
                break
            except Exception as e2:
                last_err = e2
                continue
    if df is None:
        sys.exit(f"Could not read {path} with any common encoding/parser. Last error: {last_err}")
    if skipped_note:
        print(skipped_note)

    missing = [c for c in (text_col, label_col) if c not in df.columns]
    if missing:
        sys.exit(
            f"Column(s) {missing} not found in {path}. "
            f"Available columns: {list(df.columns)}"
        )
    df = df[[text_col, label_col]].dropna()
    df.columns = ["text", "label"]
    return df


def report_overlap(train: pd.DataFrame, test: pd.DataFrame):
    train = train.copy()
    test = test.copy()

    train["exact_key"] = train["text"].apply(normalize_exact)
    test["exact_key"] = test["text"].apply(normalize_exact)
    train["template_key"] = train["text"].apply(normalize_template)
    test["template_key"] = test["text"].apply(normalize_template)

    # --- exact duplicate overlap ---
    train_exact = set(train["exact_key"])
    test_exact_matches = test["exact_key"].isin(train_exact).sum()

    # --- template-level (near-duplicate) overlap ---
    train_template = set(train["template_key"])
    test_template_matches = test["template_key"].isin(train_template).sum()

    n_test = len(test)
    exact_pct = 100 * test_exact_matches / n_test if n_test else 0
    template_pct = 100 * test_template_matches / n_test if n_test else 0

    print("=" * 60)
    print("LEAKAGE REPORT")
    print("=" * 60)
    print(f"Train rows: {len(train)}   Test rows: {len(test)}")
    print()
    print(f"Exact-text overlap (test rows whose exact message text also")
    print(f"appears in train): {test_exact_matches} / {n_test} "
          f"({exact_pct:.2f}%)")
    print()
    print(f"Template-level overlap (test rows that match a train message")
    print(f"once amounts/dates/numbers are masked out): "
          f"{test_template_matches} / {n_test} ({template_pct:.2f}%)")
    print()

    if template_pct > 20:
        print("VERDICT: Significant leakage likely. Your model may be")
        print("memorizing templates rather than learning to generalize.")
        print("Dedupe by template_key BEFORE splitting, then retrain/re-eval.")
    elif template_pct > 5:
        print("VERDICT: Moderate overlap. Worth deduping before trusting")
        print("headline accuracy numbers, especially for smaller classes.")
    else:
        print("VERDICT: Low overlap. High accuracy is more likely genuine,")
        print("but check the per-class breakdown below for weak spots.")

    print()
    print("=" * 60)
    print("PER-CLASS TEST SET SIZE (sanity check for imbalance)")
    print("=" * 60)
    counts = Counter(test["label"])
    for label, n in counts.most_common():
        print(f"{label:25s} {n}")

    # Show a few example leaked pairs for manual inspection
    if test_template_matches > 0:
        print()
        print("=" * 60)
        print("SAMPLE LEAKED TEMPLATE MATCHES (first 5)")
        print("=" * 60)
        leaked = test[test["template_key"].isin(train_template)].head(5)
        for _, row in leaked.iterrows():
            print(f"- [{row['label']}] {row['text'][:100]}")


def dedupe_only(df: pd.DataFrame):
    df = df.copy()
    df["template_key"] = df["text"].apply(normalize_template)
    total = len(df)
    unique_templates = df["template_key"].nunique()
    dup_rows = total - df.drop_duplicates(subset="template_key").shape[0]

    print("=" * 60)
    print("SINGLE-FILE DUPLICATION REPORT")
    print("=" * 60)
    print(f"Total rows: {total}")
    print(f"Unique templates (amount/date/number masked): {unique_templates}")
    print(f"Rows that are duplicates of another row's template: {dup_rows} "
          f"({100*dup_rows/total:.2f}%)")
    print()
    print("If this % is high, any random train_test_split will leak")
    print("near-identical messages across the split. Dedupe by")
    print("template_key before splitting.")


def load_raw(path: str) -> pd.DataFrame:
    """Load the full sheet (all columns) for --split-col mode."""
    if path.lower().endswith((".xlsx", ".xls")):
        return pd.read_excel(path)
    for enc in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        try:
            return pd.read_csv(path, encoding=enc)
        except UnicodeDecodeError:
            continue
        except pd.errors.ParserError:
            return pd.read_csv(path, encoding=enc, engine="python", on_bad_lines="skip")
    sys.exit(f"Could not read {path}")


def split_col_mode(path, text_col, label_col, split_col, train_val, test_val, synthetic_col):
    raw = load_raw(path)
    for c in (text_col, label_col, split_col):
        if c not in raw.columns:
            sys.exit(f"Column '{c}' not found. Available columns: {list(raw.columns)}")

    train = raw[raw[split_col] == train_val][[text_col, label_col]].dropna()
    test = raw[raw[split_col] == test_val][[text_col, label_col]].dropna()
    train.columns = ["text", "label"]
    test.columns = ["text", "label"]

    print(f"Using '{split_col}' column: train={train_val} ({len(train)} rows), "
          f"test={test_val} ({len(test)} rows)\n")
    report_overlap(train, test)

    if synthetic_col and synthetic_col in raw.columns:
        print()
        print("=" * 60)
        print("SYNTHETIC vs REAL OVERLAP CHECK")
        print("=" * 60)
        synth = raw[raw[synthetic_col] == True][[text_col, label_col]].dropna()
        real = raw[raw[synthetic_col] == False][[text_col, label_col]].dropna()
        synth.columns = ["text", "label"]
        real.columns = ["text", "label"]

        synth_templates = set(synth["text"].apply(normalize_template))
        real["template_key"] = real["text"].apply(normalize_template)
        real_matches = real["template_key"].isin(synth_templates).sum()
        pct = 100 * real_matches / len(real) if len(real) else 0
        print(f"Real rows: {len(real)}   Synthetic rows: {len(synth)}")
        print(f"Real messages that template-match a synthetic message: "
              f"{real_matches} / {len(real)} ({pct:.2f}%)")
        print()
        if pct > 5:
            print("This means synthetic training data may be near-duplicating your")
            print("real SMS backup data. Check whether real test messages are also")
            print("template-duplicated in the synthetic *training* rows specifically")
            print("(not just synthetic rows overall) — that's the direct leak path.")

        # Most direct check: do TEST-set real messages match TRAIN-set synthetic messages?
        train_synth = raw[(raw[split_col] == train_val) & (raw[synthetic_col] == True)]
        test_real = raw[(raw[split_col] == test_val) & (raw[synthetic_col] == False)]
        if len(train_synth) and len(test_real):
            train_synth_templates = set(
                train_synth[text_col].apply(normalize_template)
            )
            test_real_keys = test_real[text_col].apply(normalize_template)
            direct_leak = test_real_keys.isin(train_synth_templates).sum()
            dpct = 100 * direct_leak / len(test_real)
            print()
            print(f"DIRECT LEAK CHECK: real TEST messages matching a synthetic")
            print(f"TRAIN message template: {direct_leak} / {len(test_real)} ({dpct:.2f}%)")
            if dpct > 2:
                print("^ This is the most likely direct cause of inflated accuracy if high.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True, help="Path to train CSV/XLSX (or full dataset if --dedupe-only / --split-col)")
    ap.add_argument("--test", help="Path to test CSV/XLSX (required unless --dedupe-only or --split-col)")
    ap.add_argument("--text-col", default="message", help="Name of the SMS text column")
    ap.add_argument("--label-col", default="category", help="Name of the label column")
    ap.add_argument("--dedupe-only", action="store_true",
                     help="Just check duplication within a single file, no train/test split")
    ap.add_argument("--split-col", help="Column name that already marks train/test (e.g. dataset_split)")
    ap.add_argument("--train-val", default="train", help="Value in --split-col meaning 'train' row")
    ap.add_argument("--test-val", default="test", help="Value in --split-col meaning 'test' row")
    ap.add_argument("--synthetic-col", help="Boolean column marking synthetic vs real rows (e.g. synthetic)")
    args = ap.parse_args()

    if args.split_col:
        split_col_mode(
            args.train, args.text_col, args.label_col,
            args.split_col, args.train_val, args.test_val, args.synthetic_col
        )
        return

    if args.dedupe_only:
        df = load(args.train, args.text_col, args.label_col)
        dedupe_only(df)
        return

    if not args.test:
        sys.exit("--test is required unless you pass --dedupe-only or --split-col")

    train = load(args.train, args.text_col, args.label_col)
    test = load(args.test, args.text_col, args.label_col)
    report_overlap(train, test)


if __name__ == "__main__":
    main()