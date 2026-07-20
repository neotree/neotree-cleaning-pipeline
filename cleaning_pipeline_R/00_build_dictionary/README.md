# 00_build_dictionary -- Neotree v8 Data Dictionary Build System

This folder contains the scripts that **create, enrich, validate, and
document the data dictionaries** that power the entire Neotree cleaning
pipeline.  Every downstream module (`00_setup` -> `15_final_merge_output`)
reads from these dictionaries; they are the authoritative source of truth for
variable types, value maps, plausible ranges, harmonised names, and PII
classification.

**Run these scripts before the cleaning pipeline, and re-run them whenever
their inputs change.**  The cleaning pipeline itself (`run_pipeline.r`) does
**not** call any of them.

---

## Contents

| File | Language | Purpose | Full documentation |
|------|----------|---------|-------------------|
| `00_build_dictionary_v8.r` | R | Builds all `dictionary_*.xlsx` workbooks from the web-editor data-key exports | [README_build_dictionary_v8.md](README_build_dictionary_v8.md) |
| `00c_enrich_dictionary_from_scripts.r` | R | Enriches each workbook with field-level metadata from Neotree script JSONs | [README_enrich_from_scripts.md](README_enrich_from_scripts.md) |
| `00d_build_user_dictionary.r` | R | Generates researcher-facing dictionaries (Excel + HTML + PDF) | [README_user_dictionary.md](README_user_dictionary.md) |
| `validate_dictionaries.r` | R | Validates every dictionary against the pipeline's requirements | Section 7 below |
| `user_ranges.xlsx` | Excel | Researcher-defined plausible ranges that survive dictionary rebuilds | Section below |

---

## Key files to keep updated

Two pairs of files drive the entire dictionary build — one pair per country. These are downloaded directly from the Neotree web editor and must be replaced whenever a new data-key export is available:

```
neotree_data_keys/downloaded/
├── neotree_data_keys_zimbabwe/
│   ├── data-keys-metadata.json   ← field definitions (type, label, options, confidential flag)
│   └── data-keys-usage.xlsx      ← which scripts use each key, and script titles
└── neotree_data_keys_malawi/
    ├── data-keys-metadata.json
    └── data-keys-usage.xlsx
```

**`data-keys-metadata.json`** is the most critical file. It is the source of every field's data type, coded option list, and confidential flag. Whenever Neotree adds new questions, changes option codes, or marks a field confidential, this file changes.

**`data-keys-usage.xlsx`** controls which fields appear in which dataset dictionary. The build script filters by script title (via `DATASET_FILTERS` regex patterns) using the `ScriptTitle` column of this file. Whenever new scripts are published or renamed in the web editor, this file changes.

After replacing either file with a new download, re-run `00_build_dictionary_v8.r` to rebuild all dictionaries. The enrichment step (`00c`) and Module 16 skip logic also use the Neotree script JSONs in `neotree_scripts/`, but those are a secondary concern and do not affect the core dictionary build.

---

## Quick-start

```bash
# Step 1 -- build all dictionaries (run from the pipeline root)
Rscript 00_build_dictionary/00_build_dictionary_v8.r

# Step 2 -- enrich with script metadata
Rscript 00_build_dictionary/00c_enrich_dictionary_from_scripts.r

# Step 3 -- validate
Rscript 00_build_dictionary/validate_dictionaries.r

# Step 4 -- generate researcher user dictionaries (optional)
Rscript 00_build_dictionary/00d_build_user_dictionary.r
```

All scripts must be run from the **pipeline root directory** (the folder
containing `run_pipeline.r`, `input/`, `output/`, etc.).

Steps 1-3 produce the machine-readable dictionaries consumed by the cleaning
pipeline.  Step 4 produces human-readable dictionaries for researchers; it is
independent of the pipeline and can be re-run at any time.

### When to re-run each step

| Event | Step 1 | Step 2 | Step 3 | Step 4 |
|-------|--------|--------|--------|--------|
| Initial setup (first time) | [OK] Run | [OK] Run | [OK] Run | [OK] Run |
| New data-key export (`data-keys-metadata.json` updated) | [OK] Re-run | [OK] Re-run | [OK] Re-run | [OK] Re-run |
| New script JSONs downloaded to `neotree_scripts/` | -- | [OK] Re-run | [OK] Re-run | [OK] Re-run |
| Existing script JSON updated (script republished) | -- | [OK] Re-run | [OK] Re-run | [OK] Re-run |
| No changes to inputs | -- | -- | -- | -- |

> `og_dictionaries` is no longer an input to any step (removed from `00d` on 2026-06-12).

---

## 1. `00_build_dictionary_v8.r` -- the build script

### What it does

1. Loads the official Neotree web-editor data-key exports for Zimbabwe and Malawi (JSON + XLSX) from `neotree_data_keys/downloaded/`.
2. Filters to the relevant scripts for each country x dataset combination.
3. Constructs a structured Excel workbook for each combination with four sheets: **Variables**, **ValueMaps**, **PII_Patterns**, **ReviewNeeded**.
4. Applies manual plausible ranges, PII tier classification, and harmonised variable names.
5. Writes one workbook per combination to `dictionaries/` as `dictionary_{country}_{dataset}.xlsx`.

> **Source of truth (confirmed 2026-06-12):** the build reads *only* the downloaded
> web-editor data keys (`data-keys-metadata.json` + `data-keys-usage.xlsx`). It does
> **not** read `og_dictionaries/` (the legacy hand-maintained workbooks). Curated
> corrections live solely in the `VALUEMAP_PATCHES` list inside this script.

> **Multi-version ValueMaps union (added 2026-06-12).** A variable's options are taken
> from the *latest* version of each data key (most recent `publishDate`). But the
> cleaned data spans years and several Neotree form versions, so option codes that were
> valid only in *earlier* versions (e.g. `fontanelle = Flat`, the `resus` intervention
> codes, `ttv` dose codes, `palate` labels) would otherwise be missing from the
> ValueMaps and wrongly flagged as non-canonical by Module 04. The build now **appends
> the union of option codes/labels across every non-deleted version** of each data key
> (the `value_maps_allver` / `legacy_rows` block). This is decision-free: it only adds
> codes the web editor itself defined as valid in some version. Legacy rows are appended
> after the current-version rows (preserving display order) with `canonical_code =
> raw_code`; `VALUEMAP_PATCHES` still runs afterwards and can override them.

### Inputs

Located in `neotree_data_keys/downloaded/{country_folder}/`:

| File | Description |
|---|---|
| `data-keys-metadata.json` | All field definitions: key, label, dataType, options, confidential flag |
| `data-keys-usage.xlsx` | Which scripts use each key, and the script titles |

> **Note:** Column names in `data-keys-usage.xlsx` are normalised by stripping all non-alphanumeric characters and lowercasing (`DataKeyUniqueKey` -> `datakeyuniquekey`). This is done explicitly rather than via `janitor::clean_names()` to avoid version-dependent behaviour differences.

### Outputs

One Excel workbook per country x dataset combination, written to `dictionaries/`:

| Combination | Output file |
|---|---|
| ZIM x admissions | `dictionary_zim_admissions.xlsx` |
| ZIM x discharges | `dictionary_zim_discharges.xlsx` |
| ZIM x maternal_outcomes | `dictionary_zim_maternal_outcomes.xlsx` |
| ZIM x neolab | `dictionary_zim_neolab.xlsx` *(if scripts present)* |
| ZIM x baseline | `dictionary_zim_baseline.xlsx` *(if scripts present)* |
| ZIM x infections | `dictionary_zim_infections.xlsx` *(if scripts present)* |
| ZIM x twenty_8_day_follow_up | `dictionary_zim_twenty_8_day_follow_up.xlsx` *(if scripts present)* |
| MWI x admissions | `dictionary_mwi_admissions.xlsx` |
| MWI x discharges | `dictionary_mwi_discharges.xlsx` |
| MWI x maternal_outcomes | `dictionary_mwi_maternal_outcomes.xlsx` *(if scripts present)* |
| MWI x neolab | `dictionary_mwi_neolab.xlsx` *(if scripts present)* |
| MWI x phc_admissions | `dictionary_mwi_phc_admissions.xlsx` *(if scripts present)* |
| MWI x phc_discharges | `dictionary_mwi_phc_discharges.xlsx` *(if scripts present)* |
| MWI x combined_maternity_outcomes | `dictionary_mwi_combined_maternity_outcomes.xlsx` *(if scripts present)* |
| MWI x dhis2_maternal_outcomes | `dictionary_mwi_dhis2_maternal_outcomes.xlsx` *(if scripts present)* |
| MWI x maternity_completeness | `dictionary_mwi_maternity_completeness.xlsx` |
| ZIM x phc_admissions | `dictionary_zim_phc_admissions.xlsx` *(if scripts present)* |
| ZIM x phc_discharges | `dictionary_zim_phc_discharges.xlsx` *(if scripts present)* |

> **Note:** dictionaries marked "if scripts present" are attempted automatically by the build script. If no matching script titles are found in the data-key export for that combination, the attempt is silently skipped and reported in the build log. `joined_admissions_discharges` has no dedicated dictionary -- it falls back to the admissions dictionary at runtime.

> **ZIM infections note:** `zim_infections` is a server-side derived file — all rows carry `Transformed = TRUE` and the `Scriptid` field is empty for >99% of records. No dedicated Neotree script exists for it in the web editor. Its `DATASET_FILTERS` regex matches NeoLab scripts as the closest approximation, and `00c` enrichment is aliased to the NeoLab script JSON. The low enrichment rate (2/21 variables found in scripts) is expected and not an error.

> **MWI maternal datasets — background:** MWI has three source maternal data files collected via different mechanisms, plus a server-side combined file:
>
> | Dataset | Source | Date range | `neotreeoutcome`? | Status |
> |---|---|---|---|---|
> | `maternal_outcomes` | Original Neotree maternal script (KCH) | Nov 2021 – Jan 2022 | No | **Retired** |
> | `dhis2_maternal_outcomes` | DHIS2 Maternal Outcomes script (KCH) | Jun 2024 – present | Yes | **Currently active** |
> | `maternity_completeness` | Paper records, entered manually — no Neotree script | Nov 2021 – May 2025 | No | Paper backfill only |
> | `combined_maternity_outcomes` | Server-side join of all three above | — | Yes (inherited) | Derived file |
>
> `maternity_completeness` has no dedicated Neotree script; its `DATASET_FILTERS` regex deliberately matches the same maternal outcomes scripts as `maternal_outcomes` as the closest available approximation. At pipeline runtime, `DICT_FALLBACK` also maps this dataset to the `maternal_outcomes` dictionary as a safety net.

### Key configuration constants

All user-editable constants are in the `CONSTANTS` section at the top of the script.

| Constant | Purpose | When to edit |
|---|---|---|
| `DOWNLOADED_KEYS_BASE` | Path to the downloaded data-key exports | If the folder layout changes |
| `COUNTRY_FOLDERS` | Subfolder name per country | If new countries are added |
| `OUTPUT_DIR` | Where to write the dictionaries (default: `.`) | If you want to write elsewhere |
| `PIPELINE_TYPE_MAP` | Maps web-editor `dataType` -> R pipeline `r_type` | If Neotree adds a new field type |
| `CATEGORICAL_TYPES` | Which dataTypes need a ValueMap | If Neotree adds new categorical variants |
| `DATASET_FILTERS` | Regex patterns matching script titles for each dataset | If script naming conventions change. **Note:** `infections` maps to the `neolab` pattern (same NeoLab script); `maternity_completeness` maps to the `maternal_outcomes` pattern (no dedicated script exists) |
| `RECORD_ID_KEYS` | Columns treated as record identifiers, not analysis variables | If new system columns are added |
| `WEIGHT_KEYS_GRAMS` | Fields stored in grams that need kg conversion in Module 11 | If new weight fields are added |
| `MANUAL_RANGES` | Hard definitional limits for validated scoring instruments and percentage fields (Apgar, Thompson, SpO2) | Only when a new field has a formally defined hard upper/lower limit (e.g. a clinical score or a percentage). For researcher-defined ranges (weight, temperature, etc.) use `user_ranges.xlsx` instead — see below. |
| `KEY_UUID_OVERRIDES` | Explicit UUID overrides for specific country x dataset x question_key combinations | **See "Duplicate question_keys" section below** |
| `PII_PATTERNS_DATA` | All Tier 2 PII patterns -- the single source of truth | **See PII section below** |
| `QUASI_ID_PATTERNS` | Patterns for fields flagged but not auto-removed | **See PII section below** |

---

## 2. `user_ranges.xlsx` -- researcher-defined plausible ranges

### Purpose

A persistent, human-editable Excel workbook that defines plausible min/max ranges for any numeric variable. It is read by `00_build_dictionary_v8.r` during every dictionary rebuild and its values are written into the `suggested_plausible_min` / `suggested_plausible_max` columns of the dictionary **Variables** sheet.

**This file is never overwritten by any pipeline script.** Ranges defined here survive every dictionary rebuild.

Open it in Excel or any spreadsheet application and edit the **Ranges** sheet directly. A second **Instructions** sheet inside the workbook provides full usage guidance.

### How it works

- Ranges are applied to **all datasets** that contain the named variable.
- User-defined ranges **override** `MANUAL_RANGES` in the build script if there is a conflict — giving the researcher full control.
- Variables outside the defined range are set to `NA` by **Module 11** (numeric validation) and coded **-8** (implausible value) by **Module 16** (NA reason coding), exactly as for the existing Apgar, SpO2, and Thompson ranges.

### Format (Ranges sheet)

| Column | Required | Description |
|--------|----------|-------------|
| `question_key` | Yes | Lowercase variable key, exactly as it appears in the dictionary |
| `suggested_plausible_min` | No | Minimum plausible value; leave blank for no lower bound |
| `suggested_plausible_max` | No | Maximum plausible value; leave blank for no upper bound |
| `notes` | No | Free-text explanation — not used by the pipeline |

Row 1 is an instruction banner (ignored by the script). Row 2 is the header. Rows 3 onwards contain data rows — every non-blank row is processed. A handful of empty rows are provided at the bottom for adding new variables.

### How to find the `question_key` for a variable

The `question_key` is the lowercase identifier for a field in the Neotree data. Three places to look:

1. **Dictionary files (most reliable)** — open any `dictionaries/dictionary_*.xlsx` and go to the **Variables** sheet. The `question_key` column lists every variable. The `variable_label` column has the human-readable name shown in the Neotree app, so search or filter by label to find the key. Use the dictionary for the country and dataset you are working with (e.g. `dictionary_zim_admissions.xlsx` for Zimbabwe admissions).

