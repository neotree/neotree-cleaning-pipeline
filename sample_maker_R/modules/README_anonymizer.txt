================================================================================
  Neotree Sample Maker — modules/anonymizer.R
  README: De-identification of pipeline output files
================================================================================

PURPOSE
-------
anonymizer.R provides the logic for run_anonymizer.R.  It removes direct
identifiers, strips pipeline-internal columns, converts exact datetimes to
year-month strings, and optionally adds a sequential anonymous row ID.

This module is sourced exclusively by run_anonymizer.R.  It is not part of
Pipeline 1 or Pipeline 2.


================================================================================
EXPORTED FUNCTIONS
================================================================================

1.  anonymize_dataset(df, cfg)
    Applies all anonymization rules to a single data frame.
    Returns a named list describing what was removed and added.

2.  write_anonymizer_outputs(results_list, cfg, out_dir)
    Writes CSV outputs and a combined text report.
    Called internally by run_anonymizer.R — not called directly by the user.


================================================================================
CONFIGURABLE CONSTANTS (edit here to change built-in behaviour)
================================================================================

These three constants are defined at the top of anonymizer.R and control
what the module does to every file it processes, regardless of what the user
specifies in run_anonymizer.R.

----------------------------------------------------------------------
ANON_REMOVE_ALWAYS
----------------------------------------------------------------------
Direct identifiers that are unconditionally removed from every output:
  uid           Patient identifier
  uniquekey     Neotree record key
  match_key     uid + facility composite key (reconstructable identifier)

To add a column to this list, append its name here.

----------------------------------------------------------------------
ANON_REMOVE_PIPELINE_COLS
----------------------------------------------------------------------
Pipeline-internal columns that are always removed:
  adm_date_parsed    POSIXct version of datetimeadmission, redundant after
                     the datetime is converted to adm_yearmonth.

----------------------------------------------------------------------
ANON_DATETIME_CONVERT
----------------------------------------------------------------------
Named list mapping original datetime column → anonymized year-month column:
  datetimeadmission  →  adm_yearmonth
  datetimedischarge  →  dis_yearmonth

The new year-month column is inserted immediately after the original column
in the output, and the original column is removed.  Format: "YYYY-MM".

To add a datetime column from your data, add an entry here:
  myanydatetime = "myanydatetime_yearmonth"


================================================================================
FUNCTION DETAILS
================================================================================

----------------------------------------------------------------------
anonymize_dataset(df, cfg)
----------------------------------------------------------------------

Arguments:
  df    A data frame (any pipeline output CSV, loaded with read.csv).
  cfg   The ANONYMIZER_CONFIG list from run_anonymizer.R.
        Used fields: cfg$additional_remove, cfg$add_anon_id.

Processing steps (in order):

  1. Remove ANON_REMOVE_ALWAYS columns (if present).
  2. Remove ANON_REMOVE_PIPELINE_COLS columns (if present).
  3. Remove cfg$additional_remove columns (if present; missing names warned).
  4. Convert each column in ANON_DATETIME_CONVERT:
       - Parse with full datetime format; fall back to date-only.
       - Create a new YYYY-MM column in-place (same position).
       - Remove the original datetime column.
  5. If cfg$add_anon_id = TRUE: prepend anon_id = 1, 2, 3, … as first column.

Returns a named list:
  $df             Anonymized data frame
  $removed        Character vector of all column names removed (including
                  those replaced by year-month columns)
  $converted      Character vector of "original → new" conversion descriptions
  $added          Character vector of columns added (e.g. "anon_id")
  $n_rows         Number of rows (unchanged by anonymization)
  $n_cols_before  Number of columns before anonymization
  $n_cols_after   Number of columns after anonymization

----------------------------------------------------------------------
write_anonymizer_outputs(results_list, cfg, out_dir)
----------------------------------------------------------------------
Internal helper called by run_anonymizer.R.  Writes the anonymization report
using .build_anon_report().  Not called directly.


================================================================================
ANONYMIZATION REPORT SECTIONS
================================================================================

anonymization_report.txt contains four sections:

1. METADATA
   Run date/time, script name, add_anon_id setting.

2. VARIABLES REMOVED
   Lists all built-in removals (direct identifiers, pipeline cols, datetime
   conversions) and any user-specified additional_remove entries.
   Also lists any additional_remove names that were not found in the data.

3. FILES PROCESSED
   For each input file: row count, column counts before/after, columns removed,
   whether anon_id was added.

4. OUTPUT FILES
   Paths and file sizes of all _anon.csv files and the report itself.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (no external packages)
  - Not sourced by run_sample_maker.R or run_subsample_maker.R

================================================================================
