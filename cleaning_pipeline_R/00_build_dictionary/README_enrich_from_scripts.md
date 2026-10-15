# `00c_enrich_dictionary_from_scripts.r`

## Purpose

Adds four columns to the `Variables` sheet of each dictionary workbook, taken from the Neotree script files: the label shown in the app, whether the field is optional, its skip condition, and a comparison of its options with the `ValueMaps` sheet.

## When to run it

After `00_build_dictionary.r` and before `00e_enrich_from_public_dictionary.r`. Run it again when the dictionaries are rebuilt or when the files in `neotree_scripts/` change.

## What it does

For each base workbook `dictionaries/dictionary_<country>_<dataset>.xlsx` (files ending in `_enriched.xlsx` are not taken as input):

1. **Reads the country and dataset from the file name.**
2. **Chooses the scripts of the dataset.** These are the entries of `FACILITY_SCRIPT_MAP` for the country and dataset. `normalise_dataset_name()` first maps `combined_maternity_outcomes`, `dhis2_maternal_outcomes` and `maternity_completeness` to `maternal_outcomes`, and `infections` to `neolab`. For a dataset whose name contains `phc`, the scripts of the country whose title contains `PHC` or `primary ... health`, and `admis` or `disch` as appropriate, are added. If no script is chosen, or none of the chosen scripts is found among the files, the workbook is skipped and no output is written for it.
3. **Reads the fields of those scripts.** For every field on every screen it takes the key, the label, the `optional` flag, the options, and the condition. The condition is the field condition, or the screen condition if the field has none, or `(screen condition) AND (field condition)` if both exist and differ. Keys are put in lower case.
4. **Summarises each key across the scripts.**

   | Column | Value |
   |--------|-------|
   | `display_label` | The most frequent non-empty label. |
   | `optional` | The flag, if all scripts that state it agree; otherwise empty. |
   | `skip_condition` | The most frequent non-empty condition; empty if there is none. |
   | `valuemap_check` | Compares the option codes of the most frequent option list with the `raw_code` values of the variable in `ValueMaps`. `TRUE` if the two sets differ or the variable has no row in `ValueMaps`; `FALSE` if they are the same; empty if the field has no options in the scripts. |

5. **Writes the four columns** into the `Variables` sheet, matching on `question_key`. Existing columns of the sheet are not changed. A variable that is not found in the scripts keeps empty cells in the four columns. If the columns already exist they are refreshed in place; otherwise they are appended after the last column.
6. **Saves the workbook.**

## Inputs

| File | Description |
|------|-------------|
| `dictionaries/dictionary_<country>_<dataset>.xlsx` | Base workbooks from `00_build_dictionary.r` |
| `neotree_scripts/zim-scripts/*.json`, `neotree_scripts/mwi-scripts/*.json` | Neotree script files |

The script stops if `dictionaries/` or `neotree_scripts/` does not exist, if no script file is found, or if there is no base workbook.

## Outputs

| File | Description |
|------|-------------|
| `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx` | Copy of the base workbook with the four columns. An existing file is replaced. |

The columns are described in `dictionaries/README.md`. Progress is printed on the console with the prefix `[00c]`: for each workbook, the number of scripts matched, the number of variables filled, and the number of variables with `valuemap_check` `TRUE`.

## Configuration

Set at the top of the script.

| Setting | Default | Effect |
|---------|---------|--------|
| `OVERWRITE_IN_PLACE` | `FALSE` | `FALSE` writes `_enriched.xlsx` copies. `TRUE` writes the columns into the base workbooks. |
| `NEOTREE_SCRIPTS_BASE` | `neotree_scripts` | Folder holding `zim-scripts/` and `mwi-scripts/`. |
| `DICT_DIR` | `dictionaries` | Folder of the dictionary workbooks. |

`FACILITY_SCRIPT_MAP` lists the script identifiers per country, dataset and facility. The same kind of map exists in `00d_build_user_dictionary.r` and in `16_na_reason_coding/helpers/03_facility_script_map.r`; each script reads its own.

## How to run it

```r
source("00_build_dictionary/00c_enrich_dictionary_from_scripts.r")
```

or `Rscript 00_build_dictionary/00c_enrich_dictionary_from_scripts.r`. Packages used: `jsonlite`, `openxlsx`.
