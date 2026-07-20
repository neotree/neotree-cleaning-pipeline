# Module 14a: Resolve Missing neolab datebct from Admissions

## Purpose
For the `neolab` (blood culture) dataset, resolves missing `datebct` (date blood culture taken) values by joining to the corresponding raw admissions file on `uid + facility` and substituting `datetimeadmission` as a proxy date.  Blood cultures are typically taken at or shortly after admission, making `datetimeadmission` a clinically reasonable proxy when `datebct` is absent.

Two new columns are added to the cleaned neolab output:

| Column | Type | Description |
|--------|------|-------------|
| `datebct_resolved` | POSIXct | Best available blood culture date: `datebct` if present, otherwise `datetimeadmission`. NA if neither is available. |
| `datebct_source` | character | Provenance flag: `"original"` (datebct was present and parsed), `"from_admission"` (resolved from admissions), or `NA` (no date available). |

`datebct` itself is **never modified**.

For all non-neolab datasets this module exits immediately after a single `cfg$dataset` check (~1 ms).

---

## When It Runs
After Module 14 (datetime validation) and before Module 15 (final merge and output). It modifies `df_datetime` in-place by appending the two new columns, which Module 15 then picks up naturally in the existing sub-frame merge.

Controlled by the `RESOLVE_NEOLAB_DATEBCT` flag in `00_setup.r` (default `TRUE`).

---

## Logic

1. **Guard checks** — exits early (with a log warning) if:
   - `cfg$dataset != "neolab"`
   - `cfg$resolve_neolab_datebct == FALSE`
   - `datebct.value` is absent from `df_datetime`
   - The admissions lookup file cannot be found or read

2. **Derive admissions file path** — constructed from `cfg$csv_filepath` by substituting the `neolab` segment with `admissions` in the filename.  For example:
   - `input/mwi_db_neolab_20260501.csv` → `input/mwi_db_admissions_20260501.csv`
   - `input/mwi_mb_neolab_2026-05-01.csv` → `input/mwi_mb_admissions_2026-05-01.csv`

3. **Read admissions columns** — reads only three columns from the raw admissions CSV: `uid`, `facility`, and `DateTimeAdmission.value`.  Column detection is case-insensitive; a fallback also matches `datetimeadmission` (without `.value`) for flexibility.

4. **Parse `datetimeadmission`** — uses the same lubridate `parse_orders` as Module 14, including Metabase-specific orders when `cfg$data_source == "metabase"`.

5. **Deduplicate admissions lookup** — collapses to one row per `uid + facility`, keeping the earliest non-NA `datetimeadmission`.  Prevents fan-out in the join if a patient has multiple admission records.

6. **Left-join** — joins the lookup table to `df_datetime` on `uid + facility`.

7. **Populate new columns:**
   - `datebct_resolved` = `datebct.value` if not NA, else `adm_datetime`
   - `datebct_source` = `"original"` / `"from_admission"` / `NA`

8. **Log summary** — reports the three-way count (original / resolved from admission / still NA) to the pipeline log.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df_datetime` | Validated datetime sub-frame from Module 14 |
| `cfg$dataset` | Must be `"neolab"` for the module to do anything |
| `cfg$resolve_neolab_datebct` | Boolean flag (default `TRUE`) |
| `cfg$csv_filepath` | Path to the neolab input CSV (used to derive the admissions path) |
| `cfg$data_source` | `"database"` or `"metabase"` -- controls datetime parse orders |
| `cfg$report_dir` | Directory for the text report (optional) |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_datetime` | Same frame with `datebct_resolved` (POSIXct) and `datebct_source` (character) appended |
| `reports/14a_resolve_neolab_datebct_report.txt` | Three-way count summary (original / resolved / still NA), file paths used (optional) |

---

## Key Function

**`resolve_neolab_datebct(df_datetime, cfg, report_filepath = NULL)`**

- Checks guards; returns `df_datetime` unchanged if not applicable.
- Derives and reads the raw admissions file (uid + facility + DateTimeAdmission.value only).
- Parses datetimeadmission with the same format orders as Module 14.
- Deduplicates admissions lookup to one row per uid + facility.
- Left-joins and populates `datebct_resolved` and `datebct_source`.
- Logs the three-way resolution summary and optionally writes a report.

---

## Notes

- The raw admissions file is used rather than the cleaned admissions output because the cleaned output may not exist at pipeline run time (each dataset is processed independently).
- `datebct_resolved` is POSIXct, so Module 15's `format_datetimes_for_csv()` will format it as `"YYYY-MM-DD HH:MM:SS"` in the CSV output — consistent with all other datetime columns.
- `datebct_source` is a bare character column (no `.value` suffix) and passes through Module 15's sub-frame merge via `df_datetime` directly.
- If the admissions file for the corresponding country / source / date is absent from `input/`, the module logs a warning and sets `datebct_resolved = datebct.value` (i.e. NA for the affected rows) with `datebct_source = NA`.
- The module is safe to leave enabled for all runs (`RESOLVE_NEOLAB_DATEBCT = TRUE`): for ZIM neolab or any future neolab file where `datebct` is fully populated, it takes the zero-missing early-exit path and adds `datebct_resolved = datebct.value` with `datebct_source = "original"` for every row.
