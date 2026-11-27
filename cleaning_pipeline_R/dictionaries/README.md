# Data dictionaries

## Purpose

This folder holds the data dictionaries of the cleaning pipeline: one Excel workbook per country and dataset, listing the variables of that dataset, their types, their allowed codes and the rules for removing personal data.

The workbooks are written by the scripts in `00_build_dictionary/`. They are generated files: a rebuild replaces them, so a change made by hand in a workbook is lost. Permanent changes are made in the build script (see `00_build_dictionary/README.md`).

## Files

Each dataset has two workbooks:

| File | Written by | Content |
|------|------------|---------|
| `dictionary_<country>_<dataset>.xlsx` | `00_build_dictionary.r` | The base dictionary. |
| `dictionary_<country>_<dataset>_enriched.xlsx` | `00c_enrich_dictionary_from_scripts.r` and `00e_enrich_from_public_dictionary.r` | A copy of the base dictionary with extra documentation columns in the `Variables` sheet. |

`<country>` is `zim` or `mwi`. The datasets are:

| Dataset | `zim` | `mwi` |
|---------|:-----:|:-----:|
| `admissions` | yes | yes |
| `discharges` | yes | yes |
| `maternal_outcomes` | yes | yes |
| `phc_admissions` | yes | yes |
| `phc_discharges` | yes | yes |
| `neolab` | yes | yes |
| `baseline` | yes | |
| `infections` | yes | |
| `twenty_8_day_follow_up` | yes | |
| `combined_maternity_outcomes` | | yes |
| `dhis2_maternal_outcomes` | | yes |
| `maternity_completeness` | | yes |

The cleaning pipeline reads the base workbook, `dictionary_<country>_<dataset>.xlsx`, and from it the sheets `Variables`, `ValueMaps` and `PII_Patterns`. If the workbook for a dataset does not exist, `00_setup.r` uses the workbook of the dataset named in `DICT_FALLBACK`, where one is defined. The enriched workbooks are read by `00d_build_user_dictionary.r`.

## Sheets of a base workbook

| Sheet | One row per |
|-------|-------------|
| `Variables` | variable |
| `ValueMaps` | allowed option of a variable |
| `PII_Patterns` | column-name pattern that marks personal data |
| `ReviewNeeded` | variable that the build script flags for checking |

### `Variables`

| Column | Meaning |
|--------|---------|
| `environment` | Country name. |
| `dataset` | Country code and dataset, as `<COUNTRY>_<dataset>`. |
| `question_key` | Name of the variable: the data key name in lower case with everything except letters and digits removed. Unique within the sheet. |
| `raw_value_column` | Name of the column holding the value in the input data: `question_key` followed by `.value`. Empty for derived variables. |
| `raw_label_column` | Name of the column holding the label in the input data: `question_key` followed by `.label`. Empty for derived variables. |
| `variable_label` | Label of the data key. |
| `raw_data_type` | Data type of the key in the data-key export. `derived` for variables computed by the pipeline. |
| `r_type` | Type used by the pipeline: `numeric`, `boolean`, `categorical`, `datetime` or `object`. Empty when the data type is not known to the build script. |
| `section` | Titles of the scripts that use the key, sorted and separated by `; `. For legacy and derived variables, a fixed text naming their origin. |
| `harmonised_variable_name` | The key name in lower case with underscores between words. |
| `use_in_analysis` | `FALSE` for free-text keys, summary-table keys and draft keys; `TRUE` otherwise. |
| `weight_unit` | `grams` for weight variables; otherwise empty. |
| `confidential` | Confidentiality flag of the key in the data-key export. The HIV and syphilis clinical fields listed in `HIV_CLINICAL_KEYS` and the fields in `OTHER_KEPT_KEYS` (Zimbabwe `ethnicity2`) in `00_build_dictionary.r` are set to `FALSE`, so the cleaned files keep them. |
| `record_id_role` | Role of record-level system keys such as the record identifier, the facility and the timestamps; otherwise empty. |
| `linkage_role` | `primary_linkage_key` for `uid`, `secondary_linkage_key` for `facility`; otherwise empty. |
| `suggested_plausible_min` | Lowest accepted value of a numeric variable. Empty for no lower limit. |
| `suggested_plausible_max` | Highest accepted value of a numeric variable. Empty for no upper limit. |
| `cleaning_note` | Free-text note. Filled for legacy and derived variables. |
| `key_unique_key` | Identifier of the data key in the export. Empty for legacy and derived variables. |
| `pii_tier` | `1` when `confidential` is `TRUE`; `2` when `question_key` matches a pattern of the `PII_Patterns` sheet; `quasi` for a quasi-identifier; otherwise empty. |
| `pii_category` | Kind of personal data: `direct_identifier` for tier 1, the category of the matching pattern for tier 2. |
| `pii_matching_pattern` | The pattern that gave tier 2. |

