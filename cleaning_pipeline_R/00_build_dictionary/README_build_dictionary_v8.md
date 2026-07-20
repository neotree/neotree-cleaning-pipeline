# 00_build_dictionary_v8.r -- Dictionary Build Script

## Purpose

Builds all `dictionary_{country}_{dataset}.xlsx` workbooks from the
official Neotree web-editor data-key exports.  These workbooks are the
**authoritative source of truth** for the entire cleaning pipeline --
every downstream module reads from them.

Run this script first, before `00c` and `00d`.  Re-run whenever the
web-editor data-key exports are updated.

---

## How to run

```r
# From the pipeline root directory:
source("00_build_dictionary/00_build_dictionary_v8.r")
# or from the command line:
Rscript 00_build_dictionary/00_build_dictionary_v8.r
```

---

## Inputs

Located in `neotree_data_keys/downloaded/{country_folder}/`:

| File | Description |
|------|-------------|
| `data-keys-metadata.json` | All field definitions: key, label, dataType, options, confidential flag |
| `data-keys-usage.xlsx` | Which scripts use each key, and the script titles |

Column names in `data-keys-usage.xlsx` are normalised by stripping all
non-alphanumeric characters and lowercasing (e.g. `DataKeyUniqueKey` ->
`datakeyuniquekey`).

---

## Outputs

One Excel workbook per country x dataset combination, written to `dictionaries/`:

| Country x Dataset | Output file |
|-------------------|-------------|
| ZIM x admissions | `dictionary_zim_admissions.xlsx` |
| ZIM x discharges | `dictionary_zim_discharges.xlsx` |
| ZIM x maternal_outcomes | `dictionary_zim_maternal_outcomes.xlsx` |
| ZIM x phc_admissions | `dictionary_zim_phc_admissions.xlsx` |
| ZIM x phc_discharges | `dictionary_zim_phc_discharges.xlsx` |
| ZIM x neolab | `dictionary_zim_neolab.xlsx` |
| ZIM x infections | `dictionary_zim_infections.xlsx` *(blood culture / NeoInfect data)* |
| ZIM x baseline | `dictionary_zim_baseline.xlsx` |
| ZIM x twenty_8_day_follow_up | `dictionary_zim_twenty_8_day_follow_up.xlsx` |
| MWI x admissions | `dictionary_mwi_admissions.xlsx` |
| MWI x discharges | `dictionary_mwi_discharges.xlsx` |
| MWI x maternal_outcomes | `dictionary_mwi_maternal_outcomes.xlsx` |
| MWI x phc_admissions | `dictionary_mwi_phc_admissions.xlsx` *(if scripts present)* |
| MWI x phc_discharges | `dictionary_mwi_phc_discharges.xlsx` *(if scripts present)* |
| MWI x combined_maternity_outcomes | `dictionary_mwi_combined_maternity_outcomes.xlsx` |
| MWI x dhis2_maternal_outcomes | `dictionary_mwi_dhis2_maternal_outcomes.xlsx` |
| MWI x maternity_completeness | `dictionary_mwi_maternity_completeness.xlsx` *(built using maternal outcomes scripts as best approximation; no dedicated Neotree script exists)* |
| MWI x neolab | `dictionary_mwi_neolab.xlsx` |

Neolab script matching: the `neolab` filter matches scripts titled exactly
`NeoLab - Zim` (Zimbabwe) and `NeoLab - Malawi` (Malawi).  Scripts named
`NeoLab - Test 1`, `xNeolab`, and other variants are deliberately excluded.

---

## What it does

1. Loads the web-editor data-key exports for Zimbabwe and Malawi.
2. Filters to the relevant scripts for each country x dataset.
3. Constructs a structured Excel workbook per combination with four sheets:
   **Variables**, **ValueMaps**, **PII_Patterns**, **ReviewNeeded**.
4. Applies manual plausible ranges, PII tier classification, and
   harmonised variable names.
5. Writes one workbook per combination to `dictionaries/`.

---

## Key configuration constants (CONSTANTS section at the top of the script)

