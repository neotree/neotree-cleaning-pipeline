# Module 05: Forward Fill Placeholder Values

## Purpose
Recovers known categorical placeholder strings that were recorded in the `.label` column instead of the `.value` column. For each `.value`/`.label` pair, if `.value` is empty but `.label` contains a recognised placeholder, the placeholder is copied across into `.value`.

---

## When It Runs
After Module 04 (dictionary value cleaning). Placeholder recovery must run before numeric/datetime fill (Module 06), as those steps expect categorical placeholders to already be in the `.value` columns.

---

## Logic

For each paired `.value` / `.label` column (and `.valuedischarge` / `.labeldischarge`):
- The module checks rows where `.value` is `NA` and `.label` is not `NA`.
- If the `.label` content matches any entry in the placeholder list (exact match), the `.label` value is copied into `.value`.
- `.label` columns are **retained** after this step -- they are dropped by Module 06.

### Recognised placeholder values

| Category | Values |
|----------|--------|
| None/Normal | `"None"`, `"Normal"`, `"Norm"` (and lowercase/uppercase variants) |
| Boolean (text) | `"True"`, `"False"`, `"TRUE"`, `"FALSE"` |
| Boolean (yes/no) | `"Yes"`, `"No"`, `"YES"`, `"NO"`, `"Y"`, `"N"` |

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 04 with paired `.value` / `.label` column structures |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with placeholder values recovered into `.value` columns; `.label` columns retained |
| `reports/05_forward_fill_placeholder_report.txt` | Per-column count of values recovered (optional) |

---

## Key Function

**`forward_fill_placeholders(df, placeholders = PLACEHOLDER_VALUES, report_filepath = NULL)`**

- Iterates over all `.value` / `.label` column pairs (and `.valuedischarge` / `.labeldischarge`).
- Fills `.value` from `.label` where `.label` is a recognised placeholder and `.value` is `NA`.
- Returns the updated data frame.

---

## Notes

- This step mirrors the Jupyter pipeline's `fill_missing_with_label_value()` function, which handles `"none"`, `"normal"`, `"norm"`. The R implementation extends this to also cover boolean-type placeholders (`"Yes"`, `"No"`, `"True"`, `"False"`, etc.) for additional completeness.
- Placeholder matching is exact (not case-insensitive) to avoid accidental matches, but the list covers all common case variants explicitly.
- Labels that are not in the placeholder list are handled by Module 06 (numeric/datetime fill).