2. **Raw CSV column headers** — open a raw data file for the relevant dataset. Every column follows the pattern `{question_key}.value` and `{question_key}.label`. Strip the `.value` suffix and you have the key (it will already be lowercase).

3. **Skip logic reference** — `16_na_reason_coding/skip_logic_reference.xlsx` has an **All Variables** sheet listing all 367 fields that carry a skip condition, with `variable_key` and `label` columns. Useful for clinical fields.

The key must be entered in `user_ranges.xlsx` exactly as it appears in the dictionary — lowercase, no spaces or special characters.

### When to re-run the build script

After editing `user_ranges.xlsx`, re-run `00_build_dictionary_v8.r` (and optionally `00c`) to bake the new ranges into the dictionary files. Then re-run the cleaning pipeline so Module 11 enforces the new limits.

### Relationship to `MANUAL_RANGES`

`MANUAL_RANGES` (in the build script) is reserved for ranges that are **definitionally fixed** by a clinical scoring system or physical law — Apgar (0–10), SpO2 (0–100%), Thompson (0–22). Do not edit `MANUAL_RANGES` for physiological measurements; use `user_ranges.xlsx` instead.

---

## 3. `00c_enrich_dictionary_from_scripts.r` -- the enrichment script

### What it does

Reads each `dictionary_*.xlsx` produced in Step 1 and appends four new
columns to the **Variables** sheet by cross-referencing the Neotree script
metadata JSONs in `neotree_scripts/`:

| Column | Description |
|--------|-------------|
| `display_label` | Human-readable field label shown in the Neotree app |
| `optional` | `TRUE` / `FALSE`, or `NA` when inconsistent across hospital scripts |
| `skip_condition` | Raw condition expression controlling when the field is shown; blank when always shown |
| `valuemap_check` | `TRUE` when the script's coded options differ from the dictionary ValueMaps (worth reviewing); `FALSE` when they match; `NA` when comparison is not possible (e.g. numeric or free-text field) |

The script is **non-destructive**: only these four columns are written or
refreshed; all other columns, sheets, and workbook formatting are left intact.
It is safe to re-run at any time.

### Script-to-dictionary matching

Raw Firebase-style script IDs recorded in data rows do not match the
UUID-style IDs in the downloaded JSON files.  Matching is done by
country + dataset via `FACILITY_SCRIPT_MAP`, which is defined inline at
the top of `00c_enrich_dictionary_from_scripts.r`.

> **Note:** `FACILITY_SCRIPT_MAP` mirrors the one in
> `16_na_reason_coding/helpers/03_facility_script_map.r`.
> If scripts are replaced or new hospitals are added, update **both** files.

The `normalise_dataset_name()` function inside `00c` maps pipeline dataset aliases to the map keys before lookup. Two non-obvious mappings to be aware of:

| Pipeline dataset name | Map key used | Reason |
|---|---|---|
| `infections` | `neolab` | ZIM infections is a **server-side derived file** (all rows have `Transformed = TRUE`; `Scriptid` is empty for >99% of rows). No dedicated Neotree script exists for it. The NeoLab script is used as the closest approximation, but most infections fields are absent from it — low enrichment rate (2/21) is expected |
| `maternity_completeness` | `maternal_outcomes` | No dedicated script exists; paper records backfill. Maternal outcomes scripts are used as the closest approximation |
| `phc_admissions` | `admissions` | PHC admissions use the same script structure |
| `phc_discharges` | `discharges` | PHC discharges use the same script structure |

**Current `FACILITY_SCRIPT_MAP` entries** (as of May 2026):

| Country | Dataset | Facility | Script |
|---|---|---|---|
| ZIM | admissions | SMCH, CPH, BPH, PGH | Hospital-specific admission scripts |
| ZIM | discharges | SMCH, CPH, BPH, PGH | Hospital-specific discharge scripts |
| ZIM | maternal_outcomes | SMCH, CPH, BPH | Hospital-specific maternal scripts |
| ZIM | neolab | SMCH | NeoLab - Zim |
| ZIM | twenty_8_day_follow_up | SMCH, CPH | 28 Day Follow Up Forms |
| ZIM | baseline | CPH, BPH | Chinhoyi Baseline + Bindura Baseline Data Collection |
| MWI | admissions | KCH, KDH | Neotree Admission KCH + Kasungu District Hospital Neotree Admission |
| MWI | discharges | KCH, KDH | NeoDischarge KCH + Kasungu District Hospital Neotree Discharge |
| MWI | maternal_outcomes | KCH | Maternal Outcomes (Retrospective Data) -- fallback for Firebase IDs |
| MWI | neolab | KCH | NeoLab - Malawi |
| MWI | phc_admissions | PHC | Generic PHC Admission (Bua) |
| MWI | phc_discharges | PHC | Generic PHC Discharge (Bua) + NeoDischarge (PHC) |

PHC datasets for ZIM are not yet in the map (no ZIM PHC data currently); when available, add the relevant facility code and script UUID.

The DHIS2 Mat Outcomes script (`f1e2757a`) and Kasungu scripts (`fa11721e`, `388f5990`) are matched by exact `scriptId` (high confidence) rather than by facility code fallback -- this is handled in `16_na_reason_coding/helpers/03_facility_script_map.r` rather than in `00c`.

### Inputs

| Location | Contents |
|----------|----------|
| `dictionaries/dictionary_*.xlsx` | Workbooks from Step 1 |
| `neotree_scripts/zim-scripts/*.json` | Downloaded Neotree script metadata for Zimbabwe |
| `neotree_scripts/mwi-scripts/*.json` | Downloaded Neotree script metadata for Malawi |

### User configuration

Two constants at the top of `00c_enrich_dictionary_from_scripts.r` can be
changed without modifying logic:

| Constant | Default | Effect |
|----------|---------|--------|
| `OVERWRITE_IN_PLACE` | `FALSE` | `TRUE` overwrites the existing workbook in place; `FALSE` (default) saves a parallel `*_enriched.xlsx` copy alongside the original |
| `NEOTREE_SCRIPTS_BASE` | `"neotree_scripts"` | Path to the scripts directory, relative to the pipeline root |

### What the pipeline uses

The four enrichment columns are **informational** -- they are not consumed by
any current pipeline module.  The pipeline's core cleaning logic (Modules
01-15) uses only the columns produced by `00_build_dictionary_v8.r`.  The
enrichment columns are intended for human QA and future tooling (e.g.
reviewing `valuemap_check = TRUE` flags to decide whether to add missing
option codes, or consulting `skip_condition` when investigating unexpected NA
patterns in the data).

---

## 3. `00d_build_user_dictionary.r` -- the researcher user dictionary

### What it does

Generates clean, researcher-facing data dictionaries intended to accompany
any data release or research collaboration.  The outputs describe every
variable a researcher will encounter in the cleaned Neotree dataset, including
labels, data types, valid codes and ranges, which NA sentinel codes may appear,
and which other datasets contain the same variable.

**Primary sources (in priority order):**

1. **Neotree script JSON metadata** (`neotree_scripts/`) -- field labels, screen
   section groupings, field ordering, skip conditions, coded options.
2. **Pipeline cleaning dictionaries** (`dictionaries/`) -- data types, plausible
   ranges (`suggested_plausible_min/max`), harmonised column names, pii_tier and
   use_in_analysis exclusion flags, curated pipeline ValueMaps, and the enriched
   `display_label`.

