# Module 11: Numeric Validation

## Purpose
Validates all numeric columns in the dataset. Removes non-numeric entries, converts weight variables to grams, rescues `matageyrs` values stored in hours back to years, derives `mat_age_date_years` from the hours-based `matagedate` field (with a 9–60 plausibility filter), enforces definitional bounds for fixed-scale scoring instruments, and deduplicates. Produces the `df_numeric` sub-frame that feeds into the final merge (Module 15).

### Definitional bounds vs. researcher-defined plausibility ranges

Two categories of range can be enforced by this module, both stored in `suggested_plausible_min` / `suggested_plausible_max` in the dictionary Variables sheet and consumed via `cfg$range_lookup`:

**Definitional bounds** (`MANUAL_RANGES` in the build script) -- limits intrinsic to the definition of the instrument itself:

- `apgar1/5/10`: the Apgar score is defined on a fixed 0-10 scale. A value of 11 is not "unlikely" -- it is structurally impossible by the definition of the score.
- `thompscore`: the Thompson HIE score is defined on a fixed 0-22 scale. Same reasoning applies.
- `satsair` / `satso2`: expressed as a percentage, which is defined on a 0-100 scale. A value of 101 cannot be a valid percentage.

**Researcher-defined plausibility ranges** (`user_ranges.xlsx`) -- limits set by the research team for continuous physiological variables where a value is judged implausible for this study population (e.g. birthweight < 200 g, temperature > 42 °C). These are defined in `00_build_dictionary/user_ranges.xlsx`, baked into the dictionary by the build script, and enforced here exactly like definitional bounds: out-of-range values are set to `NA` and coded `-8` by Module 16.

By default, `user_ranges.xlsx` contains only example rows and no active entries. Continuous physiological variables with no entry in that file (weight, gestation, temperature, heart rate, etc.) are **not** range-validated by this module. Values outside the range are set to `NA` (not clamped or imputed) and logged in the report.

---

## When It Runs
After Module 10 (duplicate row removal). First of four parallel validation streams (Modules 11-14), all reading from the same stage-1 data frame.

---

## Logic

For each numeric column in `cfg$num` that is present in the data frame:

1. **Non-numeric removal** -- the column is coerced to numeric via `as.numeric()`. Any value that fails coercion (e.g. a stray label string) is set to `NA`.

2. **Unit standardisation (kilograms -> grams)** -- if the column's base name is in `cfg$weight_cols`, any value less than or equal to 20 is assumed to be in kilograms and is multiplied by 1000. (Values > 20 are assumed to already be in grams.)

2b. **Unit rescue (matageyrs: hours -> years)** -- the Neotree app populates `matageyrs` in two ways depending on how data is entered: manual entry produces a value in years, while auto-calculation from the mother's date of birth produces a value in hours. Both land in the same column, creating a mixed-unit problem in the source data. Any `matageyrs` value greater than 200 is unambiguously in hours (the oldest confirmed mother is well under 200 years; 200 hours is only ~8 days old), so those values are divided by **8766** (= 365.25 × 24) and rounded to one decimal place. The count of rescued values is logged and appears in the module report.

3b. **Maternal age from `matagedate` (hours -> years, KCH/MWI only)** -- `matagedate` is a *separate* field ("Mother's Age, auto-calculated from DOB", raw type `period`) that is **always** stored in hours, and exists only on the MWI/KCH deliveries form. A parallel column **`mat_age_date_years = round(matagedate / 8766)`** is created (raw `matagedate` is left untouched, still in hours). The derived value is plausibility-filtered on the **same 9–60 window** as `matageyrs`: out-of-range values are set to `NA` and counted here, so all implausible maternal ages are handled in this one module and are `-8`-coded by Module 16. The combined maternal-age variable itself is assembled downstream in Module 15 (`derive_maternal_age_columns()`).

3. **Range validation** -- if the variable has an entry in `cfg$range_lookup` (a tibble of `question_key`, `min`, `max` from the dictionary), values outside `[min, max]` are set to `NA`. Only variables with **definitional bounds** carry a range entry: `apgar1/5/10` (0-10), `satsair`/`satso2` (0-100), and `thompscore` (0-22). These are fixed-scale instruments where values outside the range are structurally impossible, not merely implausible. Continuous physiological variables (weight, gestation, temperature, heart rate, respiratory rate, blood glucose, etc.) have no range set in the dictionary -- extreme values are retained and passed to the sample maker for clinical plausibility filtering.

4. **Deduplication** -- `dplyr::distinct()` on (`uid`, `facility`) is applied to the numeric sub-frame before it is returned.

The sub-frame includes the three primary key columns (`facility`, `uid`, `uniquekey`) plus all numeric feature columns.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Stage-1 data frame from Module 10 |
| `cfg$num` | Character vector of numeric column names |
| `cfg$weight_cols` | Vector of column base names recorded in grams |
| `cfg$range_lookup` | Tibble: `question_key`, `min`, `max` -- definitional bounds from the dictionary (fixed-scale instruments only) |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_numeric` | Validated numeric sub-frame: primary keys + numeric columns, plus derived `mat_age_date_years` where `matagedate` is present |
| `reports/11_numeric_validation_report.txt` | Count of non-numeric removals, unit conversions, `matageyrs` rescues, `matagedate`→years derivations + implausibles, range violations (optional) |

---

## Key Function

**`validate_numeric(df, cfg, report_filepath = NULL)`**

- Selects primary key columns + all numeric feature columns present in `df`.
- Applies coercion, unit conversion, and range validation per column.
- Deduplicates and returns the validated sub-frame as `df_numeric`.

---

## Notes

- The `base_name()` helper strips `.value` / `.valuedischarge` before range lookup, so both column forms are handled transparently.
- Weight conversion threshold of 20: values like `"3500"` (grams) pass through unchanged, while values like `"3.5"` (kg) are multiplied by 1000 to give `3500` grams.
- Out-of-range values are set to `NA` (not clamped or imputed) and logged in the report.
- Continuous physiological measures (gestation, birthweight, temperature, heart rate, respiratory rate, blood glucose, maternal age, head circumference) have no range set by default. To enforce plausibility limits on these variables, add entries to `00_build_dictionary/user_ranges.xlsx` and re-run the build script. The pipeline will then set out-of-range values to `NA` here and code them `-8` in Module 16, exactly as for definitional bounds.
- `matageyrs` is a known mixed-unit column in the source data: the Neotree app stores hours when age is auto-calculated from DOB, and years when entered manually. The rescue threshold of 200 is intentionally conservative -- it leaves no ambiguity between the two populations and matches no plausible real age in years.
- `matagedate` (distinct from `matageyrs`) is *always* in hours, so `mat_age_date_years` divides unconditionally by 8766 — no threshold is needed. Both maternal-age divisors were standardised to 8766 (= 365.25 × 24) so the two fields agree; the value was previously 8760 for the `matageyrs` rescue. `mat_age_date_years` is a derived numeric column (not a dictionary variable) and is coalesced with `matageyrs` into `mat_age_years_combined` in Module 15.
