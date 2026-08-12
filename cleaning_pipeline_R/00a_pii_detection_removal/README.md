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

### Key and system columns are exempt from redaction

`uid`, `facility`, `uniquekey`, the system timestamps (`startedat`,
`completedat`, `ingestedat` and their discharge variants) and the script
metadata (`scriptversion`, `scriptid`) are listed in `PII_VALUE_SCAN_EXEMPT`.
They are still **scanned**, but a match is never redacted -- it is reported
instead.

These columns are structural identifiers the pipeline keys on, not free text in
which a phone number or email could hide. Redacting one does not protect anyone;
it destroys the record. A `uid` set to `NA` is removed by Module 02 as an empty
uid, so the patient disappears from the cleaned output altogether.

This was a live defect, not a hypothetical one. The generic
`phone_international` pattern (`^\+?[0-9]{7,15}$`) matches **any** 7-15 digit
string, and three legitimate ZIM discharge UIDs are 8 all-numeric characters
(`26530019`, `26530047`, `26530054`, all SMCH). Every run redacted them and then
dropped those three patients, recording it only as `uid : 3 value(s)` in the
audit report -- indistinguishable from a genuine redaction. All 15 raw files in
the 4 August 2026 extract were checked: this is the only key/system column hit,
in that one dataset.

Matches on exempt columns are reported under *Key/system columns exempt from
redaction* in the audit report, as **counts only, never the values**. If a match
were ever genuine PII -- a frame shift putting a phone number into `uid`, say --
printing it into the report would leak exactly what this module exists to remove.
The report tells you which column and which pattern; inspect the source file to
judge it.

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
- Which key/system columns were exempt from redaction, and any pattern matches found in them (counts only)

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
PII_VALUE_SCAN_EXEMPT    <- c(...)   # key/system columns   -> scan, report, never redact
```

Before adding a value-level pattern, consider how broad it is. `PII_VALUE_PATTERNS`
entries are applied to every non-exempt column, so a loose pattern silently
deletes legitimate clinical values wherever they happen to match its shape. Prefer
a specific pattern (`^0[67][0-9]{8}$`) over a generic one (`^[0-9]{7,15}$`).

Add a column to `PII_VALUE_SCAN_EXEMPT` only if it is structural -- something the
pipeline joins, groups or dedupes on. It is not a way to keep a column that
genuinely holds PII: for those, use `PII_FALLBACK_PATTERNS` or the dictionary's
`confidential` flag, which remove the whole column.
