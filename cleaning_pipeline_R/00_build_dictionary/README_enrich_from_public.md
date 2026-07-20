# 00e — Enrich dictionaries from the 2024 Public Data Dictionary

`00e_enrich_from_public_dictionary.r` annotates each generated dictionary with
human-readable documentation drawn from
`og_dictionaries/Public_data_dictionary_2024.xlsx` (a curated, non-web-editor
reference maintained by the Neotree team).

## What it adds

Eight columns are appended to the **Variables** sheet of every dictionary:

| Column | Source (public dictionary) | Meaning |
|---|---|---|
| `public_meaning` | Variable meaning | Plain-language description of what the variable captures |
| `public_data_type` | Data type | Documented type (reference / cross-check for `r_type`) |
| `public_dependency` | Dependency | Skip-logic described in words (complements `00c`'s `skip_condition`) |
| `public_range` | Range | Documented plausible range (reference only) |
| `old_variable_name` | Old variable name | Previous name, if the variable was renamed across form versions |
| `timeline_of_change` | Timeline of change | When/why the name or definition changed |
| `public_reference` | Reference | Source citation from the public dictionary |
| `public_dict_matched` | — | `TRUE` when a public-dictionary entry was found for this variable |

## What it does NOT do

This pass is **documentation only**. It never touches the `ValueMaps` sheet,
canonical codes, the ranges the pipeline actually uses, PII flags, or any
cleaning behaviour. The canonical dictionaries continue to build solely from the
downloaded web-editor data keys (`00_build_dictionary.r`) plus the curated
`VALUEMAP_PATCHES`; `00e` only *annotates* them so the workbooks are more usable
for analysts.

## Where in the build order

```
1. 00_build_dictionary.r                      -> dictionary_*.xlsx (canonical)
2. 00c_enrich_dictionary_from_scripts.r       -> + display_label / optional /
                                                   skip_condition / valuemap_check
3. 00e_enrich_from_public_dictionary.r        -> + the eight columns above
```

With `OVERWRITE_IN_PLACE <- FALSE` (default) the enriched output is written to
`dictionary_*_enriched.xlsx`. `00e` reads the `00c` enriched copy when it exists,
so the `00c` columns are preserved in the same workbook.

## Matching

Each dictionary variable (`question_key`, falling back to
`harmonised_variable_name`) is matched case-insensitively against **every**
public-dictionary sheet, by both current variable name and old variable name. A
global index is used because a variable's documented meaning is stable across the
Admission / Discharge / PHC / Maternal / NeoLab sheets. The first non-empty match
wins; `public_dict_matched = FALSE` marks variables absent from the 2024 public
dictionary (expected for lab-specific NeoLab fields and any form fields added
after 2024).

## When to re-run

Re-run after rebuilding the dictionaries, or whenever a newer public data
dictionary is dropped into `og_dictionaries/`. Safe to re-run: it only refreshes
these eight columns.
