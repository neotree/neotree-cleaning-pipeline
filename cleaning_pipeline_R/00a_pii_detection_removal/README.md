# Module 00a -- PII Detection, Flagging, and Removal

**Position in pipeline:** Runs second, immediately after `00_setup`, before any
cleaning step.  Previously numbered as `16_pii_detection_removal`, then briefly
`00c_pii_detection_removal`; renumbered `00a` to reflect its true position in
execution order (before `00b_rename_harmonised_columns`).

---

## What this module does

Loads the raw CSV, normalises all column names, then removes and flags any
content that constitutes Personally Identifiable Information (PII) under
data protection best practice and research ethics requirements.

### Three-tier PII strategy

| Tier | Action | Source |
|------|--------|--------|
| 1 -- Dictionary-defined | **Removed** | Columns where `confidential = TRUE` in the v8 dictionary (`cfg$pii_columns`) |
| 2 -- Fallback patterns | **Removed** | Columns matching known PII name patterns (names, phone, address, HCW/hospital IDs) |
| 3 -- Quasi-identifiers | **Flagged only** (not removed) | village, district, province, tribe, ethnicity, religion, address, matagedate |

After column removal, each remaining column is scanned at value level for
phone numbers, email addresses, and NHS/hospital number patterns; matches
are redacted to `NA`.

---

## Data source compatibility

This module normalises column names before any matching, making it work
identically with both supported data source formats:

| Format | System columns | Data columns |
|--------|---------------|--------------|
| `database` (PostgreSQL export) | `unique_key`, `started_at` | `BabyCryTriage.value` |
| `metabase` (Metabase export) | `Unique Key`, `Started At` | `Baby Cry Tria Ge. Value` |

After normalisation both become `uniquekey`, `startedat`, `babycryptriage.value`.
Set `DATA_SOURCE` in `00_setup/00_setup.R` to document which format you are using.

---

## Inputs

| Object | Description |
|--------|-------------|
| `cfg$csv_filepath` | Path to the raw CSV (database or metabase export) |
| `cfg$pii_columns` | PII column names from the v8 dictionary |
| `cfg$data_source` | `"database"` or `"metabase"` (informational) |
| `cfg$report_dir` | Directory for the audit report (NULL = suppress) |

## Outputs

| Object / File | Default | Description |
|---------------|---------|-------------|
| `df_raw_deidentified` | always | De-identified data.frame (passed to Module 01) |
| `output/<file_stem>/<file_stem>_deidentified.csv` | **off** | De-identified raw CSV written to the run's output subfolder. Controlled by `SAVE_DEIDENTIFIED` (default `FALSE`). PII removal always runs in-memory; this flag only controls the disk copy. |
| `output/<file_stem>/reports/00a_pii_audit_report.txt` | always | Audit trail of all removals, flags, and redactions |

---

## Audit report

The report (`reports/00a_pii_audit_report.txt`) documents:
- Timestamp, country, dataset, and source file
- How many columns were removed (dictionary vs pattern)
- Which quasi-identifier columns were flagged
- Which columns had individual values redacted, and how many

**Review this report before sharing any dataset.**
Quasi-identifier columns (district, village, tribe, ethnicity, religion,
`matagedate`) are listed but **not** automatically removed -- they may be
needed for analysis and their risk depends on context.

`matagedate` stores maternal age in hours (auto-calculated by the Neotree app
from the mother's date of birth). It is not itself a date of birth, but its
precision (years + months + days) makes it a stronger quasi-identifier than
the rounded `matageyrs` field. Flag added as a precaution.

---

## Extending PII patterns

To add more patterns, edit the constants at the top of
`00a_pii_detection_removal.R`:

```r
PII_FALLBACK_PATTERNS    <- c(...)   # column-name patterns -> remove
PII_QUASI_COL_PATTERNS   <- c(...)   # column-name patterns -> flag only
PII_VALUE_PATTERNS       <- list(...)# value-level regex    -> redact to NA
```