> **`og_dictionaries` removed (2026-06-12).** This script previously also read the
> hand-maintained `og_dictionaries/` workbooks (`Dictionary_ZIM.xlsx` /
> `Dictionary_MWI.xlsx`, no longer distributed with this repository) to supply
> supplementary field-description labels. That
> dependency has been **fully removed** (`load_og_dict_labels()`, the `OG_DICT_DIR`
> constant, the `og_labels` parameter, and the `og_lbl` rung of the Description
> fallback were all deleted). The whole dictionary chain now runs **only** from the
> web-editor downloads (data keys + Neotree script JSON). The Description field now
> falls back: `display_label` -> `json_label` -> pipeline `variable_label` -> `question_key`.

### Outputs

All outputs are written to `user_dictionaries/` (relative to pipeline root):

| File | Description |
|------|-------------|
| `neotree_user_dict_zim.xlsx` | Excel workbook for Zimbabwe |
| `neotree_user_dict_mwi.xlsx` | Excel workbook for Malawi |

Each workbook contains:

| Sheet | Contents |
|-------|----------|
| **About** | Study metadata, generated date, and a reference to the NA Codes sheet |
| **Admissions / Discharges / ...** | One sheet per dataset — dictionary rows with section headers, blue Calibri styling |
| **Master** | All unique variables across all datasets in screen order |
| **NA Codes** | Two-section legend: (1) numeric sentinel codes −6 to −9 with Priority column; (2) raw string codes entered by data collectors (NK, UNK, NR, REFUSED, NE, NOT_DONE, PENDING, UNKNOWN, OTHER). Includes a footer note on filtering |

Each Excel sheet contains these columns:

| Column | Source | Notes |
|--------|--------|-------|
| **Description** | enriched `display_label` -> JSON label -> pipeline `variable_label` -> `question_key` | First non-empty source wins (`og_dict` label removed 2026-06-12) |
| **Variable Name** | `harmonised_variable_name` -> `question_key` | Monospace font for readability |
| **Type** | Pipeline `r_type` | Numeric / Boolean / Categorical / Text / Date-time |
| **Values / Codes** | Pipeline ValueMaps or JSON options (categorical/boolean); `suggested_plausible_min/max` (numeric) | Ranges come only from the pipeline cleaning dict |
| **NA Codes** | Derived from `pii_tier`, `skip_condition`, `r_type` | See the dedicated **NA Codes** sheet (two sections: numeric sentinel codes −6 to −9 with priority hierarchy; raw string codes NK / UNK / NR / etc. entered by data collectors) |
| **Available also in** | Cross-dataset index | Shows other datasets in the same country that contain this variable |

### Variable exclusions

| Condition | Effect |
|-----------|--------|
| `pii_tier == "1"` | Excluded -- column is removed entirely from the cleaned dataset |
| `use_in_analysis == FALSE` | Excluded -- column is not part of the pipeline output |

### User configuration

Constants at the top of `00d_build_user_dictionary.r`:

| Constant | Default | Effect |
|----------|---------|--------|
| `NEOTREE_SCRIPTS_BASE` | `"neotree_scripts"` | Path to JSON script files |
| `DICT_DIR` | `"dictionaries"` | Path to pipeline cleaning dictionaries |
| `OUTPUT_DIR` | `"user_dictionaries"` | Where to write all output files (created if absent) |
| `USE_ENRICHED_DICT` | `TRUE` | Prefer `*_enriched.xlsx` dictionaries (from Step 2) when available |

### FACILITY_SCRIPT_MAP note

`00d` contains an inline copy of `FACILITY_SCRIPT_MAP`, the same as `00c` and
`16_na_reason_coding/helpers/03_facility_script_map.r`.  **Update all three
files** when Neotree scripts are replaced or new hospitals are added.

---

## 4. Dictionary Structure

Each workbook has four sheets.

### Sheet 1 -- Variables

One row per unique data key in the dataset. This is the primary sheet consumed by `00_setup.r`.

| Column | Type | Description |
|---|---|---|
| `environment` | string | "Zimbabwe" or "Malawi" |
| `dataset` | string | e.g. "MWI_admissions" |
| `question_key` | string | Normalised key name (lowercase, no special chars) |
| `raw_value_column` | string | Column name in the raw CSV: `{question_key}.value` |
| `raw_label_column` | string | Column name in the raw CSV: `{question_key}.label` |
| `variable_label` | string | Human-readable question label from web editor |
| `raw_data_type` | string | Web-editor dataType (e.g. `single_select`, `number`) |
| `r_type` | string | Pipeline type: `numeric`, `boolean`, `categorical`, `object`, `datetime` |
| `section` | string | Script title(s) this key appears in |
| `harmonised_variable_name` | string | Snake_case name for the final harmonised output |
| `use_in_analysis` | boolean | Whether this field is included in pipeline output |
| `weight_unit` | string | `"grams"` if weight conversion is needed; otherwise blank |
| `confidential` | boolean | `TRUE` if flagged confidential in the web editor (Tier 1 PII) |
| `pii_tier` | string | `"1"` / `"2"` / `"quasi"` / blank -- **see PII section** |
| `pii_category` | string | Type of PII: `direct_identifier`, `personal_name`, `phone_number`, `identifier`, `address`, `demographic`, `geographic` |
| `pii_matching_pattern` | string | The Tier 2 regex pattern that matched (blank for Tier 1 and non-PII) |
| `record_id_role` | string | Role of system/linkage columns (e.g. `record_uid`, `primary_linkage_key`) |
| `linkage_role` | string | `primary_linkage_key` / `secondary_linkage_key` for join columns |
| `suggested_plausible_min` | numeric | Minimum plausible value for numeric fields |
| `suggested_plausible_max` | numeric | Maximum plausible value for numeric fields |
| `cleaning_note` | string | Free-text annotation -- safe to edit manually |
| `key_unique_key` | string | Original UUID from the web-editor export |

### Sheet 2 -- ValueMaps

One row per allowed option for every categorical field. Consumed by Module 04 (dictionary-based value cleaning).

| Column | Description |
|---|---|
| `question_key` | Links back to Variables |
| `raw_code` | The raw coded value as stored in the database |
| `option_label` | Human-readable display label |
| `option_order` | Display order from web editor (legacy-version options appended after current-version rows) |
| `option_uuid` | Original option UUID (`NA` for rows added by the multi-version union or by `VALUEMAP_PATCHES`) |
| `canonical_code` | The code the pipeline standardises to (defaults to `raw_code`; edit via `VALUEMAP_PATCHES` to recode) |

> Rows in this sheet come from three sources, in order: (1) the **current** version of
> each data key; (2) the **multi-version union** -- option codes/labels valid in any
> earlier non-deleted version of the data key (added 2026-06-12, `canonical_code =
> raw_code`); (3) **`VALUEMAP_PATCHES`** -- curated corrections and additions that run
> last and can override (1) and (2). Module 04 emits the `canonical_code`, matching the
> data value against `canonical_code`, `raw_code`, or `option_label` case-insensitively.

### Sheet 3 -- PII_Patterns

The **Tier 2 PII pattern reference table**. This sheet is embedded in every dictionary workbook so each file is self-contained. Module 00a reads patterns from this sheet at runtime rather than using hardcoded constants.