| Constant | Purpose | When to edit |
|----------|---------|--------------|
| `DOWNLOADED_KEYS_BASE` | Path to downloaded data-key exports | If the folder layout changes |
| `COUNTRY_FOLDERS` | Subfolder name per country | If new countries are added |
| `OUTPUT_DIR` | Where to write dictionaries (default: `dictionaries/`) | Rarely |
| `PIPELINE_TYPE_MAP` | Maps web-editor `dataType` -> R pipeline `r_type` | If Neotree adds a new field type |
| `CATEGORICAL_TYPES` | Which dataTypes need a ValueMap | If Neotree adds new categorical variants |
| `DATASET_FILTERS` | Regex patterns matching script titles per dataset | If script naming conventions change |
| `RECORD_ID_KEYS` | Columns treated as record identifiers, not analysis variables | If new system columns are added |
| `WEIGHT_KEYS_GRAMS` | Fields stored in grams needing kg conversion in Module 11 | If new weight fields are added |
| `MANUAL_RANGES` | Hard biological limits for validated scoring instruments and neolab fields | Only for fields with formally defined hard limits (e.g. Apgar 0–10, Thompson 0–22, SpO2 0–100%) or clinically unambiguous neolab bounds (see neolab entries in script). Continuous physiological measures (temperature, gestation, birthweight, heart rate) deliberately have NO range set here -- use `user_ranges.xlsx` for researcher-defined ranges on these fields. |
| `KEY_UUID_OVERRIDES` | Explicit UUID overrides for duplicate question_key conflicts | See "Duplicate question_keys" section in README.md |
| `PII_PATTERNS_DATA` | All Tier 2 PII patterns -- the single source of truth | See "PII" section in README.md |
| `QUASI_ID_PATTERNS` | Patterns for fields flagged but not auto-removed | See "PII" section in README.md |

---

## Plausible ranges: two mechanisms

The pipeline offers two complementary ways to define plausible numeric ranges.  Both write to `suggested_plausible_min` / `suggested_plausible_max` in the dictionary Variables sheet, which Module 11 enforces at cleaning time (values outside the range are set to `NA`) and Module 16 codes as `-8` (implausible value).

### 1. `MANUAL_RANGES` (hard-coded in the build script)

`MANUAL_RANGES` is a named list of `question_key -> c(min, max)` pairs reserved for limits that are **definitionally fixed** by a clinical scoring system or physical law: Apgar (0–10), Thompson HIE score (0–22), SpO2 (0–100%).  Do not use this for continuous physiological measures.

### 2. `user_ranges.xlsx` (researcher-editable, persistent)

For researcher-defined ranges on continuous physiological variables (weight, temperature, gestational age, heart rate, etc.), edit `00_build_dictionary/user_ranges.xlsx`.  This file is **never overwritten by any pipeline script** -- ranges added here survive every dictionary rebuild.  Open the **Ranges** sheet, add one row per variable, and re-run the build script to bake the values into the dictionaries.  User-defined ranges **override** `MANUAL_RANGES` if there is a conflict.

See `README.md` (section 2) for the full format description and column definitions.

**Philosophy:** `MANUAL_RANGES` is for values where the bound is definitively known (a score cannot physically exceed 10); `user_ranges.xlsx` is for physiological plausibility thresholds where the researcher decides what is implausible for this study population.  Continuous physiological measures deliberately have NO range in `MANUAL_RANGES`: extreme values should be retained for analyst review unless the researcher explicitly sets a limit in `user_ranges.xlsx`.

---

### Admissions / Discharges datasets (all countries)

| Variable | Min | Max | Basis |
|----------|-----|-----|-------|
| `apgar1` | 0 | 10 | Apgar scale is formally defined 0-10; any value above 10 is a data-entry error by definition |
| `apgar5` | 0 | 10 | As above |
| `apgar10` | 0 | 10 | As above |
| `satsair` | 0 | 100 | Oxygen saturation is a percentage; values above 100 are physically impossible |
| `satso2` | 0 | 100 | As above |
| `dischsats` | 0 | 100 | SpO2 at discharge -- single reading on the discharge form, not split by air vs supplemental O2. Same definitional rationale as satsair/satso2: a percentage cannot exceed 100 or be negative. Present in both ZIM and MWI discharge forms as `DischSats`. |
| `thompscore` | 0 | 22 | Thompson HIE score has a formally defined maximum of 22 (sum of 9 items each scored 0-3, minus the first item which is 0-2) |

---

### Neolab (blood culture) dataset (ZIM and MWI)

Ranges were set conservatively based on observed raw data distributions from the actual
ZIM and MWI neolab CSV files.  The aim is to remove only values that are clearly
impossible data-entry artefacts while retaining any value that could plausibly occur in
a busy or resource-limited laboratory setting.

