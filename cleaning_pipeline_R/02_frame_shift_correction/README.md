# Module 02: Frame Shift Correction

## Purpose

Detects and removes rows where the `uid` field is empty or null -- the minimal necessary guard against irrecoverable data corruption -- and repairs UIDs where a substitute character (comma or slash) was typed in place of a hyphen. Non-standard but non-empty UIDs are retained and logged for downstream handling, split into two separately tracked groups.

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

They are reported in **two separate groups**, because they are not the same kind of anomaly and merging them into a single count hides the distinction:

| Group | Definition | Interpretation |
|-------|------------|----------------|
| **Standard-length, hyphen absent** | 8-character alphanumeric, no hyphen (`^[A-Za-z0-9]{8}$`), e.g. `"EC330587"`, `"75DA0016"` | A formatting variant of a well-formed uid -- the same data with the separator never stored. Expected to link normally downstream. |
| **Other non-standard** | Everything else without a hyphen, e.g. `"EC"`, `"X"`, `"BS1262"` | Truncated or incomplete submissions with no recoverable uid structure. Unlikely to link; retained for audit rather than analysis. |

On the 4 August 2026 ZIM discharges extract the split is **238 rows (112 unique UIDs)** standard-length against **11 rows (3 unique UIDs)** other. Two things move these numbers away from a raw count of the file:

- A uid repaired by the step below carries a hyphen by the time this check runs, so it appears in **neither** group. The three `"CDDA,0484"` rows are hyphen-less in the raw file but repaired before the split is computed.
- Three further rows (`26530019`, `26530047`, `26530054`, all SMCH) are hyphen-less 8-character UIDs in the raw file but never reach this check: Module 00a redacts them as PII first, and Module 02 then removes them as empty-uid rows. See the note in *Notes* below.

---

## UID Repair

UIDs of the form `XXXX<sep>YYYY` -- where a substitute character appears where a hyphen should be (e.g. `"CDDA,0484"` -> `"CDDA-0484"`, `"F55F/0700"` -> `"F55F-0700"`) -- are repaired before any other processing. This is a data-entry substitution error. The pattern matched is `[A-Za-z0-9]{3,6}<sep>[A-Za-z0-9]+`; the separator is replaced with a hyphen. Repaired UIDs are logged in the report.

### Configurable separator set

The substitute characters are configuration, not code: `UID_REPAIR_SEPARATORS` in `00_setup.r`, surfaced as `cfg$uid_repair_separators`. It currently holds **comma and slash**. Recognising a further character later is a one-line change there -- the module builds its match pattern from the vector and needs no edit.

Space and backslash are **deliberately excluded**. Both were checked across the ZIM and MWI admission and discharge files (4 August 2026 extract) and occur zero times in any uid. Repairing a character no one has ever typed invents corrections rather than fixing them; add a separator only when the raw data shows it.

### Confirmed vs unconfirmed repairs

Every repair is reported with a status saying how much evidence stands behind it:

| Status | Meaning |
|--------|---------|
| `confirmed` | The corrected (hyphenated) uid also exists in the paired admissions/discharges file for the same country, at the same facility -- the repair is backed by a real matching record. |
| `confirmed (other facility)` | The corrected uid exists in the paired file but at a different facility. Weaker evidence; shown distinctly rather than merged into either bucket. |
| `unconfirmed` | No such record exists in the paired file. The repair is inferred from the facility's uid naming pattern alone. |
| `unchecked` | The paired file was not available, so no cross-check was possible. Never read this as a negative result. |

The paired file is resolved once in `00_setup.r` (`cfg$paired_csv_filepath`) using the same approach Module 14a takes for its neolab-to-admissions lookup: the raw CSV for the opposite dataset in the same `input/` folder, preferring the same extract stamp and falling back to the most recent extract of that dataset for the same country and source. Only its `uid` and `facility` columns are read, and only when a repair actually needs confirming -- runs with no repairs pay nothing.

**An unconfirmed repair is still applied.** The distinction is reported, not acted on: the repair rests on the facility's uid pattern either way, and the report is what tells a reader how much weight it carries. On the 4 August 2026 extract, ZIM's three `"CDDA,0484"` rows are unconfirmed (no `CDDA-0484` exists anywhere in ZIM admissions or discharges) while MWI's single `"F55F/0700"` row is confirmed against `F55F-0700` in MWI admissions.