| Column | Description |
|---|---|
| `pattern` | Regex applied to normalised column names (lowercase, no whitespace/underscores) |
| `pattern_type` | `"suffix_match"` (pattern ends with `$`) or `"contains"` (matches anywhere) |
| `pii_category` | Type of PII: `personal_name`, `phone_number`, `identifier`, `address` |
| `reason` | Plain-language explanation of why this pattern is PII |
| `countries` | Countries where this pattern is relevant (`MWI`, `ZIM`, or `MWI, ZIM`) |
| `examples` | Example field names matched by this pattern |
| `added_date` | Date the pattern was first added (YYYY-MM-DD) |
| `notes` | Audit notes -- e.g. version history or extension rationale |

### Sheet 4 -- ReviewNeeded

This sheet is generated automatically by the build script as a **triage list** of fields that may need human attention before the pipeline produces reliable output. It does not block the pipeline -- the pipeline runs correctly without resolving every item -- but unresolved items will degrade cleaning quality for the affected fields.

Each row contains the `question_key`, `variable_label`, `r_type`, and a `review_reason` column explaining why it was flagged. There are three possible review reasons:

---

#### Review reason 1 -- "Categorical with no value map entries"

**What it means:** The web-editor export defines this field as a `single_select`, `multi_select`, or equivalent categorical type, but the build script found no option codes for it. The resulting Variables sheet will have `r_type = "categorical"` for this field, but the ValueMaps sheet will contain no rows for it.

**What happens at run time:** Module 04 (value cleaning) will attempt to validate values for this field against its ValueMap and will find nothing to validate against. All raw codes will pass through unchecked, which means miscoded or unexpected values will not be caught.

**What to do:**

1. Look up the field in the Neotree web editor and check whether it actually has coded options. If it does, the missing options are likely a download issue -- re-download `data-keys-metadata.json` and rebuild.
2. If the field genuinely has no fixed option list (e.g. it was defined as a categorical type in the editor but functions as a free-text field in practice), open the `dictionary_*.xlsx` for that country x dataset, go to the **Variables** sheet, find the row for this `question_key`, and change `r_type` from `"categorical"` to `"object"`. This tells the pipeline to treat it as free text. Make a note in `cleaning_note`.
3. If the field has known option codes that are simply missing from the export, add the missing rows directly to the **ValueMaps** sheet:
   - Columns to populate: `question_key`, `raw_code`, `option_label`, `option_order`, `option_uuid` (can be left blank), `canonical_code` (set equal to `raw_code` initially).
   - Validate after editing (`source("00_build_dictionary/validate_dictionaries.r")`).

> **Important:** If you manually add ValueMap rows, do **not** rebuild the dictionary from scratch without also updating the source JSON, because the rebuild will overwrite your additions.

---

#### Review reason 2 -- "Numeric without plausible range"

**What it means:** The field has `r_type = "numeric"` but no `suggested_plausible_min` or `suggested_plausible_max` is set. The build script checked `MANUAL_RANGES` and found no entry for this key.

**What happens at run time:** Module 11 will skip range validation for this field and retain all numeric values. This is the expected and correct behaviour for most clinical variables.

**Pipeline philosophy on ranges:** Out-of-range values are replaced with `NA` (permanently lost). The pipeline therefore only enforces ranges for variables with formally defined hard limits -- values outside the range are definitively data entry errors, not unusual-but-real clinical findings. Currently, only `apgar1/5/10` (0-10), `satsair`/`satso2`/`dischsats` (0-100), and `thompscore` (0-22) meet this criterion. The SpO2 fields (`satsair`, `satso2`, `dischsats`) are percentages: a value above 100 is structurally impossible regardless of clinical context. Continuous physiological measures -- gestation, birth weight, temperature, heart rate, respiratory rate, blood sugar, maternal age, head circumference -- intentionally have no range, so extreme values are retained for downstream analysis.

**What to do:**

Only add a range if the field is a validated clinical instrument with a formally defined maximum (like an Apgar or Thompson score). For all other numeric fields, leave this item unresolved -- the "Numeric without plausible range" flag in ReviewNeeded is informational, not a call to action. Add a note to `cleaning_note` in the Variables sheet if desired.

---

#### Review reason 3 -- "Unknown dataType"

**What it means:** The web-editor export includes a `dataType` value not present in `PIPELINE_TYPE_MAP`. The build script cannot determine the correct `r_type` for the field and has left it blank or assigned a default.

**What happens at run time:** A field with no `r_type` is likely to cause errors or be silently skipped in type-specific cleaning modules.

**What to do:**

1. Identify the new `dataType` string (it appears in `review_reason` in the ReviewNeeded sheet, and in the raw `data-keys-metadata.json`).
2. Determine the appropriate pipeline type -- `numeric`, `boolean`, `categorical`, `object`, or `datetime`.
3. Add the mapping to `PIPELINE_TYPE_MAP` in `00_build_dictionary_v8.r`:
   ```r
   PIPELINE_TYPE_MAP <- c(
     ...,
     "new_data_type_string" = "numeric"   # replace with correct r_type
   )
   ```
4. If the new type requires value maps (i.e. it is a new kind of categorical), also add it to `CATEGORICAL_TYPES`.
5. Rebuild and validate.

> This reason is rare and only appears when the Neotree web-editor introduces a new field type that was not present when the build script was last updated.

---

#### Working through the ReviewNeeded sheet in practice

When you open a freshly rebuilt dictionary, a reasonable workflow is:

1. Open the **ReviewNeeded** sheet and sort by `review_reason`.
2. Handle all "Unknown dataType" rows first (they are rare and require build script changes).
3. Work through "Categorical with no value map entries" rows. For each one: check the web editor, then either fix the download, change `r_type` to `"object"`, or add rows to ValueMaps.
4. Work through "Numeric without plausible range" rows. For each one: add to `MANUAL_RANGES` or document why no range applies.
5. If you made any build script changes (steps 2 or 4 above), rebuild and validate again. If you only edited the workbook directly (step 3, changing `r_type` or adding ValueMap rows), re-run validation only.
6. The ReviewNeeded sheet will still contain the original flagged rows after a rebuild -- it reflects the state at build time. Once you have handled an item, you can note this in `cleaning_note` in the Variables sheet for that field.

---

## 5. The PII System

The pipeline removes PII through three tiers. Tiers 1 and 2 are both governed by the dictionary; Tier 3 is value-level scanning inside Module 00a itself.

### Tier 1 -- Dictionary confidential flag

Fields where `confidential = TRUE` in the web-editor export. These are loaded by `00_setup.r` via `cfg$pii_columns` and removed first by Module 00a. They appear in the Variables sheet with `pii_tier = "1"`.

As of March 2026, only `mothlm.value` and `mothlm.label` are flagged via this mechanism. The Neotree team is progressively populating this flag.

### Tier 2 -- Pattern-based matching

Fields identified by regex patterns applied to normalised column names. The patterns are defined in `PII_PATTERNS_DATA` (in the build script), embedded as the `PII_Patterns` sheet in each dictionary, and read by Module 00a at runtime.

Current Tier 2 patterns:

| Pattern | Type | Category | Countries | Examples |
|---|---|---|---|---|
| `name\.value$` | suffix_match | personal_name | MWI, ZIM | babyfirstname.value, mothersurname.value, kinname.value |
| `cell\.value$` | suffix_match | phone_number | MWI | mothcell.value |
| `phone\.value$` | suffix_match | phone_number | ZIM | (various phone fields) |
| `address\.value$` | suffix_match | address | ZIM | matphysaddressdistrict.value |
| `hcwid` | contains | identifier | MWI, ZIM | hcwid.value, hcwid.label, hcwiddis.value |
| `hospnum` | contains | identifier | ZIM | mathospnum.value, babyhospnum.value |
| `neotreeid` | contains | identifier | MWI, ZIM | neotreeid.value |
| `stuid` | contains | identifier | MWI | stuid.value, stuid.label |
| `uidbid\.value$` | suffix_match | identifier | MWI, ZIM | uidbid.value |
| `uiddc\.value$` | suffix_match | identifier | MWI, ZIM | uiddc.value |
| `drid\.value$` | suffix_match | identifier | MWI, ZIM | drid.value |

