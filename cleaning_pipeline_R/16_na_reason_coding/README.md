# Module 16: NA Reason Coding

## Purpose

Gives every empty cell of the cleaned dataset a code that states why it is empty. The codes are written to companion files; the cleaned dataset itself is not changed.

## When it runs

After Module 15, on `df_clean`. `run_pipeline.r` runs the module only when the folder in `cfg$neotree_scripts_dir` exists; otherwise it logs a warning and continues without it.

## What it does

### The four codes

| Code | Name | Assigned when |
|------|------|---------------|
| `-6` | Redacted | The raw value matches a PII value pattern. |
| `-7` | Not applicable | The skip condition of the field in the Neotree script evaluates to false for that record, so the field was not shown. |
| `-8` | Invalid / removed | The raw cell held a value, the value is not PII, and the cleaned cell is empty. |
| `-9` | Unknown | Every other empty cell: the raw cell was empty, held a missing-value placeholder, or has no raw counterpart. |

The key columns `uid`, `facility` and `uniquekey` are not coded.

### Order of the rules

For each empty cell of the cleaned dataset:

1. If the raw value matches a PII pattern, the code is `-6`. Nothing overrides it.
2. Otherwise, if a skip condition is found for the field and evaluates to false, the code is `-7`. This applies whether the raw cell was empty or not.
3. Otherwise, if the raw cell held a value, the code is `-8`.
4. Otherwise the code is `-9`.

### Raw values

The module reads the input CSV (`cfg$csv_filepath`) again, with every column as text.

- Each row of the cleaned dataset is paired with the first raw row that has the same `uid`.
- Each cleaned column is paired with the raw column of the same name, compared in lower case and without punctuation, with the suffix `.value` or `.valuedischarge` or with no suffix. A cleaned column with no such raw column has no raw value.

A raw value counts as empty when, after trimming spaces, it is blank or one of `nan`, `none`, `na`, `n/a`, `null`, `NaN`, `None`, `NA`, `N/A`, `NULL`.

### PII value patterns

A raw value is treated as PII when it matches one of the patterns in `PII_PATTERNS_16`:

| Pattern | Shape |
|---------|-------|
| `phone_international` | Whole value is a Zimbabwe or Malawi country prefix followed by the subscriber digits, with or without a leading `+` |
| `phone_local_zw`, `phone_local_mwi` | Whole value is a ten-digit local mobile number |
| `email` | Value contains an e-mail address |
| `nhs_number` | Whole value is three, three and four digits separated by hyphens or spaces |

### Skip logic

`load_all_scripts()` reads every file whose name ends in `metadata.json` in the `zim-scripts/` and `mwi-scripts/` subfolders of `cfg$neotree_scripts_dir`. For every field on every screen it stores one condition:

- the screen condition, if the field has none of its own;
- the field condition, if the screen has none;
- `(screen condition) and (field condition)`, if both exist.

A field with no condition is always shown and never receives `-7`.

Each record is assigned a script by `resolve_script_id()`, in this order:

1. the value of the raw `scriptid` (or `script_id`) column, if it is listed in `EXACT_MATCH_SCRIPT_IDS`;
2. for Malawi maternal datasets, a fixed script if the raw value is listed in `MWI_MATERNAL_FIREBASE_IDS`;
3. the entry of `FACILITY_SCRIPT_MAP` for the country, the dataset and the record's `facility`.

Before the look-up, `normalise_dataset_name()` maps `combined_maternity_outcomes`, `dhis2_maternal_outcomes` and `maternity_completeness` to `maternal_outcomes`, and `infections` to `neolab`. Other dataset names are used unchanged. A record with no matching script is not evaluated for skip logic.

The condition for a field is found by the cleaned column name, in lower case and without punctuation. `translate_condition()` turns it into an R expression:

| In the script | Read as |
|---------------|---------|
| `$FieldKey` | the raw value of that field for the record, as text |
| `=` | equal to |
| `!=`, `>`, `<`, `>=`, `<=` | unchanged |
| `'text'` | the text |
| `true`, `false` | `TRUE`, `FALSE` |
| `and`, `or` | both, either |
| `( )` | grouping |

The value of `$FieldKey` is taken from the raw column that corresponds to a column of the cleaned dataset. A field with no such column, or with an empty raw value, is read as missing.

The cell receives `-7` only when the expression returns `FALSE`. If the expression returns `TRUE`, returns a missing result, cannot be parsed or raises an error, the cell keeps the code from rule 3 or 4.

## Inputs

