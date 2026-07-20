# Module 14: Datetime Validation

## Purpose
Validates all datetime columns by parsing them to POSIXct using a broad set of format patterns. Any string that cannot be parsed as a valid datetime is set to NA. Produces the `df_datetime` sub-frame. For Metabase exports, additional parse orders covering the human-readable format (e.g. `"March 2, 2026, 12:33 AM"`) are applied automatically.

---

## When It Runs
After Module 10 (duplicate row removal). Fourth and final parallel validation stream (Modules 11-14). Module 14a (`14a_resolve_neolab_datebct`) runs immediately after this module and before Module 15, adding resolved date columns to `df_datetime` for the `neolab` dataset.

---

## Logic

For each datetime column in `cfg$dt` present in the data frame:

1. The column is read as character, and trailing `"Z"` timezone indicators are stripped (e.g. `"2023-10-19T22:00:00Z"` -> `"2023-10-19T22:00:00"`).
2. `lubridate::parse_date_time()` is applied with the following format orders (tried left to right):

| Pattern | Example | Source |
|---------|---------|--------|
| `ymd HMS` | `"2023-10-19 22:00:00"` | Database / all |
| `ymd HM` | `"2023-10-19 22:00"` | Database / all |
| `ymd H` | `"2023-10-19 22"` | Database / all |
| `ymd` | `"2023-10-19"` | Database / all |
| `dmy HMS` | `"19/10/2023 22:00:00"` | Database / all |
| `dmy HM` | `"19/10/2023 22:00"` | Database / all |
| `dmy` | `"19/10/2023"` | Database / all |
| `mdy HMS` | `"10/19/2023 22:00:00"` | Database / all |
| `mdy HM` / `mdy` | `"10/19/2023"` | Database / all |
| `Ymd HMS` / `dmY HMS` | ISO variants | Database / all |
| `BdY` | `"October 19, 2023"` | All |
| `dBY` | `"19 October 2023"` | All |
| `BdY IMp` *(Metabase only)* | `"March 2, 2026, 12:33 AM"` | Metabase |
| `BdY HMp` *(Metabase only)* | 24-h fallback | Metabase |
| `dBY IMp` *(Metabase only)* | `"2 March 2026, 12:33 AM"` | Metabase |
| `dBY HMp` *(Metabase only)* | 24-h fallback | Metabase |

The Metabase-specific orders are appended **only when `cfg$data_source == "metabase"`**, so ISO patterns remain preferred for direct database exports.

3. Any value that fails all patterns becomes `NA`. No forced or approximate conversions are made.
4. `dplyr::distinct()` on (`uid`, `facility`) deduplicates the datetime sub-frame.

The sub-frame includes the three primary key columns (`facility`, `uid`, `uniquekey`) plus all datetime feature columns (including dataset-specific timestamp columns from `cfg$dt` such as `startedat`, `completedat`, `ingestedat`).

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Stage-1 data frame from Module 10 |
| `cfg$dt` | Character vector of datetime column names (includes timestamp columns) |
| `cfg$data_source` | `"database"` or `"metabase"` -- controls Metabase parse orders |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_datetime` | Validated datetime sub-frame: primary keys + datetime columns, all values as POSIXct or NA |
| `reports/14_datetime_validation_report.txt` | Counts of successful parses and failed values, data source note (optional) |

---

## Key Function

**`validate_datetime(df, cfg, report_filepath = NULL)`**

- Selects primary key columns + all datetime feature columns present in `df`.
- Builds parse order list; appends Metabase-specific orders when `cfg$data_source == "metabase"`.
- Strips trailing `"Z"`, attempts multi-format parsing, sets failures to `NA`.
- Deduplicates and returns the validated sub-frame as `df_datetime`.

---

## Notes

- The broad format list handles both ISO 8601 timestamps (from direct PostgreSQL exports) and human-readable formats (from Metabase exports). Metabase exports datetime fields as `"March 2, 2026, 12:33 AM"` rather than `"2026-03-02 00:33:00"` -- without the Metabase-specific orders these values would all become `NA`.
- This mirrors the reference Jupyter pipeline, which uses `pd.to_datetime(errors='coerce')` -- a format-agnostic parser that handles both formats transparently.
- Examples of invalid values that become `NA`: stray strings like `"not a date"`, corrupted fragments like `"202"`, or out-of-range dates.
- The `cfg$dt` list includes both the clinical datetime variables from the dictionary and the dataset-specific system timestamp columns (`startedat`, `completedat`, `ingestedat`, etc.) defined in `TIMESTAMP_COLS` in Module 00.

---

## Known difference vs the Python Jupyter pipeline: `datetimeadmission` in MWI discharges

When comparing R-cleaned and Python-cleaned MWI discharge files, the `datetimeadmission` column will be almost entirely empty in the Python output despite being ~48% filled in the raw data and correctly preserved by this pipeline.

**Root cause -- Python pipeline data loss:**
The raw MWI discharge file has `DateTimeAdmission.value` populated in approximately 48% of rows. The R pipeline reads this correctly and outputs it as `datetimeadmission` at the same fill rate. The Python Jupyter notebook (`03_data_cleaning_&_validation_all_tables.ipynb`) loses this column internally: investigation shows that `datetimeadmission.value` is absent from the dataframe by the time the deduplication step runs (logged as "NOT found"), and the final `datetimeadmission` output column carries fewer than 0.1% of values.

The likely mechanism is Python's `drop_unwanted_columns()` function, which -- when a column appears in both bare (`datetimeadmission`) and `.value` (`datetimeadmission.value`) forms -- keeps the one with more non-null values. If a bare `datetimeadmission` column with low fill rate enters the frame before this step (e.g. from a join or an earlier processing stage), it can displace the `.value` column. The alternative candidate is a datetime parsing failure in `convert_columns_and_create_report()` for that specific column.

**Practical implication:**
If you are using Python-cleaned MWI discharge files, `datetimeadmission` will be unreliable (essentially empty). Use the R-cleaned files when `datetimeadmission` is required for analysis (e.g. for computing length of stay). ZIM discharges are unaffected -- both pipelines agree at ~55% fill for `datetimeadmission` in ZIM.

**This is a Python notebook defect, not an R pipeline defect.** No change is needed to the R pipeline. The Python notebook has not been modified.
