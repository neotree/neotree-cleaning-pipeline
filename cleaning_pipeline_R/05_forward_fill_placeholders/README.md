# Module 05: Forward Fill Placeholder Values and Label-to-Value Rules

## Purpose

Recovers answers that are stored only in a label column. Configured fields are read from their label by a field-specific parser; a set of fixed placeholder words is copied from a label column into its paired value column where the value is missing.

## When it runs

After Module 04.

## What it does

### 1. Label-to-value rules

`cfg$label_value_rules` (from `LABEL_VALUE_RULES` in `00_setup/00_setup.r`) lists, for the current country and dataset, fields and the parser that reads each one. For each field the parser reads the `.value` and `.label` columns and fills `.value` where it holds no valid value and the label gives one. A valid `.value` is never changed. The pairs handled here are skipped by step 2.

The parser `anc_visit_count` (antenatal care visits, Malawi `admissions`) works as follows.

| `.value` | `.label` | Result in `.value` | `<field>_source` |
|----------|----------|--------------------|------------------|
| whole number, 0 or more | any | unchanged | `raw_numeric_value` |
| empty or not a whole number | `N ANC visit` or `N ANC visits` (any case, extra spaces allowed), or a plain whole number | `N` | `raw_exact_label` |
| empty or not a whole number | `None` | `0` | `raw_exact_label` |
| empty or not a whole number | `More than 4 ANC visits`, `More than 8 ANC visits` | empty | `raw_range_label` |
| empty or not a whole number | anything else, such as `Not sure`, `ANC visits` with no number, or question text | empty | `unresolved` |

A `.value` that is not a whole number of 0 or more and has no label count is set to `NA`, and the number of such rows is reported. When a valid `.value` and a label count disagree, the `.value` is kept and the number of such rows is reported and logged as a warning. The parser adds the bare column `<field>_source` to the data frame. Module 15 derives `antenatalcare_category` from the final count and this column.

The rule is configured for Malawi `admissions` only.

### 2. Placeholder words

Columns are paired by name: each `.value` column with the `.label` column of the same variable, and each `.valuedischarge` column with its `.labeldischarge` column. A value column with no label column is skipped.

In each pair, a row is filled when the value is `NA` and the label is exactly one of the placeholders below. The label text is copied into the value column as it is.

| Group | Placeholders |
|-------|--------------|
| None / normal | `None`, `Normal`, `Norm`, `none`, `normal`, `norm`, `NONE`, `NORMAL`, `NORM` |
| True / false | `True`, `False`, `TRUE`, `FALSE` |
| Yes / no | `Yes`, `No`, `YES`, `NO`, `Y`, `N` |

Matching is case-sensitive. Labels in any other form are not copied. The label columns are kept.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 04 |
| `cfg$label_value_rules` | Label-to-value rules for the current country and dataset, or `NULL` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with values read from labels and placeholders copied into the value columns, plus `<field>_source` for each rule |
| `reports/05_forward_fill_placeholder_report.txt` | Number of placeholders checked, total number of values filled and, for each pair with a fill, the number of values filled. For each label-to-value rule, the number of rows in each class: valid value, count read from the label, `None` read as 0, `More than N` label, and the unresolved classes (`Not sure`, no number, question text, no answer, other), the number of rows where the value and the label disagree, and the number of invalid values set to missing. |

## Function

`apply_label_value_rules(df, rules)` returns a list with the updated data frame, the value columns handled and the report lines. `forward_fill_placeholders(df, placeholders = PLACEHOLDER_VALUES, report_filepath = NULL, skip_value_cols = character(0), rule_report = character(0))` returns the updated data frame. `placeholders` is the character vector of labels that may be copied; `skip_value_cols` are the value columns handled by a rule.
