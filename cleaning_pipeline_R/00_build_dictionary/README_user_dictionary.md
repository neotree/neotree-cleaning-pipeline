# `00d_build_user_dictionary.r`

## Purpose

Builds the user dictionary: one Excel workbook per country that lists, for each dataset, the variables of the cleaned data in the order of the Neotree form, with their description, type, values and missing-value codes. It is a reference for people who use the cleaned data. The cleaning pipeline does not read it.

## When to run it

After `00_build_dictionary.r`, `00c_enrich_dictionary_from_scripts.r` and `00e_enrich_from_public_dictionary.r`. Run it again when the dictionaries are rebuilt or when the files in `neotree_scripts/` change.

## What it does

For each country (`ZIM`, `MWI`) and each dataset in `DATASET_CONFIGS`:

1. **Chooses the scripts of the dataset.** These are the entries of `FACILITY_SCRIPT_MAP` for the country and dataset; `infections` uses the entry for `neolab`. For the two PHC datasets, if the map has no entry, the scripts of the country whose title contains one of the keywords in `PHC_ADMISSION_KW` or `PHC_DISCHARGE_KW` are used. Identifiers with no file in `neotree_scripts/` are dropped. A dataset with no script gets no sheet.
2. **Reads the fields of those scripts** in screen and field order, with keys in lower case, and keeps one row per key:

   | Item | Taken from |
   |------|------------|
   | Section | The most frequent screen title of the key |
   | Position | The lowest screen number with that title, then the lowest field number |
   | Label | The first non-empty label |
   | Skip condition | The first non-empty condition (screen and field conditions joined with `AND` when both exist and differ) |
   | Options | The longest option list |

3. **Reads the dictionary workbook of the dataset**: the `_enriched.xlsx` copy if it exists and `USE_ENRICHED_DICT` is `TRUE`, otherwise the base workbook. Variables are matched on `question_key`.
4. **Leaves out** every variable whose `pii_tier` is `1` or whose `use_in_analysis` is `FALSE`. A field that is in the scripts but not in the dictionary is kept, with an empty type.
5. **Adds the derived variables.** Each key in `DERIVED_KEYS` that is in the dictionary of the dataset, and not left out by step 4, is added in the section `Derived variables (computed by the cleaning pipeline)`.
6. **Writes one sheet per dataset**, then a `Master` sheet.

### Columns of a dataset sheet

| Column | Content |
|--------|---------|
| `Description` | `display_label` of the dictionary; if empty, the label in the scripts; if empty, `variable_label`; if empty, the key. For derived variables, `variable_label`. |
| `Variable Name` | `harmonised_variable_name`; if empty, the key. |
| `Type` | `Numeric`, `Boolean`, `Categorical`, `Text` or `Date/time`, from `r_type`. |
| `Values / Codes` | See below. |
| `NA Codes` | The missing-value codes that can occur for the variable. See below. |
| `Available also in` | The other datasets of the same country that contain the variable. |

`Values / Codes` (for a staff field, see `staff_fields.r`, it reads `Not listed (staff identifier)`):

| Type | Content |
|------|---------|
| Numeric | `Range: a to b`, `Range: >= a` or `Range: <= b` from the limits in the dictionary; `Numeric value` if there are none. |
| Date/time | `Date / time value` |
| Text | `Free text` |
| Boolean, Categorical, or no type | One line `code = label` per option, from the `ValueMaps` sheet in `option_order`, using `raw_code` and the first label of each code. If the variable has no row there, the options in the scripts. If there are none, `true / false` for a Boolean and empty otherwise. |
| Derived variables | Empty |

`NA Codes`:

| Code | Listed when |
|------|-------------|
| `-9` | Always |
| `-8` | The type is Numeric, Boolean, Categorical or Date/time |
| `-7` | The variable has a skip condition (`skip_condition` of the dictionary, or the condition in the scripts) |
| `-6` | The type is Text and `pii_tier` is set and is not `1` |

### Layout of a dataset sheet

The first row is the header and is frozen. Variables are grouped under section rows:

1. `Administrative / System`: variables with a `record_id_role` or a `linkage_role` in the dictionary.
2. One section per screen title, in form order.
3. `Derived variables (computed by the cleaning pipeline)`.
4. `Other`, for fields whose screen has no title.

### Sheets of the workbook

| Sheet | Content |
|-------|---------|
| `About` | Title, date of generation and a short description of the workbook. |
| `NA Codes` | The four numeric codes `-6` to `-9` with their meaning and priority, a list of text codes entered by data collectors in the raw data, and a note on how the two kinds are used. |
| One per dataset | As above. The sheet is named with the `sheet` value of the dataset in `DATASET_CONFIGS` if there is one, otherwise with its `label`. |
| `Master` | Every variable name once, taken from the first dataset sheet in which it occurs, in the same layout. |

## Inputs

| File | Description |
|------|-------------|
| `neotree_scripts/<country>-scripts/*.json` | Neotree script files |
| `dictionaries/dictionary_<country>_<dataset>_enriched.xlsx` | Dictionary workbook, where it exists |
| `dictionaries/dictionary_<country>_<dataset>.xlsx` | Dictionary workbook otherwise |

## Outputs

| File | Description |
|------|-------------|
| `user_dictionaries/neotree_user_dict_zim.xlsx` | User dictionary for Zimbabwe |
| `user_dictionaries/neotree_user_dict_mwi.xlsx` | User dictionary for Malawi |

The folder is created if it does not exist. Existing files are replaced. For each dataset the console shows the number of rows, sections and scripts.

## Configuration

Set in the script.

| Setting | Default | Effect |
|---------|---------|--------|
| `NEOTREE_SCRIPTS_BASE` | `neotree_scripts` | Folder of the script files. Each subfolder named `<country>-scripts` is read. |
| `DICT_DIR` | `dictionaries` | Folder of the dictionary workbooks. |
| `OUTPUT_DIR` | `user_dictionaries` | Folder of the output workbooks. |
| `USE_ENRICHED_DICT` | `TRUE` | Read the `_enriched.xlsx` copies when they exist. |
| `DERIVED_KEYS` | list of keys | Derived variables to add. A key is added only if it is also in the dictionary, where `DERIVED_VARIABLES` of `00_build_dictionary.r` puts it. |
| `DATASET_CONFIGS` | per country | Datasets to include, in sheet order, with `key`, `label` and optionally `sheet`. |
| `FACILITY_SCRIPT_MAP` | per country and dataset | Script identifiers. |

To add a dataset, add it to `DATASET_CONFIGS` and to `FACILITY_SCRIPT_MAP`.

## How to run it

```r
source("00_build_dictionary/00d_build_user_dictionary.r")
```

or `Rscript 00_build_dictionary/00d_build_user_dictionary.r`. Packages used: `openxlsx`, `jsonlite`.
