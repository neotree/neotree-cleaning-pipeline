# Dictionary build scripts

## Purpose

The scripts in this folder build the data dictionaries that the cleaning pipeline reads, add documentation columns to them, build the dictionaries for data users, and check the result.

## Scripts and order

| Step | Script | Writes | Described in |
|------|--------|--------|--------------|
| 1 | `00_build_dictionary.r` | `dictionaries/dictionary_<country>_<dataset>.xlsx` | this file |
| 2 | `00c_enrich_dictionary_from_scripts.r` | `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx` | `README_enrich_from_scripts.md` |
| 3 | `00e_enrich_from_public_dictionary.r` | adds columns to the `_enriched.xlsx` workbooks | `README_enrich_from_public.md` |
| 4 | `00d_build_user_dictionary.r` | `user_dictionaries/neotree_user_dict_<country>.xlsx` | `README_user_dictionary.md` |
| 5 | `validate_dictionaries.r` | console report | this file |

The sheets and columns of the dictionary workbooks are described in `dictionaries/README.md`.

Running `00_build_dictionary.r` runs steps 1 to 4 in order, removes staff names (see below) and checks the result; step 5 is run separately. With `RUN_FOLLOW_ON_STEPS` set to `FALSE` the script builds the base dictionaries only, and does not remove staff names.

Step 1 is required before the cleaning pipeline can run. Steps 2 to 4 produce documentation and are not read by the cleaning pipeline. Step 3 must follow step 2, because step 2 starts again from the base workbook and replaces the `_enriched.xlsx` copy.

The data keys and the script metadata are downloaded from the Neotree web editors with a Neotree account; see `neotree_data_keys/README.md` and `neotree_scripts/README.md`. They are not part of the published repository.

## When to run it

Run `00_build_dictionary.r` when:

- a new data-key export is placed in `neotree_data_keys/downloaded/`;
- a constant in `00_build_dictionary.r` or a row of `user_ranges.xlsx` is changed;
- new Neotree script files are placed in `neotree_scripts/`.

## `00_build_dictionary.r`

### What it does

The script builds one workbook for each country and dataset listed in `BUILD_PLAN`. If one combination fails, the error is printed and the others are still built. For each combination, `build_dictionary()` does the following.

1. **Selects the keys of the dataset.** A data key belongs to the dataset when it is used by a script whose title matches the regular expression of the dataset in `DATASET_FILTERS` (case is ignored). Deleted keys and option entries are left out.
2. **Keeps one row per variable.** `question_key` is the key name in lower case with everything except letters and digits removed. When several keys give the same `question_key`, the one with the latest publish date is kept. An entry in `KEY_UUID_OVERRIDES` names the key to keep instead, for one country, dataset and `question_key`.
3. **Fills the `Variables` columns.** `r_type` comes from `PIPELINE_TYPE_MAP`. `use_in_analysis` is `FALSE` for free-text keys, summary-table keys and draft keys. `weight_unit` is `grams` for the keys in `WEIGHT_KEYS_GRAMS`. The record-level system keys in `RECORD_ID_KEYS` receive a `record_id_role`; `uid` and `facility` receive a `linkage_role`.
4. **Adds legacy variables.** Each entry of `LEGACY_VARIABLES` for the country and dataset is added as a row, unless the `question_key` is already present. These are fields that occur in the data but not in the data-key export.
5. **Adds derived variables.** Each entry of `DERIVED_VARIABLES` for the country and dataset is added as a row, unless already present. These are columns computed by the cleaning pipeline. Their `raw_value_column` and `raw_label_column` are empty and their `raw_data_type` is `derived`.
6. **Applies `MANUAL_RANGES`.** For each listed `question_key`, the lower and upper limits are filled where they are still empty.
7. **Applies `user_ranges.xlsx`.** See below. These limits replace any limit set so far.
8. **Assigns PII tiers.** `pii_tier` is `1` where `confidential` is `TRUE`. Each pattern of `PII_PATTERNS_DATA` is then tested against `question_key`; a match on a variable without a tier gives tier `2`, with the category and the pattern recorded. Each pattern of `QUASI_ID_PATTERNS` is tested in the same way and gives `quasi` to a variable still without a tier.
9. **Builds `ValueMaps`.** The options of the kept key are listed in order, with `canonical_code` equal to `raw_code`. Leading and trailing spaces are removed from codes and labels. Each label is kept once per variable. Options that exist in other non-deleted versions of the same key, and whose code and label are both absent so far, are appended after them.
10. **Applies `VARIABLE_PATCHES`.** Each entry sets the named columns of one variable in the listed datasets of one country.
11. **Applies `VALUEMAP_PATCHES`.** Each entry carries one action on one variable:

    | Action | Effect |
    |--------|--------|
    | `add_rows` | Appends the given options. An option whose label already exists for the variable is not added. |
    | `update_canonical` | Sets `canonical_code` for the given `raw_code` values. |
    | `remove_duplicate_raw_code` | Where a `raw_code` has several rows, keeps the row with the given label and removes the others. |

    A patch for a variable or code that is not present is skipped.
