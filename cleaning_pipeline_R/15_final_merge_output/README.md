# Module 15: Final Merge & Output

## Purpose
Merges five validated sub-frames on primary keys and saves the final clean dataset to CSV and RDS. Mirrors the reference Jupyter pipeline's merge step, including a passthrough sub-frame for columns that were not assigned to any feature type list.

---

## When It Runs
After Modules 11-14. Final assembly of the stage-2 cleaned dataset.

---

## Logic

### 1. Non-validated passthrough sub-frame
Before merging, two categories of columns that were **not** classified into any typed feature list (`cfg$num`, `cfg$bool`, `cfg$cat`, `cfg$obj`, `cfg$dt`) are collected into a `df_non_validated` sub-frame (retained as character):

- **`.value` / `.valuedischarge` columns** -- untyped clinical fields. Mirrors the Jupyter pipeline's `df_non_validated` sub-frame behaviour.
- **Bare (no-dot) columns** -- system/metadata/computed fields that have no `.value` suffix: `scriptid`, `scriptversion`, `transformed`, `timespent`, `agecategory`, and any others present after Module 07. These would otherwise be silently dropped because no typed sub-frame captures them. Retaining them aligns with the pipeline objective of preserving all non-PII information from the raw file.

Columns whose base name appears in any typed list (e.g. a bare `birthweight` column whose `.value` counterpart is in `cfg$num`) are excluded to avoid duplication.

### 2. Smart deduplication (pre-merge)
Each sub-frame is independently deduplicated using the dedup key determined by `cfg$skip_dedup_stage2`:

- **Standard datasets** (`cfg$skip_dedup_stage2 = FALSE`, default): dedup key is `(uid, facility)` — one record per patient per facility is kept, retaining the most complete row.
- **Longitudinal datasets** (`cfg$skip_dedup_stage2 = TRUE`, auto-set for `infections` and `neolab`): dedup key is `(uid, facility, uniquekey)` — all distinct visit records are preserved; only true within-record duplicates (same uid, facility, and uniquekey) are collapsed.

### 3. Merge
The five sub-frames are joined sequentially using `dplyr::left_join()` on primary keys `(facility, uid, uniquekey)`, in this order: numeric -> boolean -> categorical -> datetime -> non-validated. Only columns not already present in the accumulating result are added at each step.

### 4. Final deduplication
A final smart deduplication is applied to the merged result, using the same key as step 2 above.

### 5. Suffix stripping
`.value` and `.valuedischarge` suffixes are stripped from all column names so the output uses plain variable names (e.g. `age`, `birthweight`, `datetimeadmission`). This mirrors the Jupyter pipeline's `remove_suffixes()` step and is applied **after** all validation is complete, so intermediate modules can still match columns against `cfg$num` / `cfg$bool` / etc.

### 6. Datetime format for CSV
All `POSIXct` columns are formatted as `"YYYY-MM-DD HH:MM:SS"` before CSV export. This matches the Jupyter/pandas output format. The RDS file retains native POSIXct values.

### 7. Trailing `.000` millisecond strip
After POSIXct formatting, a second pass strips any trailing `.000` suffix from every character column via `gsub("\\.000$", "", x)`. This ensures consistent output regardless of whether the column was a POSIXct that was just formatted, or an already-character datetime value (passthrough or object-type column) that carried a raw `.000` millisecond suffix from the source CSV.

### 8. Derived concept-grouped columns (after suffix stripping, before output)
Two derivation steps run once column names are bare, and leave all source columns untouched:

- **Weight (`derive_weight_columns()`)** — adds `birthweight_g = coalesce(birthweight, bwt, bwtdis)` (always emitted), plus `admission_weight_g` and `discharge_weight_g` where their source concept is present. Includes a >1 g disagreement guard and an idempotent kg→g guard.
- **Maternal age (`derive_maternal_age_columns()`)** — adds **`mat_age_years_combined = coalesce(matageyrs, mat_age_date_years)`** and provenance **`mat_age_source ∈ {"matageyrs", "matagedate_derived", "none"}`**. `matageyrs` (manual whole years) takes priority; `mat_age_date_years` (from Module 11's hours→years conversion of `matagedate`) fills the gaps. Both inputs are already in years and already 9–60 range-clean by this point, so the coalesce is lossless. Emitted only when a source column is present, so ZIM (matageyrs only) and MWI (both) share one combined schema and non-maternal datasets are not padded. **Disagreement guard:** rows where both sources are present and differ by **>1 year** are counted and logged (never overwritten — `matageyrs` is kept); the count and rate are written to `15b_maternal_age_summary.txt`.

Derived columns are written to CSV/RDS and NA-reason-coded by Module 16. For the combined maternal-age column, cell-level NA reasons are most accurate on the *source* columns (`matageyrs`, `mat_age_date_years`); use `mat_age_source == "none"` plus the Module 11 and 15b reports as the authoritative accounting for the combined variable.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df_numeric` | Validated numeric sub-frame (Module 11) |
| `df_boolean` | Validated boolean sub-frame (Module 12) |
| `df_categorical` | Validated categorical/object sub-frame (Module 13) |
| `df_datetime` | Validated datetime sub-frame (Module 14) |
| `df` | Full stage-1 data frame (Module 10) -- used to build `df_non_validated` |
| `cfg` | Configuration list (output paths, feature lists) |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_clean` | Final merged, deduplicated data frame in memory |
| `cfg$output_csv` | CSV file -- column names are bare variable names, datetimes as `"YYYY-MM-DD HH:MM:SS"` |
| `cfg$output_rds` | R binary checkpoint (POSIXct values preserved natively) |
| `reports/15_final_merge_summary.txt` | Row/column counts, non-validated column count, run timestamp |
| `reports/15b_maternal_age_summary.txt` | Maternal-age harmonisation: `mat_age_source` breakdown, combined coverage, count/rate of >1yr disagreements (maternal datasets only) |

---

## Key Functions

**`dedup_keep_most_complete(df, key_cols)`** -- retains the most complete record per key group.

**`build_non_validated(df_full, cfg)`** -- identifies (a) `.value` / `.valuedischarge` columns and (b) bare (no-dot) columns not in any feature list, and returns them together as a character sub-frame.

**`format_datetimes_for_csv(df)`** -- converts `POSIXct` columns to `"YYYY-MM-DD HH:MM:SS"` character strings before CSV write.

**`derive_weight_columns(df, cfg)`** -- adds concept-grouped weight columns (`birthweight_g`, `admission_weight_g`, `discharge_weight_g`) with disagreement and kg→g guards.

**`derive_maternal_age_columns(df, cfg)`** -- adds `mat_age_years_combined` and `mat_age_source` by coalescing `matageyrs` with the Module 11-derived `mat_age_date_years`; counts (never overwrites) >1yr disagreements and writes `15b_maternal_age_summary.txt`.

**`merge_and_output(...)`** -- orchestrates all steps above, saves CSV and RDS.

---

## Notes

- The `df_non_validated` passthrough extends the Jupyter pipeline's equivalent sub-frame: it captures both untyped `.value` columns and bare (no-dot) non-typed columns (`scriptid`, `scriptversion`, `transformed`, `timespent`, `agecategory`, etc.), so the output is as complete as the raw input allows without re-introducing PII-removed columns.
- Suffix stripping is applied **after** merge, not before, so all intermediate matching against `cfg$num` / `cfg$bool` / etc. uses the original `.value` names throughout.
- The datetime format change (`"YYYY-MM-DD HH:MM:SS"` vs. `readr`'s default ISO 8601 `"YYYY-MM-DDTHH:MM:SSZ"`) is applied only to the CSV; the RDS retains full POSIXct precision.
- Marks the end of stage-2 validation and completion of the main pipeline.
