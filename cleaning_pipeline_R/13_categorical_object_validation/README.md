# Module 13: Categorical and Object Validation

## Purpose
Validates categorical (factor) and free-text (object/character) columns through five sequential cleaning steps: value standardisation, disallowed value removal, missing string normalisation. Produces the `df_categorical` sub-frame.

---

## When It Runs
After Module 10 (duplicate row removal). Third of four parallel validation streams (Modules 11-14).

---

## Logic

For each categorical column in `cfg$cat` and object column in `cfg$obj`:

**Step 1 -- Value standardisation (`cfg$value_mappings`)**
If an alias -> canonical mapping is defined for the column's base name in `cfg$value_mappings`, all alias values are replaced with their canonical form. For example, if `"HCH"` and `"SMCH"` both mean the same hospital, they can be unified here. The `value_mappings` list is configured in `cfg` (defined in Module 00).

**Step 2 -- Disallowed value removal (`cfg$values_to_delete`)**
Any value explicitly listed in `cfg$values_to_delete` for the column's base name is set to `NA`. This handles known data artefacts such as timestamps appearing in categorical fields.

**Step 3 -- Missing string normalisation**
Literal string representations of missing data -- `"nan"`, `"None"`, `"NA"`, `"N/A"`, `"null"`, `""`, and their case variants -- are replaced with real `NA`.

**Step 4 -- Deduplication**
`dplyr::distinct()` on (`uid`, `facility`) is applied to the categorical sub-frame before it is returned.

The sub-frame includes the three primary key columns (`facility`, `uid`, `uniquekey`) plus all categorical and object feature columns.

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Stage-1 data frame from Module 10 |
| `cfg$cat` | Character vector of categorical column names |
| `cfg$obj` | Character vector of object/free-text column names |
| `cfg$value_mappings` | Named list: `column_base -> list(canonical -> c("alias1", "alias2"))` |
| `cfg$values_to_delete` | Named list: `column_base -> c("bad_value_1", "bad_value_2")` |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df_categorical` | Validated categorical/object sub-frame: primary keys + cat/obj columns |
| `reports/13_categorical_validation_report.txt` | Count of standardisations, deletions, and missing-string normalisations (optional) |

---

## Key Function

**`validate_categorical(df, cfg, report_filepath = NULL)`**

- Selects primary key columns + all categorical and object feature columns present in `df`.
- Applies value standardisation, disallowed value removal, and missing string normalisation per column.
- Deduplicates and returns the validated sub-frame as `df_categorical`.

---

## Notes

- The `base_name()` helper strips `.value` / `.valuedischarge` before `value_mappings` and `values_to_delete` lookups.
- `cfg$value_mappings` and `cfg$values_to_delete` are optional -- if left as empty lists (`list()`) in setup, those steps are simply skipped.
- Values not recognised by the dictionary but not in the delete list are left in place. The dictionary validation in Module 04 has already corrected the most common label contamination issues.
