# Module 04: Dictionary-Based Value Cleaning

## Purpose

Rewrites categorical values as the canonical codes defined in the data dictionary, wherever a value can be matched to exactly one code. Values that cannot be matched are left as they are.

## When it runs

After Module 03. All columns are character at this point.

## What it does

Four steps run in this order. A column is matched to its dictionary entry by its name with the `.value` or `.valuedischarge` suffix removed.

### 1. Multi-select encoding

Applies to columns with a dictionary entry, and to `resus` and `delivinter`. Only values that start with `[` are examined.

| Value | Result |
|-------|--------|
| Quoted list, `["A","B"]` or `["A", "B"]` | `{A,B}` |
| Unquoted list, `[A, B]`, where every item is a raw or canonical code of the column (in any case) | `{A,B}` |
| Unquoted list with an item that is not a code of the column, or in a column with no dictionary entry | unchanged |
| List with an empty item, or any other value starting with `[` | unchanged |

Items are written as they appear in the value, without surrounding spaces.

### 2. Canonical codes

Applies to columns with a dictionary entry. The targets are the entry's canonical codes; if it has none, its raw codes are used instead. Each distinct value of a column is resolved by the first rule that fits:

1. It is a canonical code, exactly as written: kept.
2. It matches a canonical code when case is ignored: replaced by the canonical spelling.
3. It matches a raw code when case is ignored: replaced by that code's canonical code.
4. It matches an option label when case is ignored: replaced by that label's canonical code.
5. It is `true`, `yes`, `t` or `y`, or `false`, `no`, `f` or `n` (in any case), and every canonical code of the variable is one of `Y`, `N`, `U`: replaced by the variable's yes or no code.
6. Otherwise: left unchanged and counted as unresolved.

Case-insensitive matching is used only where it is unambiguous. If two codes or labels of a variable differ only by case and lead to different canonical codes, that spelling is not matched without regard to case, and only rule 1 applies to it.

A multi-select value, `{A,B}`, is split on commas and each item is resolved by rules 1 to 5. If every item resolves, the value is rewritten with the canonical codes, as `{A,B}` without spaces. If any item does not resolve, the whole value is left unchanged and counted as unresolved.

Option labels whose dictionary code is empty are not used for matching.

### 3. `modedelivery`

In `modedelivery` and `modedelivery.value`, a value that is exactly one of the text codes named in `MODEDELIVERY_MAP` is replaced by the numeric code given there. Other values are unchanged.

### 4. Thompson score columns

In every column whose name starts with `thomp` (in any case), a value made of a number followed by `=` and a label, such as `2 = Label`, is replaced by the number alone.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 03 |
| `cfg$value_map_list` | List with one entry per dictionary variable: `allowed_codes` (raw codes), `canonical_codes`, `label_to_code` (option label to canonical code) and `code_to_canonical` (raw code to canonical code). Built in `00_setup.r` from the dictionary value maps. |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with values rewritten by the four steps |
| `reports/04_dictionary_cleaning_report.txt` | Results of step 2 only: number of columns checked; totals of replacements, deletions and unresolved values; and, for each column, every replaced value with its replacement and every unresolved value, each with its number of records. |

Steps 1, 3 and 4 write their counts to the pipeline log.

## Functions

| Function | Returns |
|----------|---------|
| `normalise_multiselect_encoding(df, value_map_list)` | Data frame after step 1 |
| `clean_values_using_dict(df, value_map_list, report_filepath = NULL)` | Data frame after step 2 |
| `harmonise_modedelivery(df)` | Data frame after step 3 |
| `strip_thompson_labels(df)` | Data frame after step 4 |
