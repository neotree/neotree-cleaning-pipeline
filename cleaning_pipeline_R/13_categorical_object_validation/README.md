# Module 13: Categorical and Object Validation

## Purpose

Cleans the categorical and free-text columns: applies configured value replacements and deletions, removes values that look like column headers or datetimes, and turns text that stands for "missing" into `NA`. Produces the categorical sub-frame used in the final merge.

## When it runs

After Module 10. Modules 11 to 14 each read the same data frame from Module 10 and each produce one sub-frame for Module 15.

## What it does

The sub-frame holds the key columns `facility`, `uid` and `uniquekey` and the columns of `cfg$cat` and `cfg$obj` present in `df`. The steps run in this order.

| Step | Applies to | Rule |
|------|-----------|------|
| 1. Value replacement | categorical and object columns with an entry in `cfg$value_mappings` | Each listed alias is replaced by its canonical value. The column is matched by its name without the `.value` or `.valuedischarge` suffix. |
| 2. Value deletion | columns named in `cfg$values_to_delete`, as written or with `.value` added | Each listed value becomes `NA`. |
| 3. Headers and datetimes | categorical columns | A value becomes `NA` if it is three or more capitalised words (optionally ending in `?`), starts like an ISO datetime (`YYYY-MM-DD` followed by a time), or starts with a full English month name. |
| 4. Missing-value text | categorical and object columns | A value that, once trimmed, equals one of `nan`, `NaN`, `none`, `None`, `na`, `NA`, `n/a`, `N/A`, `null`, `NULL` or the empty string becomes `NA`. |
| 5. Factors | categorical columns | Each column is converted to a factor. |
| 6. Duplicates | whole sub-frame | Rows identical in every column are reduced to one. |

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 10 |
| `cfg$cat` | Names of the categorical columns |
| `cfg$obj` | Names of the object (free-text) columns |
| `cfg$value_mappings`, `cfg$values_to_delete` | See *Configuration* |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_categorical` | Key columns and validated categorical and object columns |
| `reports/13_categorical_validation_report.txt` | Number of values replaced, number removed in steps 2 and 3, number of missing-value texts set to `NA`, duplicate rows removed, final row count |

## Function

`validate_categorical(df, cfg, report_filepath = NULL)` returns the categorical sub-frame.

## Configuration

Both settings are entries of the `cfg` list built in `00_setup.r`. Both are empty lists by default, in which case steps 1 and 2 change nothing.

| Setting | Format | Effect |
|---------|--------|--------|
| `cfg$value_mappings` | `list(column = list(canonical = c("alias1", "alias2")))` | Step 1 replaces each alias with the canonical value in that column. |
| `cfg$values_to_delete` | `list(column = c("value1", "value2"))` | Step 2 sets each listed value to `NA` in that column. |