### Repairs that reveal a duplicate submission

If a repaired uid matches another row **in the same file**, the report flags it as `[also present in this file -- likely duplicate submission]`. That is the signature of a retry rather than a plain typo: the MWI `F55F/0700` row shares its facility and `unique_key` event timestamp with the existing `F55F-0700` row and was ingested 250 ms later.

Module 02 does not collapse the pair -- deduplication is Module 10's job, and it does catch this pattern (Stage 1 keys on `uid` + `facility` + the visit-date columns, all of which agree once the uid is repaired). Note the consequence: before the repair the two rows looked like two different patients and both survived; after it they are one patient and Module 10 keeps a single record.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 01 with a `uid` column |
| `cfg$uid_repair_separators` | Characters treated as a mistyped hyphen (from `00_setup.r`) |
| `cfg$paired_csv_filepath` | Paired admissions/discharges raw CSV used to confirm repairs; `NULL` if unavailable |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with empty/null-uid rows removed; separator UIDs repaired |
| `reports/02_frame_shift_report.txt` | Counts of repaired, removed, and non-standard UIDs; full lists for audit |
| `reports/02_frame_shift_dirty_rows.csv` | Rows with empty/null uid saved for audit (only rows actually removed) |

---

## Report Contents

The plain-text report includes:

- The separator set in force for this run, and the paired file used for confirmation
- Rows on entry and after correction
- Count of separator UIDs repaired, broken down into confirmed / unconfirmed / unchecked, followed by a table giving each repair's original and corrected uid, facility, separator, row count and status
- Count of empty/null uid rows removed (with the uid values, typically blank). **This line is written on every run, including when the count is zero** -- a silent report and a clean file must never look the same
- Count of non-standard UIDs **retained**, split into standard-length and other, each with its own UID list

---

## Key Function

**`remove_frame_shift(df, separators = NULL, paired_csv_filepath = NULL, report_filepath = NULL, csv_filepath = NULL)`**

Performs four steps in sequence:

1. **Repair** -- replaces the separator with a hyphen in UIDs matching the `XXXX<sep>YYYY` pattern, for each character in `separators` (defaults to `cfg$uid_repair_separators`).
2. **Remove** -- drops rows where `uid` is empty, NA, or a null-equivalent string.
3. **Confirm** -- looks each repaired uid up in `paired_csv_filepath` and tags it confirmed, unconfirmed or unchecked. The paired file is read only if there is a repair to confirm.
4. **Log** -- identifies rows with non-standard (no-hyphen) UIDs, splits them into standard-length and other, and includes both in the report without removing anything.

Returns the cleaned data frame with empty-uid rows removed and separator UIDs repaired.

---

## Notes

- Frame shifts are typically caused by encoding errors or export pipeline bugs in the Neotree database.
- The `dirty_rows.csv` contains only the rows that were **actually removed** (empty/null uid), not the non-standard UIDs that were retained.
- This step must run before any join, deduplication, or value-cleaning logic.
- The probabilistic admissions-discharges matching module is the appropriate place to assess whether records with non-standard UIDs can be linked to other records.
- Confirmation reads the **raw** paired CSV, not a cleaned one, so it does not depend on the paired file having been through the pipeline. It reads two columns only.
- **An all-numeric uid is blanked before this module sees it.** Module 00a's value-level PII scan applies `phone_international` (`^\+?[0-9]{7,15}$`) to every column including `uid`, so a legitimate all-digit uid is redacted to NA and Module 02 then removes the row as empty-uid. On the 4 August 2026 extract this costs ZIM discharges three patient records (`26530019`, `26530047`, `26530054`, SMCH); the other three admission/discharge files have no all-numeric UIDs and are unaffected. The empty/null count in this module's report is therefore not always a count of genuine frame shifts. Fixing this belongs in Module 00a (exclude `uid` from value-level phone matching), not here.
- `cfg$paired_csv_filepath` is `NULL` for datasets with no admissions/discharges counterpart (maternal outcomes, neolab, baseline, and so on). Those runs report `unchecked` if they ever contain a repair; today none do.