12. **Builds `ReviewNeeded`.** Lists categorical variables with no row in `ValueMaps`, numeric variables with no limits, and variables with no `r_type`.
13. **Writes the workbook** with the sheets `Variables`, `ValueMaps`, `PII_Patterns` and `ReviewNeeded`.

### Staff names

Some answer options in the data keys and the scripts are the names or codes of health workers, and some script titles contain names. No dictionary receives them:

1. **Script titles.** Each title listed in `00_build_dictionary/private/script_title_replacements.tsv` (columns `original_title` and `published_title`) is replaced as soon as the data keys are read. The `private/` folder is not part of the published repository.
2. **Answer options of staff fields.** The fields are the keys matched by `STAFF_KEY_PATTERN` in `staff_fields.r`. Their options are not written to `ValueMaps`, and their `Values / Codes` cell in the user dictionaries reads `Not listed (staff identifier)`. `00d_build_user_dictionary.r` reads the same file.
3. **Other text.** The answer options of staff fields in the data keys and the scripts are collected. Any of them still found in a cell of a dictionary is replaced by `[staff]`. Names of two or more words are matched in any letter case; single words and codes only in their exact case. Header rows are not changed, and a string that is also used outside staff fields, such as `Other` or a word that occurs in a question, is left as it is.
4. **Check.** Every workbook file in `dictionaries/` and `user_dictionaries/` is then read in full, including text kept in the file but shown in no cell. The run stops with an error, naming the files and the number of matches, if a staff name, a staff code or a listed title is found.

### Datasets

`BUILD_PLAN` lists the datasets built for each country:

| Country | Datasets |
|---------|----------|
| `ZIM` | `admissions`, `discharges`, `maternal_outcomes`, `phc_admissions`, `phc_discharges`, `neolab`, `baseline`, `infections`, `twenty_8_day_follow_up` |
| `MWI` | `admissions`, `discharges`, `maternal_outcomes`, `phc_admissions`, `phc_discharges`, `combined_maternity_outcomes`, `dhis2_maternal_outcomes`, `maternity_completeness`, `neolab` |

`DATASET_FILTERS` gives the script-title expression of each dataset:

```
admissions                   Admission
discharges                   Discharge
maternal_outcomes            Maternal
maternity_completeness       Maternal
phc_admissions               PHC.*Admission|Generic PHC Admission|Kasungu.*Admission
phc_discharges               PHC.*Discharge|Generic PHC Discharge|NeoDischarge.*PHC
combined_maternity_outcomes  Maternal|DHIS2 Mat|Maternity
dhis2_maternal_outcomes      DHIS2.*Mat|DHIS.*Matern
neolab                       ^NeoLab - (Zim|Malawi)
baseline                     Baseline|Retrospective
infections                   Infection|NeoInfect
twenty_8_day_follow_up       28.?[Dd]ay|Follow.?[Uu]p|28.*[Ff]ollow|NeoFollow
```

### Types

`PIPELINE_TYPE_MAP` gives the `r_type` of each data type of the export:

| Data type in the export | `r_type` |
|-------------------------|----------|
| `number`, `period`, `timer` | `numeric` |
| `date`, `datetime` | `datetime` |
| `yesno` | `boolean` |
| `single_select`, `dropdown`, `multi_select`, `checklist`, `diagnosis`, `diagnosis_symptom_risk`, `diagnosis_symptom_sign` | `categorical` |
| `text`, `zw_edliz_summary_table`, `mwi_edliz_summary_table` | `object` |

### Limits for numeric variables

`MANUAL_RANGES` holds limits that apply in every dataset containing the variable:

| `question_key` | Lowest | Highest |
|----------------|--------|---------|
| `apgar1`, `apgar5`, `apgar10` | 0 | 10 |
| `satsair`, `satso2`, `dischsats` | 0 | 100 |
| `thompscore` | 0 | 22 |
| `bcreturntime` | 0 | 1440 |
| `poshours` | 0 | 120 |
| `timespent` | 0 | 72 |
| `episode` | 1 | none |

Legacy and derived variables carry the limits given in their own entries.

`user_ranges.xlsx`, in this folder, holds further limits and is edited by hand. The build script only reads it. It has one sheet per dataset:

| Dataset | Sheet |
|---------|-------|
| `admissions` | `Admissions` |
| `discharges` | `Discharges` |
| `maternal_outcomes` | `Maternal_outcomes` |
| `phc_admissions` | `PHC_admissions` |
| `phc_discharges` | `PHC_discharges` |
| `neolab` | `Neolab` |
| `infections` | `Infections` |
| `baseline` | `Baseline` |
| `twenty_8_day_follow_up` | `Follow_up` |
| `combined_maternity_outcomes` | `Comb_maternity` |
| `dhis2_maternal_outcomes` | `DHIS2_maternal` |
| `maternity_completeness` | `Maternity_completeness` |

The first row of a sheet is skipped and the second row is the header. The columns read are `question_key`, `suggested_plausible_min` and `suggested_plausible_max`. A row is used when its `question_key` exists in the dataset and at least one limit is a number; both limits of the variable are then set to the values of the row, so a blank limit in the row leaves that side without a limit. Rows with a blank `question_key` are ignored. If the file or the sheet is missing, the step is skipped with a message.

### Inputs

| File | Description |
|------|-------------|
| `neotree_data_keys/downloaded/neotree_data_keys_zimbabwe/data-keys-metadata.json` | Data keys and options of the Zimbabwe export |
| `neotree_data_keys/downloaded/neotree_data_keys_zimbabwe/data-keys-usage.xlsx` | Which script uses which key |
| `neotree_data_keys/downloaded/neotree_data_keys_malawi/data-keys-metadata.json` | Data keys and options of the Malawi export |
| `neotree_data_keys/downloaded/neotree_data_keys_malawi/data-keys-usage.xlsx` | Which script uses which key |
| `00_build_dictionary/user_ranges.xlsx` | Limits for numeric variables (optional) |
| `neotree_scripts/zim-scripts/*.json`, `neotree_scripts/mwi-scripts/*.json` | Script metadata, read for the staff-name check and by steps 2 and 4 |
| `00_build_dictionary/private/script_title_replacements.tsv` | Script titles to replace (optional, not published) |
| `00_build_dictionary/staff_fields.r` | Keys of the staff fields |

The folder names are set in `DOWNLOADED_KEYS_BASE` and `COUNTRY_FOLDERS`.

### Outputs

| File | Description |
|------|-------------|
| `dictionaries/dictionary_<country>_<dataset>.xlsx` | One workbook per combination in `BUILD_PLAN`. An existing file is replaced. |
| `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx`, `user_dictionaries/neotree_user_dict_<country>.xlsx` | Written by steps 2 to 4 when `RUN_FOLLOW_ON_STEPS` is `TRUE` |
| `neotree_pipeline.log` | Log lines are appended; they are also printed on the console. |

### Constants

A permanent change to a dictionary is made in one of these constants, followed by a rebuild.

