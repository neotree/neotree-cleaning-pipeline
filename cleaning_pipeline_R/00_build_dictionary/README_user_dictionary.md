# 00d_build_user_dictionary.r -- User Dictionary Generator

## Purpose

Generates clean, researcher-facing data dictionaries intended to accompany
any data release or research collaboration.  The outputs describe every
variable a researcher will encounter in the cleaned Neotree dataset,
including labels, data types, valid codes and ranges, NA sentinel codes,
and cross-dataset availability.

This script is **independent of the cleaning pipeline** and can be re-run
at any time.  It does not affect how the pipeline processes data.

---

## How to run

```r
# From the pipeline root directory:
source("00_build_dictionary/00d_build_user_dictionary.r")
# or from the command line:
Rscript 00_build_dictionary/00d_build_user_dictionary.r
```

---

## Inputs (in priority order for label resolution)

| Source | Contents | Priority |
|--------|----------|----------|
| `neotree_scripts/` | Field labels, section groupings, field ordering, skip conditions, coded options from script JSONs | Highest |
| `dictionaries/` | Data types, plausible ranges, harmonised column names, PII / use_in_analysis flags, curated ValueMaps | Second |

> **Note (2026-06).** This script previously also read hand-maintained workbooks
> from `og_dictionaries/` as a second label source. That dependency was removed:
> the chain now builds solely from the web-editor downloads (data keys + script
> JSON) plus `dictionaries/`. `og_dictionaries/` retains only
> `Public_data_dictionary_2024.xlsx`, which is read by `00e`, not by this script.

If `USE_ENRICHED_DICT = TRUE` (default), the script prefers
`*_enriched.xlsx` files produced by `00c_enrich_dictionary_from_scripts.r`
when they exist.

---

## Outputs

All outputs are written to `user_dictionaries/`:

| File | Description |
|------|-------------|
| `neotree_user_dict_zim.xlsx` | Excel workbook for Zimbabwe |
| `neotree_user_dict_mwi.xlsx` | Excel workbook for Malawi |

Each workbook contains:

| Sheet | Contents |
|-------|----------|
| **About** | Study metadata, generated date, and a reference to the NA Codes sheet |
| **Admissions / Discharges / ...** | One sheet per dataset — dictionary rows merged with section headers, blue Calibri styling |
| **Master** | All unique variables across all datasets in screen-ordering |
| **NA Codes** | Two-section legend: (1) numeric sentinel codes −6 to −9 with Priority column; (2) raw string codes entered by data collectors (NK, UNK, NR, REFUSED, NE, NOT_DONE, PENDING, UNKNOWN, OTHER). Includes a footer note on when each type appears and how to filter |

Each Excel sheet contains:

| Column | Source | Notes |
|--------|--------|-------|
| Description | `display_label` -> `json_label` -> pipeline `variable_label` -> `question_key` | First non-empty source wins |
| Variable Name | `harmonised_variable_name` -> `question_key` | |
| Type | Pipeline `r_type` | Numeric / Boolean / Categorical / Text / Date-time |
| Values / Codes | Pipeline ValueMaps or JSON options (categorical); `suggested_plausible_min/max` (numeric) | Ranges always from the pipeline dictionary |
| NA Codes | Derived from `pii_tier`, `skip_condition`, `r_type` | See the dedicated **NA Codes** sheet (two sections: numeric sentinel codes −6 to −9 with priority hierarchy; raw string codes NK / UNK / NR / etc. entered by data collectors) |
| Available also in | Cross-dataset index | Other datasets in the same country containing this variable |

---

## Variable exclusions

| Condition | Effect |
|-----------|--------|
| `pii_tier == "1"` | Excluded entirely -- column stripped from the cleaned dataset |
| `use_in_analysis == FALSE` | Excluded -- not part of the pipeline output |

---

## User configuration

Constants at the top of the script:

| Constant | Default | Effect |
|----------|---------|--------|
| `NEOTREE_SCRIPTS_BASE` | `"neotree_scripts"` | Path to JSON script files |
| `DICT_DIR` | `"dictionaries"` | Path to pipeline cleaning dictionaries |
| `OUTPUT_DIR` | `"user_dictionaries"` | Where to write all output files (created if absent) |
| `USE_ENRICHED_DICT` | `TRUE` | Prefer `*_enriched.xlsx` from `00c` when available |

---

## Script-to-dictionary matching (FACILITY_SCRIPT_MAP)

This script contains an inline copy of `FACILITY_SCRIPT_MAP` -- the same
mapping used by `00c_enrich_dictionary_from_scripts.r` and
`16_na_reason_coding/helpers/03_facility_script_map.r`.

> **Important:** If scripts are replaced or new hospitals are added,
> update **all three** copies of the map.

---

## ZIM infections dataset

`zim_infections` is a server-side derived file — it has no dedicated Neotree script in the web editor. All rows carry a `Transformed = TRUE` flag and the `Scriptid` field is empty for virtually all records, confirming it is generated server-side rather than collected directly via the Neotree app.

The dictionary for this dataset is built using the NeoLab script as the closest available approximation (the same fallback used for `00c` enrichment). As a result, most variables in the infections file do not appear in any script JSON and will have blank `Description` entries in the user dictionary. This is expected — not a data quality issue.

The `Infections` sheet in `neotree_user_dict_zim.xlsx` reflects this limitation: variable labels may be missing for fields that are unique to the server-side transformation.

---

## MWI maternal datasets

Malawi has three source maternal data files (plus one server-side combined file). Their histories differ, which affects what appears in the user dictionary for each sheet:

| Dataset | Source | Date range | `neotreeoutcome` field? | Status |
|---|---|---|---|---|
| `maternal_outcomes` | Original Neotree maternal script (KCH) | Nov 2021 – Jan 2022 | No | **Retired** |
| `dhis2_maternal_outcomes` | DHIS2 Maternal Outcomes script (KCH) | Jun 2024 – present | Yes | **Currently active** |
| `maternity_completeness` | Paper records, entered manually — no Neotree script | Nov 2021 – May 2025 | No | Paper backfill only |
| `combined_maternity_outcomes` | Server-side join of all three above | — | Yes (inherited from DHIS2) | Derived file |

The **DHIS2 Maternal Outcomes** script is the form currently running on the Neotree app in Malawi. The original `Maternal_Outcomes` script was retired in January 2022. `Maternity_Completeness` was collected manually from paper records and has no dedicated Neotree script — its dictionary is approximated from the maternal outcomes scripts.

This also explains why the `combined_maternity_outcomes` sheet is the most complete MWI maternal dictionary: it draws on the broadest set of scripts (`"Maternal|DHIS2 Mat|Maternity"` filter) and includes the `neotreeoutcome` field (Birth Outcome: LB/SBF/SBM/UNK) from the DHIS2 script.

---

## Adding a new dataset

To add a new dataset to the user dictionary:

1. Add an entry to `DATASET_CONFIGS` for the relevant country block:
   ```r
   list(key = "new_dataset", label = "New Dataset")
   ```
2. If the dataset uses a new script, add it to `FACILITY_SCRIPT_MAP`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Dataset sheet is missing from the Excel output | `DATASET_CONFIGS` entry missing, or no matching script JSON found | Add entry to `DATASET_CONFIGS` and confirm the script JSON is in `neotree_scripts/` |
| All variable descriptions are blank | JSON scripts not matched | Check the `NEOTREE_SCRIPTS_BASE` path |
| "Script index: 0 scripts indexed" | `neotree_scripts/` directory is empty or missing | Download script JSONs from the Neotree web editor |