| Object / file | Description |
|---------------|-------------|
| `df_clean` | Cleaned data frame from Module 15 |
| `cfg$csv_filepath` | The input CSV, read again as text |
| `cfg$neotree_scripts_dir` | Folder holding `zim-scripts/` and `mwi-scripts/` with the Neotree script JSON files |
| `cfg$country`, `cfg$dataset` | Used to choose the script for each record |
| `cfg$output_csv` | Path of the cleaned CSV; the output file names are built from it |
| `cfg$report_dir` | Folder for the module report |

## Outputs

`<cleaned>` stands for the path in `cfg$output_csv` without `.csv`.

| Object / file | Description |
|---------------|-------------|
| `df_na_reasons` | Data frame with the rows and columns of `df_clean`. Key columns are copied; every other cell holds the code where the cleaned cell is empty and is empty otherwise. |
| `na_reasons_long` | Data frame with one row per coded cell: `uid`, `facility`, `variable`, `na_reason`, `raw_value`. |
| `<cleaned>_na_reasons.csv.gz` | `df_na_reasons`. Always written. |
| `<cleaned>_na_reasons_long.csv.gz` | `na_reasons_long`. Written when `cfg$save_na_reasons_long` is `TRUE`. |
| `<cleaned>_na_reasons_summary.csv` | One row per variable, sorted by number of empty cells, largest first. Always written. Columns below. |
| `<cleaned>_na_coded.csv` | The cleaned dataset with every column as text and every empty cell replaced by its code. Written when `cfg$save_na_coded` is `TRUE`. |
| `16_na_reason_coding_summary.txt` in `cfg$report_dir` | Country, dataset, input file, scripts folder, number of scripts loaded, number of cells per code, the twenty variables with most empty cells, and the paths of the output files. Counts and column names only. |

Columns of the summary file:

| Column | Meaning |
|--------|---------|
| `variable` | Column name in the cleaned dataset |
| `n_total` | Number of rows |
| `n_present` | Rows with a value |
| `n_missing` | Rows without a value |
| `pct_missing` | `n_missing` as a percentage of `n_total`, one decimal |
| `n_not_applicable` | Cells coded `-7` |
| `n_invalid` | Cells coded `-8` |
| `n_unknown` | Cells coded `-9` |
| `n_redacted` | Cells coded `-6` |

`assert_pii_removed()` from `00_setup.r` is called on each table before it is written, and stops the run if the check fails. The long table holds raw values, so the check applies to those values. In the summary table the `variable` column is left out of the value scan, after the module has confirmed that it holds only column names of the cleaned dataset.

## Functions

| Function | File | Arguments | Returns |
|----------|------|-----------|---------|
| `classify_na_reasons()` | `16_na_reason_coding.r` | `df_clean`, `df_raw`, `script_conditions`, `cfg` | List with `$wide`, `$long` and `$counts` |
| `build_variable_summary()` | `16_na_reason_coding.r` | `na_long`, `n_rows`, `data_cols` | Per-variable summary data frame |
| `build_clean_coded()` | `16_na_reason_coding.r` | `df_clean`, `df_na_reasons` | Text data frame with codes in the empty cells |
| `load_all_scripts()` | `helpers/01_load_scripts.r` | `scripts_dir` | List with `$conditions` (one row per field) and `$index` (one row per script) |
| `translate_condition()` | `helpers/02_condition_evaluator.r` | `condition_str` | R expression as text, or `NA` |
| `resolve_script_id()` | `helpers/03_facility_script_map.r` | `scriptid_raw`, `facility`, `country`, `dataset` | Script identifier, or `NA` |

## Configuration

| Setting in `00_setup.r` | Default | Effect |
|-------------------------|---------|--------|
| `NEOTREE_SCRIPTS_DIR` | `neotree_scripts` in the pipeline folder | Folder of script JSON files. The module stops if it does not exist. |
| `SAVE_NA_CODED` | `TRUE` | Writes `<cleaned>_na_coded.csv`. |
| `SAVE_NA_REASONS_LONG` | `FALSE` | Writes `<cleaned>_na_reasons_long.csv.gz`. |

`FACILITY_SCRIPT_MAP`, `EXACT_MATCH_SCRIPT_IDS` and `MWI_MATERNAL_FIREBASE_IDS` in `helpers/03_facility_script_map.r` hold the script identifiers. A new facility or script is added there.

## Other files in this folder

`skip_logic_reference.*` are reference listings of the fields that carry a skip condition. The module does not read them.