> **How patterns are matched:** column names are normalised before matching -- lowercased, whitespace removed, underscores stripped -- so `BabyCryTriage.value` and `Baby Cry Tria Ge. Value` both become `babycryptriage.value`. This ensures patterns work identically for database and Metabase exports.

### Quasi-identifiers -- flagged, not removed

Fields that could contribute to re-identification in combination with other data, but have legitimate analytical uses. They are **flagged** in the audit report (`pii_tier = "quasi"` in Variables) but **not automatically removed**. The analyst must review them before sharing any dataset.

Patterns: `village`, `district`, `province`, `tribe\.value$`, `ethnicity\.value$`, `religion\.value$`, `address`

### Tier 3 -- Value-level scanning

After column removal, Module 00a scans every remaining cell for PII-like values (phone numbers, email addresses, NHS/hospital number patterns). Matching cell values are redacted to NA. This tier is hardcoded in Module 00a and does not involve the dictionary.

---

## 6. How to update PII rules

### Adding a new Tier 2 pattern

1. Open `00_build_dictionary_v8.r` and locate the `PII_PATTERNS_DATA` tibble in the `PII PATTERN DEFINITIONS` section.
2. Add a new row:
   ```r
   "newpattern",  "contains",  "identifier",
     "Description of what this field contains",
     "MWI, ZIM",
     "example.value, example.label",
     "YYYY-MM-DD",  NA_character_,
   ```
3. If the field should only be flagged (not removed), add the pattern to `QUASI_ID_PATTERNS` instead and do **not** add it to `PII_PATTERNS_DATA`.
4. Re-run the build script (`Rscript 00_build_dictionary/00_build_dictionary_v8.r`).
5. Validate (`source("00_build_dictionary/validate_dictionaries.r")`).
6. Module 00a will pick up the new pattern automatically on the next pipeline run -- no changes to Module 00a required.

### Promoting a field to Tier 1 (dictionary flag)

If a field should be flagged `confidential = TRUE` in the web editor:
1. Update the field's confidential flag in the Neotree web editor.
2. Re-download the data-key exports.
3. Re-run the build script. The field will appear with `pii_tier = "1"` in the Variables sheet and will be removed by Module 00a via `cfg$pii_columns`.

### Modifying an existing pattern

Edit the relevant row in `PII_PATTERNS_DATA`, update the `notes` field with the change history (date and reason), then rebuild and validate.

---

## 7. `validate_dictionaries.r` -- the validation script

### What it checks

| Check | Type |
|---|---|
| All core dictionary files exist (ZIM/MWI x admissions/discharges/maternal_outcomes) | **FAIL** if missing |
| Variables, ValueMaps, PII_Patterns, ReviewNeeded sheets present | **FAIL** if missing |
| Variables sheet has all required columns (including pii_tier, pii_category, pii_matching_pattern) | **FAIL** if columns absent |
| ValueMaps sheet has all required columns | **FAIL** if columns absent |
| PII_Patterns sheet has required columns, >=1 pattern, no blanks, no duplicates | **FAIL** / **WARN** |
| No null r_type for use_in_analysis rows | **WARN** |
| All ValueMap question_keys exist in Variables | **WARN** |
| All numeric ranges have min < max | **FAIL** if violated |
| pii_tier values are valid; Tier 2 fields have pii_matching_pattern | **FAIL** / **WARN** |
| confidential=True fields assigned pii_tier 1 or 2 | **WARN** |
| Known ranges present in ZIM admissions (spot-check) | **WARN** |
| Summary statistics per dictionary | Info only |

Optional extended dictionaries (`phc_*`, `combined_maternity_*`, `dhis2_*`, `maternity_completeness_*`) are validated if present and silently skipped if absent.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more failures -- see output for details |

### Interpreting failures

- **Missing sheet `PII_Patterns`** -- the dictionary was built with an older version of the build script. Rebuild with the current `00_build_dictionary_v8.r`.
- **Variables missing columns `pii_tier`/`pii_category`/`pii_matching_pattern`** -- same as above; rebuild.
- **Tier 2 fields missing `pii_matching_pattern`** -- a pattern match was registered but the matching pattern string was not stored. Check the `PII_PATTERNS_DATA` loop in the build script.
- **confidential=True fields without pii_tier 1/2** -- the dictionary has `confidential = TRUE` for a field that the build script did not classify as Tier 1. This typically means the field appears in the JSON with `confidential = TRUE` but the Tier 1 assignment logic didn't catch it. Check the build script's Tier 1 `if_else` condition.

---

## 8. Manual dictionary editing

Some columns are safe to edit directly in the Excel file without rebuilding. Others will be overwritten on the next rebuild and should only be changed via the build script.

### Safe to edit manually (survives rebuild -- these are NOT populated by the build script)

| Column | Use case |
|---|---|
| `suggested_plausible_min` / `_max` | Add or refine plausible ranges. Prefer adding to `MANUAL_RANGES` in the build script so the value is version-controlled |
| `cleaning_note` | Free-text annotation for analysts; not consumed by any pipeline module |
| `canonical_code` in ValueMaps | Recode a raw option code to a standardised canonical value (e.g. normalise `"Y"` -> `"yes"`) |

### Do NOT edit manually -- will be overwritten on rebuild

| Column | Reason |
|---|---|
| `pii_tier`, `pii_category`, `pii_matching_pattern` | Derived from `PII_PATTERNS_DATA` and the `confidential` flag in the build script |
| `r_type` | Derived from `PIPELINE_TYPE_MAP` |
| `harmonised_variable_name` | Auto-generated from the field key |
| `use_in_analysis` | Derived from `raw_data_type` and `isDraft` |
| `record_id_role`, `linkage_role` | Hardcoded logic in the build script |
| All PII_Patterns sheet content | Embedded directly from `PII_PATTERNS_DATA` |

### The correct way to make permanent changes

Always edit the relevant constant in `00_build_dictionary_v8.r`, then rebuild and validate:

| Change | Edit in build script |
|---|---|
| New/modified PII pattern | `PII_PATTERNS_DATA` tibble |
| New quasi-identifier | `QUASI_ID_PATTERNS` vector |
| New plausible range | `MANUAL_RANGES` list |
| New field type | `PIPELINE_TYPE_MAP` |
| New weight field | `WEIGHT_KEYS_GRAMS` |
| Correct a PII flag or r_type on a specific field | `VARIABLE_PATCHES` list — **see section 9 below** |
| Add, correct, or remove ValueMap rows for a specific field | `VALUEMAP_PATCHES` list — **see section 9 below** |

---

## 9. POST_BUILD_PATCHES — permanent corrections that survive rebuilds

### The problem they solve

Two kinds of corrections cannot be made cleanly via the mechanisms above:

1. **The web-editor export is wrong for a specific field** — for example, a clinical outcome field is flagged `confidential = TRUE` in the web-editor JSON (a data-entry error in the Neotree web editor), or a `yesno` field is mapped to `boolean` by `PIPELINE_TYPE_MAP` when it should be `categorical` because ZIM classifies it that way. Editing `PIPELINE_TYPE_MAP` would affect all `yesno` fields globally; we need a targeted per-field, per-country override.