| Variable | Min | Max | Basis |
|----------|-----|-----|-------|
| `bcreturntime` | 0 | 1440 | Hours from specimen collection to result. Lower bound 0: negatives confirmed impossible in raw data (~46 ZIM rows, ~10 MWI rows). Upper bound 1440h (60 days): raw data shows a clear discontinuity at ~432h (ZIM p95) before values jump to 5000-14000h, which are clearly impossible. MWI max ~1000h (42 days) is plausible for delayed reporting in resource-limited settings; 1440h gives comfortable headroom above this while removing the impossible tail. |
| `poshours` | 0 | 120 | Hours from incubation start to positivity signal (ZIM only). Upper bound 120h (5 days) equals the standard maximum incubation period for blood cultures. Observed ZIM max = 50h; this limit will not remove any current values. |
| `timespent` | 0 | 72 | Hours for the laboratory procedure or consultation. ZIM raw data shows 99% of values below 13.2h, then a sharp discontinuous jump to 3069-21943h (clearly impossible for a procedure-level field). MWI max = 11.7h. Upper bound 72h (3 days) is deliberately generous and removes only the clearly impossible tail. |
| `episode` | 1 | *(none)* | Sequential episode counter per blood culture record. ZIM values reach up to 243 -- likely a row counter rather than a clinical episode count. No upper bound is applied (max is `NA`, so Module 11 enforces no upper limit). Lower bound 1 removes any zero or negative values. |

**Variables without ranges (neolab):** `admissionweight` was initially considered for a
neolab range but was found to have no numeric values in either the ZIM or MWI neolab raw
data files and was therefore excluded.  All other continuous neolab variables (e.g.
temperature, heart rate if present) follow the general philosophy: no range is set.

---

## Workbook structure

Each workbook contains four sheets:

### Variables sheet

One row per unique data key.  The primary sheet consumed by `00_setup.r`.

| Column | Description |
|--------|-------------|
| `question_key` | Normalised key (lowercase, no special characters) |
| `raw_value_column` | Raw CSV column: `{question_key}.value` |
| `raw_label_column` | Raw CSV column: `{question_key}.label` |
| `variable_label` | Human-readable label from the web editor |
| `raw_data_type` | Web-editor dataType (e.g. `single_select`, `number`) |
| `r_type` | Pipeline type: `numeric`, `boolean`, `categorical`, `object`, `datetime` |
| `harmonised_variable_name` | Snake_case name for the harmonised output |
| `use_in_analysis` | Whether included in pipeline output (`TRUE` / `FALSE`) |
| `weight_unit` | `"grams"` if weight conversion needed; otherwise blank |
| `confidential` | `TRUE` if flagged confidential in the web editor |
| `pii_tier` | `"1"` / `"2"` / `"quasi"` / blank |
| `suggested_plausible_min` / `_max` | Plausible numeric range (safe to edit manually) |
| `cleaning_note` | Free-text annotation (not consumed by pipeline; safe to edit) |

### ValueMaps sheet

One row per allowed option for every categorical field.  Consumed by
Module 04 (value cleaning).

| Column | Description |
|--------|-------------|
| `question_key` | Links back to Variables |
| `raw_code` | Raw coded value as stored in the database |
| `option_label` | Human-readable display label |
| `canonical_code` | Standardised code (defaults to `raw_code`; edit to recode) |

### PII_Patterns sheet

Tier 2 PII pattern reference table.  Read by Module 00a at runtime.

### ReviewNeeded sheet

Triage list of fields that may need manual attention.  Three review
reasons can appear:

- **Categorical with no value map entries** -- field has no option codes;
  either fix the download, change `r_type` to `"object"`, or add rows to
  ValueMaps manually.
- **Numeric without plausible range** -- informational only; only add a
  range for fields with formally defined hard limits (Apgar, Thompson
  scores etc.).
- **Unknown dataType** -- Neotree introduced a new field type; add a
  mapping to `PIPELINE_TYPE_MAP` in this script.

---

## Manual editing rules

Safe to edit directly in Excel (survives rebuild only for columns NOT
generated by this script):

| Column | Safe? | Notes |
|--------|-------|-------|
| `suggested_plausible_min` / `_max` | Yes -- but prefer `user_ranges.xlsx` for physiological ranges (survives rebuild) or `MANUAL_RANGES` for definitional limits |
| `cleaning_note` | Yes | Not consumed by any pipeline module |
| `canonical_code` (ValueMaps) | Yes | Recode raw options to canonical values |
| `pii_tier`, `pii_category` | NO | Overwritten on rebuild |
| `r_type`, `harmonised_variable_name` | NO | Overwritten on rebuild |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No `.xlsx` files appear after running | Data-key export not found | Check `DOWNLOADED_KEYS_BASE` path |
| Log shows `UUID override NOT applied` | Override UUID not found in metadata | Check UUID in `data-keys-metadata.json` |
| MWI maternity has discharge codes instead of birth codes | `KEY_UUID_OVERRIDES` not applied | Run current version of script |
| Build fails with column-name error | Wrong `data-keys-usage.xlsx` format | Confirm the normalisation logic matches the export |
