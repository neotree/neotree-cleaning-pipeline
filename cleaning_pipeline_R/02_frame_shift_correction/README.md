# Module 02: Frame Shift Correction

## Purpose

Detects and removes rows where the `uid` field is empty or null -- the minimal necessary guard against irrecoverable data corruption -- and repairs UIDs where a comma was typed in place of a hyphen. Non-standard but non-empty UIDs are retained and logged for downstream handling.

---

## When It Runs

After Module 01 (column header standardisation). Structural integrity must be established before value-level operations begin.

---

## Detection Strategy (revised)

A row is removed only if its `uid` is **empty, NA, or a recognised null-equivalent string** (`""`, `"NA"`, `"NULL"`, `"nan"`, `"none"`, etc.). These records are genuinely irrecoverable -- without any uid value, they cannot be linked to any other record and contribute nothing to downstream analysis.

### Why the original hyphen rule was changed

The original criterion -- drop any row whose `uid` lacks a hyphen -- was too aggressive. Investigation of ZIM discharge data identified **116 legitimate patients** with 8-character alphanumeric UIDs that contain no hyphen (e.g. `"EC330587"`, `"75DA0016"`, `"F6650504"`). These are real Neotree records from specific facilities where the hyphen separator was never stored. Applying the hyphen rule silently dropped these patients from every pipeline run.

The standard Neotree UID format is `XXXX-YYYY` (4-char prefix, hyphen, variable-length number). Some facilities produce UIDs in the concatenated form `XXXXYYYY` -- the same data, hyphen omitted. These are not frame shifts; they are a non-standard but consistent formatting variant.

### What a true frame shift looks like

A genuine frame shift occurs when a CSV export misaligns columns, causing the `uid` field to receive data from a completely different column -- a diagnosis code, a date string, a lab value. The resulting `uid` value is typically blank, or so obviously wrong that no amount of downstream matching could recover the record. The null/empty test catches this reliably without discarding records that simply have an unusual UID format.

### Retained non-standard UIDs

Non-standard UIDs (no hyphen, very short, unusual characters such as `"EC"` or `"X"`) are **kept in the dataset** and logged in the report. The downstream probabilistic admissions-discharges matching step has access to multiple clinical variables (facility, birth weight, gestation, dates, outcomes) and is better placed to determine whether such a record can be linked. Silent deletion at Module 02 is worse than a logged anomaly passed on for further assessment.

---

## UID Repair

UIDs of the form `XXXX,YYYY` -- where a comma appears where a hyphen should be (e.g. `"CDDA,0484"` -> `"CDDA-0484"`) -- are repaired before any other processing. This is a data-entry substitution error. The pattern matched is `[A-Za-z0-9]{3-6},[A-Za-z0-9]+`; the comma is replaced with a hyphen. Repaired UIDs are logged in the report.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 01 with a `uid` column |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with empty/null-uid rows removed; comma UIDs repaired |
| `reports/02_frame_shift_report.txt` | Counts of repaired, removed, and non-standard UIDs; full lists for audit |
| `reports/02_frame_shift_dirty_rows.csv` | Rows with empty/null uid saved for audit (only rows actually removed) |

---

## Report Contents

The plain-text report includes:

- Rows on entry and after correction
- Count of comma UIDs repaired (with the repaired UID values)
- Count of empty/null uid rows removed (with the uid values, typically blank)
- Count of non-standard UIDs **retained** (with UID values, for audit)

---

## Key Function

**`remove_frame_shift(df, report_filepath = NULL, csv_filepath = NULL)`**

Performs three steps in sequence:

1. **Repair** -- replaces commas with hyphens in UIDs matching the `XXXX,YYYY` pattern.
2. **Remove** -- drops rows where `uid` is empty, NA, or a null-equivalent string.
3. **Log** -- identifies rows with non-standard (no-hyphen) UIDs and includes them in the report without removing them.

Returns the cleaned data frame with empty-uid rows removed and comma UIDs repaired.

---

## Notes

- Frame shifts are typically caused by encoding errors or export pipeline bugs in the Neotree database.
- The `dirty_rows.csv` contains only the rows that were **actually removed** (empty/null uid), not the non-standard UIDs that were retained.
- This step must run before any join, deduplication, or value-cleaning logic.
- The probabilistic admissions-discharges matching module is the appropriate place to assess whether records with non-standard UIDs can be linked to other records.
