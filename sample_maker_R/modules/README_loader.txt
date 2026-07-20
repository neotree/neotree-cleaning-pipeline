================================================================================
  Neotree Sample Maker — modules/loader.R
  README: CSV loading and structural validation
================================================================================

PURPOSE
-------
loader.R reads the admissions and discharges CSV files and validates that the
minimum required columns are present.  It returns clean data frames and the
raw row counts used for reporting.

This module is called once at STEP 2 of run_sample_maker.R.


================================================================================
EXPORTED FUNCTION
================================================================================

  load_data(admissions_path, discharges_path)

  Arguments:
    admissions_path   Full path to the admissions CSV file
    discharges_path   Full path to the discharges CSV file

  Returns a named list:
    $admissions     Admissions data frame (all columns, all rows)
    $discharges     Discharges data frame (all columns, all rows)
    $n_adm_raw      Number of rows in the admissions file (before any filter)
    $n_dis_raw      Number of rows in the discharges file (before any filter)


================================================================================
HOW IT WORKS
================================================================================

For each file (admissions, then discharges):

  1. CHECK FILE EXISTS
     Stops immediately with a clear path if the file is not found.

  2. READ WITH read.csv()
     Uses stringsAsFactors = FALSE and check.names = FALSE.
     The check.names = FALSE setting preserves column names exactly as they
     appear in the CSV header, including any dots or special characters.

  3. CHECK FOR EMPTY FILE
     Stops if the resulting data frame has zero rows.

  4. VALIDATE REQUIRED COLUMNS
     Admissions must have: uid, facility, datetimeadmission
     Discharges must have: uid, facility

     If any required column is absent, the pipeline stops with an error that
     lists the missing columns and the first 30 column names actually present
     (to help diagnose naming differences).

  5. PRINT ROW AND COLUMN COUNTS
     Reports the number of records and columns loaded from each file.


================================================================================
REQUIRED COLUMNS
================================================================================

Admissions file:
  uid               — patient identifier (used in match key)
  facility          — facility name (used in match key)
  datetimeadmission — admission date/time (used for date window filtering)

Discharges file:
  uid               — patient identifier
  facility          — facility name

All other columns in both files are loaded as-is and passed through the
pipeline unchanged.


================================================================================
NOTES ON check.names = FALSE
================================================================================

By default, R's read.csv() sanitises column names (replacing dots and other
special characters).  Using check.names = FALSE preserves the original column
names exactly as written in the CSV header, ensuring that downstream modules
can reliably look up columns by name.


================================================================================
ERRORS
================================================================================

  "[loader] admissions file not found: ..."
    → The path returned by file_finder.R no longer exists (e.g. file was moved).

  "[loader] Failed to read admissions file '...': ..."
    → read.csv() threw an error (e.g. file is not a valid CSV, encoding issue).

  "[loader] admissions file is empty: ..."
    → The CSV exists but contains no data rows.

  "[loader] Required column(s) missing from admissions file: uid, facility"
    → One or more required columns not found.  The error shows the first 30
      column names in the file to help identify the correct names.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (read.csv, file.exists, nrow, ncol, names)
  - No other modules


================================================================================
