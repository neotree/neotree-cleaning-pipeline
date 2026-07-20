================================================================================
  Neotree Sample Maker
  README: run_anonymizer.R — Standalone de-identification script
================================================================================

OVERVIEW
--------
run_anonymizer.R removes or replaces identifying variables from any pipeline
output CSV (master_joined, master_joined_extended, subsample files, or any
combination), producing de-identified datasets safe for sharing or archiving.

All configuration is embedded at the top of the script in two clearly marked
sections — edit those sections, then Source or run with Rscript.

This script is completely independent of all other pipeline scripts.  It can
be run at any point after Pipeline 1 or Pipeline 2 has produced output files.


================================================================================
HOW TO RUN
================================================================================

1. Open run_anonymizer.R.
2. Edit SECTION A (input files and output settings).
3. Edit SECTION B (any additional variables to remove beyond the defaults).
4. Run:
     From RStudio  : click "Source"
     From terminal : Rscript run_anonymizer.R

Requirements:
  - R (any recent version)
  - Base R only — no external packages required
  - modules/anonymizer.R in the same folder as this script


================================================================================
CONFIGURATION (embedded in the script)
================================================================================

----------------------------------------------------------------------
SECTION A — INPUT FILES AND OUTPUT SETTINGS
----------------------------------------------------------------------

  input_files
      Character vector of file paths to anonymize.
      Can be any pipeline CSV output: master_joined, master_joined_extended,
      subsample_joined, subsample_joined_extended, or any combination.
      Relative paths are resolved from the script's directory.
      Each input file produces one _anon.csv output.

  output_dir
      NULL  → each _anon.csv is written to the same folder as its source file.
      Or provide a single output folder: "outputs/zim_master/anonymized"

  add_anon_id
      TRUE  → adds an anon_id column (sequential integers 1, 2, 3, …) as the
               first column.  Useful for referencing specific records in
               analysis without any patient-linkable identifier.
      FALSE → no ID column added.

  convert_datetimes
      FALSE (default) → datetimeadmission and datetimedischarge are kept
               as-is with their original exact values.  Use this when the
               anonymized file is for internal analyses (e.g. length-of-stay
               calculations still need exact dates).
      TRUE  → datetimeadmission is replaced by adm_yearmonth ("2024-03")
               and datetimedischarge by dis_yearmonth.  Use this when sharing
               externally and day-level precision would be quasi-identifying.

----------------------------------------------------------------------
SECTION B — VARIABLES TO REMOVE
----------------------------------------------------------------------

The module always applies a built-in set of removals (see below).
SECTION B lets you add further columns specific to your data.

  additional_remove
      NULL or a character vector of extra column names to remove.
      Names not found in the data are reported and silently ignored.
      A commented list of common candidates is provided in the script
      (device IDs, HCW IDs, mother identifiers, etc.)
      — uncomment any you want, or add your own.


================================================================================
WHAT THE ANONYMIZER DOES (built-in rules)
================================================================================

These rules are applied to EVERY file processed, before any user-specified
additional_remove entries.  They are defined in modules/anonymizer.R and can
be extended there if needed.

DIRECT IDENTIFIERS — always removed:
  uid             The patient's unique identifier as entered in Neotree at
                  admission.  This is what the pipeline uses to link admissions
                  to discharges, so it directly identifies a baby.
  uniquekey       The Neotree form submission key.  Every form (admission or
                  discharge) gets a unique key assigned by the app, identifying
                  the specific data entry record.
  match_key       Not from the original data — added by the pipeline as
                  uid + "_" + facility.  Removed because it is directly
                  reconstructable from uid and facility.

PIPELINE-INTERNAL COLUMNS — always removed:
  adm_date_parsed Not from the original data — added by the pipeline as a
                  parsed POSIXct copy of datetimeadmission for internal date
                  arithmetic.  Redundant in any output file.

DATETIME COLUMNS — kept or converted depending on convert_datetimes:
  convert_datetimes = FALSE (default)
      datetimeadmission and datetimedischarge are kept unchanged.
  convert_datetimes = TRUE
      datetimeadmission  →  adm_yearmonth   (e.g. "2024-03-15 08:30" → "2024-03")
      datetimedischarge  →  dis_yearmonth
      Use when sharing externally and day-level precision is quasi-identifying.

WHAT IS KEPT:
  facility, datetimeadmission (unless convert_datetimes = TRUE), datetimedischarge
  (unless convert_datetimes = TRUE), match_type, prob_match_similarity, and all
  clinical variables (birthweight, gestation, gender, apgar scores, diagnoses,
  outcomes, etc.)


================================================================================
OUTPUT FILES
================================================================================

For each input file:
  {original_filename}_anon.csv
      The de-identified dataset.  Same rows as the input; columns as described
      above.  If add_anon_id = TRUE, an anon_id column is prepended.

One combined report:
  anonymization_report.txt
      Covers: variables removed, datetime conversions, per-file column counts
      before and after, output file list.
      Written to the same directory as the first output file (or output_dir
      if specified).


================================================================================
RECOMMENDED WORKFLOW
================================================================================

  run_sample_maker.R          → master datasets (full, identified)
        ↓
  run_subsample_maker.R       → researcher-specific extract (identified)
        ↓
  run_anonymizer.R            → de-identified files for sharing / archiving

The anonymizer should be run LAST — after subsample filtering — because the
subsample_maker uses exact datetimes and uid/facility for its filtering logic.
If you anonymize first, date-range and facility filtering in the subsample
maker will no longer work correctly.


================================================================================
ADDING OR CHANGING VARIABLES TO REMOVE
================================================================================

Three places you can customise what gets removed:

1. SECTION B of this script (additional_remove)
   Add any column names specific to your data extract.
   This is the right place for HCW IDs, device IDs, GPS fields, etc.

2. ANON_REMOVE_ALWAYS in modules/anonymizer.R
   For direct identifiers that should always be removed from every run.
   Currently: uid, uniquekey, match_key.

3. ANON_DATETIME_CONVERT in modules/anonymizer.R
   For datetime columns that should be converted to year-month.
   Currently: datetimeadmission → adm_yearmonth, datetimedischarge → dis_yearmonth.
   Add any other datetime columns from your data here.


================================================================================
TROUBLESHOOTING
================================================================================

"Input file not found"
  → Check file paths in SECTION A.
  → Relative paths are resolved from the script's directory.

"Module not found: modules/anonymizer.R"
  → modules/anonymizer.R must be in the same folder as this script.

"additional_remove columns not found (ignored): columnname"
  → The listed column does not exist in the input file.
  → Check the exact spelling against the file header; this is a warning,
    not an error, so processing continues normally.

A column still appears in the output that should have been removed:
  → Check SECTION B: is the exact column name listed in additional_remove?
  → Check ANON_REMOVE_ALWAYS in modules/anonymizer.R for built-in removals.
  → Column names are case-sensitive.

================================================================================