### `ValueMaps`

| Column | Meaning |
|--------|---------|
| `question_key` | Variable the option belongs to. Matches `question_key` in `Variables`. |
| `raw_code` | Code of the option as stored in the data. |
| `option_label` | Display label of the option. |
| `option_order` | Position of the option within the variable. Options of the current version of the key come first, followed by options that exist only in other versions of the key, then options added by the build script. |
| `option_uuid` | Identifier of the option in the data-key export. Empty for options added by the build script. |
| `canonical_code` | Code that the pipeline writes for this option. Equal to `raw_code` unless the build script sets a different one. |

A variable may have several rows with the same `raw_code` and different labels; each label is kept once per variable.

### `PII_Patterns`

The same table is written to every workbook.

| Column | Meaning |
|--------|---------|
| `pattern` | Regular expression tested against column names. |
| `pattern_type` | How the pattern is meant to match: `suffix_match`, `contains` or `exact_match`. |
| `pii_category` | Kind of personal data, for example `personal_name`, `phone_number`, `address`, `identifier`, `date_of_birth`. |
| `reason` | Short description of what the pattern covers. |
| `countries` | Countries in which such columns occur. |
| `examples` | Example column names. |
| `added_date` | Date recorded for the pattern. |
| `notes` | Free-text note. |

### `ReviewNeeded`

Holds the rows of `Variables` that meet one of the conditions below, with all the columns of `Variables` and one more:

| Column | Meaning |
|--------|---------|
| `review_reason` | Why the variable is listed. |

| `review_reason` | Condition |
|-----------------|-----------|
| `Categorical with no value map entries` | `r_type` is `categorical` and the variable has no row in `ValueMaps`. |
| `Numeric without plausible range` | `r_type` is `numeric` and both limits are empty. |
| `Unknown dataType (not in PIPELINE_TYPE_MAP)` | `r_type` is empty. |

The sheet is a list for checking. The pipeline does not read it.

## Additional columns of an enriched workbook

The enriched workbook has the same sheets. Its `Variables` sheet carries these further columns.

Written by `00c_enrich_dictionary_from_scripts.r`, from the Neotree script files:

| Column | Meaning |
|--------|---------|
| `display_label` | Label of the field as shown in the app; the most frequent label across the scripts of the dataset. |
| `optional` | Whether the field is optional. Empty when the scripts disagree. |
| `skip_condition` | Condition under which the field is shown; the most frequent across the scripts. Empty when the field is always shown. |
| `valuemap_check` | `TRUE` when the option codes of the field in the scripts differ from the `raw_code` values in `ValueMaps`; `FALSE` when they are the same set; empty when the field has no options in the scripts. |

The four columns are empty for a variable that is not found in the scripts of its dataset.

Written by `00e_enrich_from_public_dictionary.r`, from the public data dictionary:

| Column | Meaning |
|--------|---------|
| `public_meaning` | Meaning of the variable. |
| `public_data_type` | Data type as documented there. |
| `public_dependency` | Dependency on other variables, in words. |
| `public_range` | Documented range. |
| `old_variable_name` | Earlier name of the variable, if different from the current one. |
| `timeline_of_change` | Documented change of name or definition. |
| `public_reference` | Reference cited. |
| `public_dict_matched` | `TRUE` when an entry was found for the variable. |

These columns are documentation. The cleaning pipeline does not use them.