| Constant | Holds |
|----------|-------|
| `RUN_FOLLOW_ON_STEPS` | Whether steps 2 to 4, the removal of staff names and the check are run |
| `STAFF_GENERIC_OPTIONS` | Answer options never treated as staff names |
| `STAFF_TEXT_PLACEHOLDER` | Text written in place of a staff name |
| `TITLE_REPLACEMENTS_FILE` | Location of the list of script titles to replace |
| `BUILD_PLAN` | Datasets built per country |
| `DATASET_FILTERS` | Script-title expression per dataset |
| `PIPELINE_TYPE_MAP` | `r_type` per data type |
| `RECORD_ID_KEYS` | Record-level system keys |
| `WEIGHT_KEYS_GRAMS` | Weight variables |
| `MANUAL_RANGES` | Limits for numeric variables |
| `KEY_UUID_OVERRIDES` | The key to keep where two keys share a `question_key` |
| `LEGACY_VARIABLES` | Variables absent from the export |
| `DERIVED_VARIABLES` | Variables computed by the cleaning pipeline |
| `VARIABLE_PATCHES` | Corrections to columns of `Variables` |
| `VALUEMAP_PATCHES` | Corrections to `ValueMaps` |
| `PII_PATTERNS_DATA` | Content of the `PII_Patterns` sheet |
| `QUASI_ID_PATTERNS` | Patterns that give `pii_tier` `quasi` |

A variable added to `DERIVED_VARIABLES` must also be added to `DERIVED_KEYS` in `00d_build_user_dictionary.r` to appear in the user dictionary.

### Functions

`load_country_keys(country)` reads the two export files of a country and returns a list with `metadata`, `usage` and `opt_lookup`.

`build_dictionary(country, dataset, out_path = NULL, include_review = TRUE, keys = NULL)` writes one workbook and returns, invisibly, a list with `variables`, `value_maps` and `review_needed`. With `out_path = NULL` the file is named `dictionary_<country>_<dataset>.xlsx` in `dictionaries/`. With `include_review = FALSE` the `ReviewNeeded` sheet is left out.

## `validate_dictionaries.r`

Checks the base workbooks in `dictionaries/` and prints `[OK]`, `[WARN]` or `[FAIL]` for each check, then a summary. It changes no file.

The six workbooks for `admissions`, `discharges` and `maternal_outcomes` of both countries must exist. The other workbooks are checked when present.

| Check | Result if not met |
|-------|-------------------|
| The sheets `Variables`, `ValueMaps`, `PII_Patterns` and `ReviewNeeded` exist | fail |
| `Variables`, `ValueMaps` and `PII_Patterns` have all their columns | fail |
| `PII_Patterns` has at least one row and no blank pattern | fail |
| `PII_Patterns` has no repeated pattern | warning |
| Every variable with `use_in_analysis` `TRUE` has an `r_type` | warning |
| Every `question_key` in `ValueMaps` exists in `Variables` | warning |
| Where both limits are set, the lower is below the upper | fail |
| `pii_tier` is `1`, `2`, `quasi` or empty | fail |
| Every tier 2 variable has a `pii_matching_pattern` | warning |
| Every variable with `confidential` `TRUE` has tier `1` or `2` | warning |
| In the Zimbabwe admissions workbook, the Apgar, oxygen saturation and Thompson score limits equal those of `EXPECTED_RANGES_ZIM_ADM` | warning |

For each workbook it also prints the number of variables, value-map rows and review items, and the number of variables per `r_type` and per `pii_tier`.

When run with `Rscript`, the exit status is 1 if any check failed and 0 otherwise.

## How to run it

Each script finds the pipeline folder from its own location, so it can be started from any working directory. One command runs steps 1 to 4, the removal of staff names and the check:

```r
source("00_build_dictionary/00_build_dictionary.r")
```

The validation is run afterwards:

```r
source("00_build_dictionary/validate_dictionaries.r")
```

or, from a terminal:

```
Rscript 00_build_dictionary/00_build_dictionary.r
```

Packages used: `jsonlite`, `readxl`, `dplyr`, `tidyr`, `stringr`, `writexl`, `tibble`, `janitor`, `purrr`, `logger` (build); `jsonlite`, `openxlsx`, `readxl` (steps 2 to 4); `openxlsx` (validation).
