# Module 16 -- NA Reason Coding

## Overview

After the cleaning pipeline produces the final dataset, many cells contain `NA` (missing values). Not all NAs mean the same thing. This module examines every NA cell and assigns a numeric reason code explaining *why* the value is missing. This distinction matters for downstream analysis -- in particular for machine learning, where treating a "test not done" the same as "test done but value lost" leads to misleading models.

The module produces up to three output files alongside the clean CSV. All land in the run's output subfolder (`output/<file_stem>/`):

| File | Default | Description |
|------|---------|-------------|
| `*_na_reasons.csv.gz` | **always** | Wide-format: same shape as the clean dataset, each cell contains a reason code where the clean-data cell is NA, otherwise empty. |
| `*_na_coded.csv` | **on** | The clean dataset with NA cells replaced by their numeric reason codes (`-6`/`-7`/`-8`/`-9`). Controlled by `SAVE_NA_CODED` (default `TRUE`). |
| `*_na_reasons_long.csv.gz` | **off** | Long-format provenance table: one row per NA cell, columns `uid`, `facility`, `variable`, `na_reason`, `raw_value`. Controlled by `SAVE_NA_REASONS_LONG` (default `FALSE`). Useful for ML feature engineering but large and slow to compute. |

The `.csv.gz` files are gzip-compressed CSV. No information is lost: the compression is lossless and reduces file sizes by approximately 85-90% compared to plain CSV. All standard analysis tools read these files natively without any extra steps -- see *Reading the output files* below.

---

## The Four Reason Codes

| Code | Label | Meaning |
|------|-------|---------|
| `-6` | **Redacted** | A value existed in the raw data but was removed because it matched a PII pattern (phone number, email address, hospital ID number). The information exists in reality but cannot be shared. |
| `-7` | **Not applicable** | The field was never shown to the data collector. The Neotree form's skip logic determined the field was not relevant for this patient -- for example, a result field for a diagnostic test that was never performed, or a question that only applies to preterm infants asked of a term baby. |
| `-8` | **Invalid / removed** | A value was present in the raw data but was removed by the cleaning pipeline because it failed validation: it was an unrecognised dictionary code, a label string contaminating a value field, a pattern that looks like a column header or timestamp, a numeric value outside the clinically plausible range, a value that failed type coercion, or a blacklisted entry. |
| `-9` | **Unknown** | The raw cell was empty, or contained a recognised missing-value placeholder (`nan`, `none`, `null`, `n/a`, `""`, etc.). The field was applicable to this patient but no useful value was recorded -- the information was simply not captured at the time. |

These codes deliberately mirror the convention used by the Vermont Oxford Network (VON), where `7` = N/A and `9` = Unknown. The negative sign distinguishes them from valid clinical values and makes them unambiguous in numeric columns.

---

## Classification Priority

When a cell is NA in the clean data, the module inspects the original raw value and the form's skip logic and assigns codes in this order:

1. **`-6` first** -- if the raw value exists and matches a PII pattern, it was redacted regardless of anything else.
2. **`-7` second** -- if the skip logic for this field evaluates to FALSE for this patient (the field was not shown), the cell is not applicable. This takes priority over `-9` even when the raw is empty, because the reason for emptiness is structural rather than informational.
3. **`-8` third** -- if the raw value was non-empty and non-PII but the clean value is NA, the pipeline removed it during validation.
4. **`-9` otherwise** -- the raw was empty or a missing-string placeholder, and no skip logic ruled it not applicable.

---

## What Is Skip Logic?

Neotree forms are not static -- they adapt to each patient as data is entered. Each screen (page) and field can have a **condition** that controls whether it is shown. If the condition is not met, the screen or field is skipped entirely and never appears on the tablet. The data collector never sees the question and therefore cannot answer it.

For example:
- "Was a cranial ultrasound performed?" is asked for all patients.
- "What was the ultrasound grade?" only appears **if** the answer to the previous question was "Yes".

A baby for whom no ultrasound was performed will have an empty `ultrasoundgrade` cell in the data -- but this is not an unknown value, it is a structurally absent one. The correct interpretation is "not applicable", not "unknown".

### The Condition Syntax

Neotree conditions are written in a simple expression language:

| Syntax | Meaning |
|--------|---------|
| `$FieldKey = 'value'` | Field equals a string value |
| `$FieldKey != 'value'` | Field does not equal a string value |
| `$FieldKey = true` | Boolean field is true |
| `$FieldKey = false` | Boolean field is false |
| `$FieldKey > 37` | Numeric field is greater than 37 |
| `$FieldKey < 2.6` | Numeric field is less than 2.6 |
| `expr and expr` | Both conditions must be true |
| `expr or expr` | Either condition must be true |
| `!$FieldKey = 'value'` | Equivalent to `$FieldKey != 'value'` |
| `(expr)` | Parentheses for grouping |

A field has two levels of condition: a **screen condition** (applies to all fields on that screen) and a **field condition** (applies to that specific field only). Both must be TRUE for the field to be shown. The module combines them as `(screen_condition) and (field_condition)`.

### How the Module Evaluates Conditions

For each NA cell, the module:

1. Identifies which script was used for this patient's record (by matching on `scriptid` first, then on `facility` + `dataset` -- see *Script Matching* below).
2. Looks up the effective condition for that field in that script.
3. Substitutes the patient's other recorded values into the condition (replacing `$FieldKey` with the actual raw value).
4. Evaluates the resulting expression in R.
5. If the result is `FALSE` -> the field was not shown -> code `-7`.
6. If the result is `TRUE` -> the field was shown but empty -> code `-9`.
7. If evaluation fails (missing variable, syntax edge case) -> conservative fallback to `-9`.

---

## Script Matching

Each patient record in the raw data has a `scriptid` column recording which Neotree form script was used to collect the data. Ideally we would match each record to its exact script. In practice there are two complications:

**Older records use Firebase-style IDs.** When Neotree migrated from its original Firebase backend, the main production scripts were re-published with new UUIDs. Older records carry Firebase IDs (e.g. `-ZO1TK4zMvLhxTw6eKia`) which no longer exist in the web editor. For these records, the module falls back to matching by `(facility, dataset)` -- using the current production script for that hospital as the best available approximation.

**Three scripts match exactly.** The Kasungu District Hospital admission and discharge scripts, and the DHIS2 Malawi maternal outcomes script, have UUIDs that match directly between the raw data and the downloaded JSONs. These are matched by ID with high confidence.

**Third-party imported records.** The combined maternity outcomes file contains records imported from a third-party source (not collected via Neotree). These records have unrecognised script IDs and no skip logic is available for them. All empty cells in these records receive `-9`.

The mapping is defined in `helpers/03_facility_script_map.r` and can be updated if new hospitals or scripts are added.

### PHC datasets and `normalise_dataset_name()`

`helpers/03_facility_script_map.r` contains a helper function `normalise_dataset_name()` that translates pipeline dataset aliases (e.g. `infections → neolab`) to the keys used in `FACILITY_SCRIPT_MAP`. This function must **not** map `phc_admissions → admissions` or `phc_discharges → discharges` before the lookup: PHC datasets have their own dedicated entries in the map, and collapsing them to standard names causes the lookup to return `NA` (no PHC-specific script found under the standard key), meaning skip-logic is never evaluated and every PHC `-7` cell is coded `-9` instead.

If you add a new PHC-style dataset, ensure it has its own entry in `FACILITY_SCRIPT_MAP` and is **not** normalised away by `normalise_dataset_name()` before the lookup is performed.

---

## Limitations

**Scripts may have changed since data collection.** The downloaded scripts represent the current version of each form. If screens or conditions were added, removed, or modified since older records were collected, the skip logic evaluation for those records may not perfectly reflect what data collectors actually saw. The module uses current scripts as the best available proxy; clinicians reviewing the output should bear this in mind for older data.

**Condition evaluation is approximate for complex expressions.** Conditions involving fields from earlier screens work well. Conditions comparing two field values to each other (e.g. `$DateTimeDeath > DateLastAttendedBaby`) require both fields to be present in the raw data; if either is missing the evaluation returns NA and the cell is coded `-9` conservatively.

**`-7` requires skip logic to have been downloaded.** If a script is not found for a record, all empty cells for that record receive `-9` rather than `-7`. The skip logic directory is configured via `cfg$neotree_scripts_dir` in `00_setup.r`.