2. **A hand-edit to the dictionary `.xlsx` file would be lost on the next rebuild** — `writexl::write_xlsx()` overwrites the workbook from scratch every time the build script runs.

`VARIABLE_PATCHES` and `VALUEMAP_PATCHES` solve both problems by encoding these corrections as code constants that are applied automatically at the end of every `build_dictionary()` call, after the main Variables and ValueMaps sheets are assembled but before the workbook is written.

### Idempotency — what it means and why it matters

All patches are **idempotent**: running the build script a second (or tenth) time produces exactly the same dictionary as running it once. Each patch action checks the current state before acting:

- `add_rows` compares the `option_label` values you want to add against those already in the ValueMaps sheet. Rows whose labels are already present are skipped. So if you run the build script today and again tomorrow, you will not end up with duplicate rows.
- `update_canonical` sets a canonical code to a new value. Running it again just sets the same value again — the result is identical.
- `remove_duplicate_raw_code` counts how many rows with the given `raw_code` exist. If there is already only one, it logs "no duplicates" and does nothing.
- `VARIABLE_PATCHES` writes a column value unconditionally. Setting `confidential = FALSE` on a row that already has `confidential = FALSE` is a no-op.

This means you never need to comment out or remove a patch after the first run, and the build script is safe to re-run at any time.

### Forward-compatibility — what happens when the upstream data improves

If the Neotree web-editor is corrected upstream — for example, a field is un-flagged as confidential in the JSON, or a question_key is added to the ZIM admission scripts — the patch simply becomes a no-op rather than a conflict:

- `VARIABLE_PATCHES` writes the corrected value even if the JSON already supplies it. No harm done.
- `LEGACY_VARIABLES` (used to inject `hivtestresult` into ZIM admissions) contains the guard: `if (lv$question_key %in% variables$question_key) next`. If the field ever appears naturally in the ZIM admissions dictionary, the injection is silently skipped.
- `VALUEMAP_PATCHES` `add_rows` checks for existing labels before adding, so if a future JSON export already includes the rows, no duplicates are introduced.

In all cases, the patch degrades gracefully. You do not need to track "which patches have been superseded by upstream fixes" — they are always safe to leave in place. A log message at `INFO` level records each action taken (or skipped).

### `VARIABLE_PATCHES`

Defined in the `POST-BUILD PATCHES` section of the build script. Each entry is a named list:

| Field | Description |
|---|---|
| `country` | `"MWI"` or `"ZIM"` |
| `datasets` | Character vector of `dataset_lc` values this patch applies to (e.g. `c("admissions", "discharges")`) |
| `question_key` | The `question_key` of the row to patch |
| `changes` | Named list mapping column names to new values; use `NA_character_` to clear a column |

The patch is applied after PII-tier assignment, so it can override the `pii_tier` and `pii_category` values that were set based on the (incorrect) `confidential` flag from the JSON.

**Current patches (as of May 2026):**

| question_key | Country | Dataset(s) | Change | Reason |
|---|---|---|---|---|
| `hivtestresult` | MWI | adm + dis | `confidential` FALSE; pii_tier/pii_category cleared | Clinical outcome, not a direct identifier |
| `hivtestresultdc` | MWI | dis | same | same |
| `datehivtest` | MWI | adm + dis | same | same |
| `haart` | MWI | adm + dis | same | same |
| `lengthhaart` | MWI | adm + dis | same | same |
| `mathivstat` | MWI | adm | same | same |
| `mathivtest` | MWI | adm + dis | `r_type` → `categorical` | ZIM classifies as categorical; boolean would give TRUE/FALSE output instead of Y/N |
| `birthplacesame` | MWI | adm + dis | `r_type` → `categorical` | same |
| `dysmorphic` | MWI | adm | `r_type` → `categorical` | same |
| `feversr` | MWI | adm | `r_type` → `categorical` | same |
| `ortolani` | MWI | adm | `r_type` → `categorical` | same |
| `inorout` | MWI | dis | `r_type` → `categorical` | same |
| `phototherapy` | MWI | dis | `r_type` → `categorical` | same |

### `VALUEMAP_PATCHES`

Each entry is a named list with an `action` field:

**`action = "add_rows"`**
Adds rows to the ValueMaps sheet for the specified `question_key`. The `rows` field is a data frame with columns `raw_code`, `option_label`, `canonical_code`. Rows are added only if their `option_label` is not already present.

**`action = "update_canonical"`**
Updates the `canonical_code` for specific `raw_code` values. The `updates` field is a named list of `raw_code = new_canonical_code`. Used when the canonical code in the JSON export doesn't align with the agreed cross-site standard.

**`action = "remove_duplicate_raw_code"`**
Removes duplicate rows sharing the same `raw_code` under a given `question_key`, keeping only the row whose `option_label` matches `keep_label`.

**Current patches (as of May 2026):**

| question_key | Country | Dataset(s) | Action | Detail |
|---|---|---|---|---|
| `mathivtest` | MWI | adm + dis | add_rows | Y/Yes, N/No, U/Unknown |
| `birthplacesame` | MWI | adm + dis | add_rows | Y/Yes, N/No, U/Unknown |
| `dysmorphic` | MWI | adm | add_rows | Y/Yes, N/No |
| `feversr` | MWI | adm | add_rows | Y/Yes, N/No |
| `ortolani` | MWI | adm | add_rows | Y/Yes, N/No |
| `inorout` | MWI | dis | add_rows | In/Within PHC, Out/Outside PHC |
| `phototherapy` | MWI | dis | add_rows | Y/Yes, N/No |
| `hivtestresult` | ZIM | adm | add_rows | R/Positive→R, NR/Negative→NR, U/Unknown→U |
| `mecpresent` | ZIM | dis | update_canonical | N→No, U→UNK, Y→Yes |
| `mecthickthin` | ZIM | dis | update_canonical | U→UNK |
| `lengthhaart` | MWI | adm + dis | remove_duplicate_raw_code | Keep "3rd Trimester more than 1 month before delivery"; remove shorter duplicate |

### Adding a new patch

**To correct a Variables column for a specific field:**
Append a new entry to `VARIABLE_PATCHES` in `00_build_dictionary_v8.r`. Rebuild and validate. No other file needs to change.

**To add, correct, or remove ValueMap rows:**
Append a new entry to `VALUEMAP_PATCHES`. Use `add_rows` for new rows, `update_canonical` for canonical code corrections, `remove_duplicate_raw_code` for duplicate cleanup. Rebuild and validate.

**Do not** make these corrections by hand-editing the dictionary `.xlsx` files — the next rebuild will overwrite them. The patches are the version-controlled equivalent of those hand-edits.

---

## 10. Full workflow

