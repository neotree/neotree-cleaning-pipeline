# `00e_enrich_from_public_dictionary.r`

## Purpose

Adds eight documentation columns to the `Variables` sheet of each dictionary workbook, taken from the public data dictionary in `og_dictionaries/`. It does not change `ValueMaps`, codes, limits or any other existing column.

## When to run it

After `00c_enrich_dictionary_from_scripts.r`. Run it again when the dictionaries are rebuilt, when `00c` is run again, or when the public data dictionary file is replaced.

## What it does

1. **Reads the public data dictionary.** The sheets named in `PUBLIC_SHEETS` are read without a header row. A row with a value in the third column starts a variable; from that row the script takes the variable name (column 3), meaning (4), data type (7), dependency (8), range (9), old variable name (10), timeline of change (11) and reference (13). Rows below it with an empty third column are option rows and are not used. A sheet that cannot be read is skipped.
2. **Builds one index for all sheets.** Each entry is indexed by its variable name and by its old variable name, in lower case. When a name occurs more than once, the first entry is kept.
3. **Fills each workbook.** Each output is built from the base workbook in `dictionaries/`. The four columns written by `00c_enrich_dictionary_from_scripts.r` are carried over from an existing `_enriched.xlsx` copy only when that copy is not older than the base workbook and lists the same variables in the same order; otherwise they are left out and a message says so. Each variable is looked up by `question_key` and, if that is not found, by `harmonised_variable_name`.

   | Column | Value |
   |--------|-------|
   | `public_meaning` | Meaning |
   | `public_data_type` | Data type |
   | `public_dependency` | Dependency |
   | `public_range` | Range |
   | `old_variable_name` | Old variable name, if it differs from the current name |
   | `timeline_of_change` | Timeline of change |
   | `public_reference` | Reference |
   | `public_dict_matched` | `TRUE` if an entry was found, `FALSE` otherwise |

   For a variable with no entry, the seven text columns are empty.
4. **Writes the eight columns** into the `Variables` sheet. If they already exist they are refreshed in place; otherwise they are appended after the last column. A workbook with no `Variables` sheet, or an empty one, is skipped.
5. **Saves the workbook.**

## Inputs

| File | Description |
|------|-------------|
| `og_dictionaries/Public_data_dictionary_2024.xlsx` | Public data dictionary. The script stops if it is missing. |
| `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx` | Source of the four `00c` columns, where it exists and matches the base workbook |
| `dictionaries/dictionary_<country>_<dataset>.xlsx` | Source otherwise. The script stops if there is no base workbook. |

## Outputs

| File | Description |
|------|-------------|
| `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx` | The base workbook with the `00c` columns carried over and the eight columns. An existing file is replaced. |

The columns are described in `dictionaries/README.md`. For each workbook the console shows the number of variables matched, with the prefix `[00e]`.

## Configuration

Set at the top of the script.

| Setting | Default | Effect |
|---------|---------|--------|
| `OVERWRITE_IN_PLACE` | `FALSE` | `FALSE` reads the base workbooks and writes the `_enriched.xlsx` copies. `TRUE` reads the base workbooks and writes the columns into them. |
| `DICT_DIR` | `dictionaries` | Folder of the dictionary workbooks. |
| `PUBLIC_DICT` | `og_dictionaries/Public_data_dictionary_2024.xlsx` | Path of the public data dictionary. |
| `PUBLIC_SHEETS` | seven sheet names | Sheets of the public data dictionary that are read. |

## How to run it

```r
source("00_build_dictionary/00e_enrich_from_public_dictionary.r")
```

or `Rscript 00_build_dictionary/00e_enrich_from_public_dictionary.r`. Packages used: `readxl`, `openxlsx`.
