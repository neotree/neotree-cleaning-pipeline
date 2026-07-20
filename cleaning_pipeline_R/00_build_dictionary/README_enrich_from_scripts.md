# 00c_enrich_dictionary_from_scripts.r -- Dictionary Enrichment Script

## Purpose

Reads the `dictionary_*.xlsx` workbooks produced by
`00_build_dictionary_v8.r` and appends four new columns to each
**Variables** sheet by cross-referencing the Neotree script metadata
JSONs in `neotree_scripts/`.

Run after `00_build_dictionary_v8.r`.  Re-run whenever script JSONs are
updated or new scripts are downloaded.  This script is **non-destructive**
-- it only writes or refreshes the four enrichment columns and leaves all
other columns, sheets, and workbook formatting intact.

---

## How to run

```r
# From the pipeline root directory:
source("00_build_dictionary/00c_enrich_dictionary_from_scripts.r")
# or from the command line:
Rscript 00_build_dictionary/00c_enrich_dictionary_from_scripts.r
```

---

## Inputs

| Location | Contents |
|----------|----------|
| `dictionaries/dictionary_*.xlsx` | Workbooks from `00_build_dictionary_v8.r` (and manually maintained neolab dictionaries) |
| `neotree_scripts/zim-scripts/*.json` | Downloaded Neotree script metadata for Zimbabwe |
| `neotree_scripts/mwi-scripts/*.json` | Downloaded Neotree script metadata for Malawi |

---

## Outputs

For each input dictionary one of two things happens, depending on
`OVERWRITE_IN_PLACE`:

| Setting | Output |
|---------|--------|
| `OVERWRITE_IN_PLACE = TRUE` | Workbook is updated in place |
| `OVERWRITE_IN_PLACE = FALSE` (default) | A parallel `*_enriched.xlsx` copy is written alongside the original |

The four new columns added to the Variables sheet are:

| Column | Description |
|--------|-------------|
| `display_label` | Human-readable field label shown in the Neotree app |
| `optional` | `TRUE` / `FALSE`, or `NA` when inconsistent across hospital scripts |
| `skip_condition` | Raw condition expression controlling field visibility; blank when always shown |
| `valuemap_check` | `TRUE` when the script's coded options differ from the dictionary ValueMaps (worth reviewing); `FALSE` when they match; `NA` when comparison is not possible |

These columns are **informational** -- no current pipeline module
consumes them.  They are intended for human QA and future tooling.

---

## User configuration

Two constants at the top of the script:

| Constant | Default | Effect |
|----------|---------|--------|
| `OVERWRITE_IN_PLACE` | `FALSE` | `TRUE` = overwrite in place; `FALSE` = save `*_enriched.xlsx` alongside original |
| `NEOTREE_SCRIPTS_BASE` | `"neotree_scripts"` | Path to the scripts directory, relative to the pipeline root |

---

## Script-to-dictionary matching

Script UUIDs in the downloaded JSON files do not match the Firebase-style
IDs recorded in data rows.  This script uses `FACILITY_SCRIPT_MAP`
(defined inline near the top of `00c_enrich_dictionary_from_scripts.r`)
to map each (country, dataset) combination to the correct production
script UUIDs.

> **Important:** `FACILITY_SCRIPT_MAP` is duplicated in three places:
> - `00c_enrich_dictionary_from_scripts.r` (this script)
> - `00d_build_user_dictionary.r`
> - `16_na_reason_coding/helpers/03_facility_script_map.r`
>
> If scripts are replaced or new hospitals are added, update **all three**.

### Supported datasets in FACILITY_SCRIPT_MAP

| Country | Dataset | Scripts matched |
|---------|---------|-----------------|
| ZIM | admissions | SMCH, CPH, BPH, PGH |
| ZIM | discharges | SMCH, CPH, BPH, PGH |
| ZIM | maternal_outcomes | SMCH, CPH, BPH |
| ZIM | neolab / infections | SMCH (NeoLab - Zim) |
| ZIM | twenty_8_day_follow_up | SMCH, CPH |
| ZIM | baseline | CPH, BPH |
| MWI | admissions | KCH, KDH |
| MWI | discharges | KCH, KDH |
| MWI | maternal_outcomes | KCH (Retro + DHIS2) |
| MWI | neolab | KCH (NeoLab - Malawi) |
| MWI | phc_admissions | PHC (Generic PHC Admission - Bua) |
| MWI | phc_discharges | PHC, PHC2 (Generic PHC Discharge + NeoDischarge PHC) |

PHC datasets additionally match scripts found by title keyword ("PHC" or
"Primary Health Care" in the script title).

> **Note on `infections` vs `neolab`:** The pipeline BUILD_PLAN uses `infections`
> as a separate dataset key for NeoInfect-sourced blood culture data.  The
> `FACILITY_SCRIPT_MAP` lookup normalises `infections → neolab` internally so
> both datasets are matched against the same NeoLab script UUIDs.

> **Note on PHC datasets and `normalise_dataset_name()`:** This script contains
> a local copy of `normalise_dataset_name()` (the same function used in
> `16_na_reason_coding/helpers/03_facility_script_map.r`).  The function must
> **not** map `phc_admissions → admissions` or `phc_discharges → discharges`
> before the FACILITY_SCRIPT_MAP lookup.  PHC datasets have their own dedicated
> map entries; collapsing them to standard names causes the lookup to find no
> PHC-specific scripts and silently skip enrichment for those dictionaries.
> If you add a new PHC-style dataset, give it its own map entry and leave the
> name intact in `normalise_dataset_name()`.

---

## How the key matching works

Script JSON files use the original camelCase field keys as exported from
the Neotree web editor (e.g. `Org1`, `BCResult`, `BabyBwd`).  The
pipeline dictionaries store lowercase `question_key` values (e.g. `org1`,
`bcresult`, `babybwd`).  The script normalises all JSON keys to lowercase
before matching so they align with the dictionary.

---

## Log output interpretation

```
[00c] Matched 2 script JSON(s).
[00c] Parsed 359 field occurrence(s) across 2 script(s).
[00c] Enriched 123 / 260 variables (137 not found in scripts).
[00c] valuemap_check: 4 variable(s) flagged with option mismatches.
```

- **Enriched N / M variables**: N variables were found in the script
  JSONs and had their four enrichment columns filled.  M - N variables
  were not found (this is normal for system columns, PII columns with
  `use_in_analysis = FALSE`, or pipeline-added variables that have no
  script counterpart).
- **valuemap_check flags**: Variables where the script's coded options
  differ from the dictionary ValueMaps.  Review these to decide whether
  the dictionary is missing option codes.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Enriched 0 / N variables" for all dictionaries | Case mismatch between JSON keys and dictionary `question_key` | Confirm the script has the `tolower()` normalisation step after building `all_fields` |
| "No matching scripts in FACILITY_SCRIPT_MAP -- skipping" | Country / dataset not in the map | Add an entry to `FACILITY_SCRIPT_MAP` |
| "Script UUIDs resolved but no JSON files matched" | JSON file missing from `neotree_scripts/` | Download the script JSON from the Neotree web editor |
| "Cannot parse JSON" error | Malformed JSON file | Re-download the script from the web editor |