```
/-----------------------------------------------------------------\
|  Web-editor exports (data-keys-metadata.json + data-keys-usage.xlsx)
\---------------------------+-------------------------------------/
                            v
          Rscript 00_build_dictionary/00_build_dictionary_v8.r       <- Step 1
                            |
                            v
           dictionary_{country}_{dataset}.xlsx  (x18)
           +-- Variables     (fields + PII tiers + types + ranges)
           +-- ValueMaps     (allowed codes per categorical field)
           +-- PII_Patterns  (Tier 2 pattern reference)
           \-- ReviewNeeded  (items needing manual attention)
                            |
                            v
          Rscript 00_build_dictionary/00c_enrich_dictionary_from_scripts.r  <- Step 2
          (reads neotree_scripts/*.json; adds display_label, optional,
           skip_condition, valuemap_check to each Variables sheet;
           saves *_enriched.xlsx copies by default)
                            |
                            v
       Rscript 00_build_dictionary/validate_dictionaries.r        <- Step 3
                            |
                   /--------+-------\
                 PASS              FAIL -> fix and rebuild
                   |
                   v
          source("run_pipeline.r")                                       <- Pipeline
          (00_setup.r reads the dictionaries; all modules downstream
           use cfg objects derived from them)

          [independently, at any time]

          Rscript 00_build_dictionary/00d_build_user_dictionary.r        <- Step 4
          (reads neotree_scripts/*.json + dictionaries/; og_dictionaries
           removed 2026-06-12; produces user_dictionaries/neotree_user_dict_{country}.xlsx
           per country — About + per-dataset sheets + Master + NA Codes)
```

---

## 10. Handling duplicate question_keys

The `to_db_name()` function normalises every field name to a lowercase alphanumeric string (e.g. `"NeotreeOutcome"` -> `"neotreeoutcome"`). When two or more fields in the web-editor export produce the same `question_key` string, the build script deduplicates them by keeping the most recently published one (`publishDate`-based `slice(1)`). This works correctly for the majority of cases -- most duplicates are facility-specific variants of the same clinical question, and the most recent version is a reasonable default.

However, there is one known case where the publishDate rule picks the **wrong** entry, because the two fields are genuinely different clinical concepts that happen to share the same name.

### The `neotreeoutcome` problem in MWI maternity

In the MWI data keys, the field name `"NeotreeOutcome"` is used for two entirely different questions:

| UUID prefix | Label | Applicable dataset | Option codes |
|---|---|---|---|
| `9b361090` | "Birth Outcome" | Maternity scripts | LB, SBF, SBM, UNK |
| `a59852da` | "Outcome" | Neonatal discharge scripts | DC, NND<24, NND>24, TRH, ... |

Both normalise to `question_key = "neotreeoutcome"`. The neonatal discharge UUID (`a59852da`) has a newer `publishDate` and would win the dedup -- placing discharge outcome codes in the maternity dictionary, where they do not belong. Records containing birth outcome codes (LB, SBF, SBM, UNK) would pass through Module 04 uncleaned, and Module 13 would flag them as invalid values.

### Fix: `KEY_UUID_OVERRIDES`

A `KEY_UUID_OVERRIDES` list is defined in the CONSTANTS section of the build script. For each entry, the publishDate-based dedup result is **replaced** by the explicitly specified UUID, but only for the matching country x dataset combination. All other combinations are unaffected.

```r
KEY_UUID_OVERRIDES <- list(
  "MWI:combined_maternity_outcomes:neotreeoutcome" = "9b361090-1b37-4056-b1a2-64908729b2d5",
  "MWI:dhis2_maternal_outcomes:neotreeoutcome"     = "9b361090-1b37-4056-b1a2-64908729b2d5"
)
```

Only `combined_maternity_outcomes` and `dhis2_maternal_outcomes` are listed. The original `maternal_outcomes` script (retired Jan 2022) and `maternity_completeness` (paper records backfill) never collected the `neotreeoutcome` field at all — it is absent from both forms, so no override is needed or possible for those two datasets.

The build log will confirm each override was applied:
```
INFO [build_dictionary] UUID override applied: neotreeoutcome -> UUID 9b361090 ('Birth Outcome')
```

If the UUID is not found in the filtered metadata (e.g. that script type is not present for that country/dataset), a WARNING is logged and the override is silently skipped -- the publishDate winner is used instead.

**To add a new override:** identify the correct UUID for your question_key + dataset combination by inspecting `data-keys-metadata.json` (e.g. `grep -i "birth outcome" data-keys-metadata.json`), then add a new entry to `KEY_UUID_OVERRIDES` in the format `"COUNTRY:dataset_key:question_key" = "full-UUID"`. Country and dataset_key must exactly match the values passed to `build_dictionary()`.

### The label-variant problem in ValueMaps

A secondary issue affects the ZIM data keys: multiple option entries for the same field can share the same `raw_code` but have different label strings. The known case is `neotreeoutcome` / STBM:

| UUID prefix | Code | Label |
|---|---|---|
| `69c7a0e0` | STBM | "Stillbirth Macerated" *(correct spelling)* |
| `75d3d54b` | STBM | "Stillbirth Mascerated" *(typo -- "sc" instead of "c")* |

The typo variant is present because it was a genuine data-entry error in the web editor that was later corrected, but historical records in the database may contain either spelling. Module 04 uses a `lbl_to_code` map (option_label -> canonical_code) to replace label strings with canonical codes. If only one label variant is present in the dictionary, the other will pass through Module 04 uncleaned and be flagged by Module 13.

**Fix:** the ValueMaps dedup uses `distinct(question_key, option_label)` rather than `distinct(question_key, raw_code)`. Since the two STBM entries have different labels, both survive as separate rows in ValueMaps. Module 04's `lbl_to_code` map will then contain both spellings, both pointing to STBM.

**Leading/trailing whitespace:** the web-editor export occasionally has leading or trailing spaces in option labels (e.g. `" Stillbirth Mascerated"`). The `opt_lookup` construction in the build script applies `trimws()` to both `raw_code` and `option_label` before they enter the dictionary. Module 04 also calls `trimws()` on raw data values before the `lbl_to_code` lookup. Together these two trim steps ensure that spacing differences between the dictionary and the raw data never prevent a match.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build runs but no `.xlsx` files appear | Error in `load_country_keys()` -- data-key export not found | Check `DOWNLOADED_KEYS_BASE` path and confirm JSON/XLSX files exist |
| All dictionaries fail with `str_detect` error | `janitor::clean_names()` version mismatch producing wrong column names | The build script uses explicit `tolower(gsub(...))` normalisation -- if you see this error, check you are running the current version of the script |
| `PII_Patterns` sheet missing after rebuild | Running an older build script | Ensure you are running the current `00_build_dictionary_v8.r` |
| Validation fails with missing `pii_tier` column | Same as above | Rebuild with current script |
| Module 00a logs "Using built-in default patterns" | Dictionary was built without PII_Patterns sheet (old build) | Rebuild dictionaries |
| Dictionary filename has uppercase country (e.g. `dictionary_MWI_...`) | Running an older build script that used `country_up` in the filename | Current script uses `tolower(country_up)` -- rebuild |
| Log shows "UUID override NOT applied" warning | The override UUID is not present in the filtered metadata for that country x dataset | Check the UUID in `data-keys-metadata.json` and verify the correct dataset_key in `KEY_UUID_OVERRIDES`. Note: this warning is **not** expected for any current dataset — `maternal_outcomes` and `maternity_completeness` were removed from the override list because they never collected `neotreeoutcome` |
| MWI maternity dictionary has discharge outcome codes (DC, NND<24...) instead of birth codes (LB, SBF...) | Running a build script without `KEY_UUID_OVERRIDES` | Ensure you are running the current `00_build_dictionary.r`; the override forces UUID `9b361090` for `combined_maternity_outcomes` and `dhis2_maternal_outcomes` |
| ZIM `neotreeoutcome` only has one STBM label variant in ValueMaps | Running an older build script that used `distinct(question_key, raw_code)` | Current script deduplicates on `(question_key, option_label)` -- rebuild to get both label variants |