---

## Configuration

Add the following to `00_setup.r` before running this module:

```r
# Path to the neotree_scripts directory containing zim-scripts/ and mwi-scripts/
NEOTREE_SCRIPTS_DIR <- file.path("..", "..", "key_dictionary", "neotree_scripts")
```

This is already added to `00_setup.r` as part of the pipeline integration.

---

## Using the Reason Codes for Machine Learning

The distinction between codes is clinically and statistically meaningful:

| Code | ML interpretation |
|------|-------------------|
| `-7` Not applicable | Encode as a **separate category** (e.g. `"not_applicable"`) rather than treating as missing. Models should learn that this state carries real clinical information -- it means a condition or procedure was absent. |
| `-9` Unknown | Treat as **standard missingness**. Use imputation (mean, median, MICE, etc.) or add a binary `_is_missing` indicator column. |
| `-8` Invalid/removed | Treat as missing for most purposes, but consider flagging with an indicator -- the missingness pattern may be informative (e.g. systematic data quality issues at a specific facility or time period). |
| `-6` Redacted | Treat as missing for analysis. The value existed but cannot be observed. If the fact of redaction is itself informative, an indicator column can encode it. |

The long-format output (`*_na_reasons_long.csv.gz`, when enabled via `SAVE_NA_REASONS_LONG = TRUE`) is designed to make this easy: join it to your feature matrix on `(uid, facility, variable)` to add reason-code columns for any variables you choose.

---

## How These Scripts Could Improve the Data Dictionary

The Neotree script JSON files contain information that goes beyond what is currently in the cleaning pipeline's data dictionary. A future `00_build_dictionary` update could extract:

| Script element | Dictionary improvement |
|----------------|------------------------|
| `screen.title` and `field.label` | Enrich `variable_label` with the exact question text shown to data collectors |
| `field.options` | Verify and complete the `ValueMaps` sheet -- each option has a `value` (code) and `valueLabel` (display text) |
| `field.condition` / `screen.condition` | Add a new `skip_condition` column to the Variables sheet, enabling automated structural NA detection without this module |
| `field.optional` | Add an `optional` flag indicating whether the field was required or optional on the form -- mandatory fields with `-9` are more likely to represent genuine data gaps than optional ones |
| `field.dataType` | Cross-check against `r_type` to catch type mismatches in the dictionary |
| `screen.title` (section grouping) | Improve the `section` column, which currently contains free-text descriptions |

---

## Skip Logic Reference Files

Four reference files in this folder document every variable in the Neotree scripts that carries a field-level skip condition, each suited to a different use:

- `skip_logic_reference.xlsx` -- Excel workbook with a **Summary** sheet (one row per group, colour-coded), an **All Variables** sheet (all 367 fields in a filterable flat table), and one dedicated sheet per clinical group. The best starting point for clinical review.
- `skip_logic_reference.csv` -- flat table of all 367 fields with columns: `group`, `group_rationale`, `variable_key`, `label`, `skip_condition`, `scripts`. Suitable for programmatic use, joining to other datasets, or importing into statistical software.
- `skip_logic_reference.md` -- formatted Markdown, grouped with full narrative rationale per group. Intended for reading in a text editor or rendered documentation.
- `skip_logic_reference.txt` -- plain-text equivalent of the Markdown file, suitable for grep or diff.

All four files are generated from the same source data (the script JSON files in `key_dictionary/neotree_scripts/`) and contain identical information in different formats. They are intended as a reference for clinicians reviewing the `-7` (Not Applicable) codes in the NA reason output, and for analysts who want to understand why specific fields are systematically absent for certain patient groups.

### What the reference files contain

**367 variable keys** are covered, each carrying a field-level skip condition in at least one Neotree script. The variables are organised into 15 clinical groups:

| Group | Fields | Summary |
|---|---|---|
| 1. Dumpsite / unknown-origin baby | 64 | `AdmReason = 'DU'`: baby found abandoned, no maternal or birth history available. Affects birth weight, gender, antenatal care, mode of delivery, and virtually all maternal fields. |
| 2. Brought In Dead (BID) -- outcome routing | 37 | `NeoTreeOutcome = 'BID'`: the baby arrived at the facility already deceased. The form hides fields only relevant for live admissions (treatments, feeding, follow-up). NAs here are clinically meaningful. |
| 3. Date of birth known / unknown | 15 | `DOBYN = 'Y'` / `BIDDOBYN = 'Y'`: the date field is only shown if the clinician confirms the date is known. If not, an age-estimate field is shown instead. |
| 4. Investigation two-step pattern | 80 | `$FBC`, `$CRP`, `$UE`, `$Bili`, `$BC`, `$GLUC`, `$IMAGING`, `$LP`, etc.: result and detail fields are hidden until the corresponding test is confirmed as performed. The most frequent single source of `-7` codes. |
| 5. HIV pathway | 15 | `$MatHIVStat`, `$HIVtestResult`, etc.: HAART, viral load, DNA PCR, and infant prophylaxis fields only appear for HIV-positive or unknown-status patients. |
| 6. Syphilis pathway | 5 | `$ANVDRLResult = 'P'` or `'U'`: treatment and result detail fields only appear after a positive or equivocal syphilis screen. |
| 7. Medication then detailed | 36 | `$MedsGiven`, `$ANSteroids`, `$Transfusion`, etc.: dose, route, timing, and product-type fields only appear after confirming the treatment was administered. |
| 8. Maternal admission and outcome | 19 | `$MatAdm`, `$MatOutcome`, `$MatCauseDeath`, etc.: maternal admission source, outcome details, and cause of maternal death gated by admission status and specific outcomes. |
| 9. Mode of delivery specific | 10 | `$ModeDelivery`: reason for CS only if delivery was caesarean; BBA details only for out-of-facility births; fetal presentation only for certain delivery types. |
| 10. Resuscitation details | 8 | `$RESUS`, `$Resus`: duration, type, and respiratory support fields only if resuscitation was performed. |
| 11. Clinical condition then detailed | 50 | `$Bone`, `$J` (jaundice), `$Dysmorphic`, `$FoeHrtDoc`, etc.: sub-fields for a clinical condition only appear if the screening question for that condition was answered affirmatively. |
| 12. Follow-up review | 15 | `$Review`, `$REVCLIN3D`, `$REVCLIN7D`, `$REVCLIN6W`, etc.: 3-day, 7-day, 6-week, and KMC review details only if the review was completed. |
| 13. COVID-19 risk screening | 2 | `$DiscCovidRisk`: pandemic-era fields gated by a COVID risk screening question. Expected to be absent in most records. |
| 14. Site configuration / identifier fields | 4 | `$HCWSig`, `$Ethnicity`, etc.: HCW electronic signature fields and some demographic fields that are site-specific. |
| 15. Other / miscellaneous | 7 | Remaining fields with field-level conditions that do not fit the groups above. |

### How to use the reference files

**Clinicians** reviewing `-7`-coded cells in the NA reason output can look up any variable key in the reference file to find the exact condition string that caused it to be hidden, and the plain-English rationale for that design decision.

**Analysts** can use the `skip_condition` column (once the dictionary enrichment script is implemented) to programmatically verify whether a `-7` code is expected for a given patient record, and to build features that encode the presence/absence of clinical pathways (e.g. "this baby went through the HIV management pathway").

**Note:** the files reflect the current versions of the downloaded Neotree scripts. If scripts are updated, the files should be regenerated. A future pipeline task will automate this as part of the `00c_enrich_dictionary_from_scripts.r` step.

---

## Files in This Module

```
16_na_reason_coding/
+-- 16_na_reason_coding.r          Main module -- run this
+-- README.md                       This file
+-- skip_logic_reference.xlsx       Skip logic reference -- Excel workbook (Summary + per-group sheets)
+-- skip_logic_reference.csv        Skip logic reference -- flat CSV table (367 rows)
+-- skip_logic_reference.md         Skip logic reference -- formatted Markdown with narrative
+-- skip_logic_reference.txt        Skip logic reference -- plain text
+-- helpers/
    +-- 01_load_scripts.r           Parse Neotree JSON scripts -> condition table
    +-- 02_condition_evaluator.r    Evaluate Neotree condition strings in R
    +-- 03_facility_script_map.r    Map (facility, dataset) -> script UUID
```
