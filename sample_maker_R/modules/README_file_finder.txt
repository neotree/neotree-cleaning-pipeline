================================================================================
  Neotree Sample Maker — modules/file_finder.R
  README: Input file discovery
================================================================================

PURPOSE
-------
file_finder.R locates the admissions and discharges CSV files for a given
country and source combination.  It supports two modes: reading directly from
a cleaning pipeline output folder (Mode A, recommended) or searching the legacy
nested cleaned_files/ directory hierarchy (Mode B).

This module is called once at the start of run_sample_maker.R (STEP 1).

All directory and file name matching is case-insensitive, so Title Case folder
names produced by some Metabase extracts (e.g.
mwi_mb_Combined_Maternity_Outcomes_2026-05-07) are found correctly.


================================================================================
EXPORTED FUNCTION
================================================================================

  find_input_files(cfg, script_dir = NULL)

  Arguments:
    cfg         The CONFIG list from config_sample_maker.R
    script_dir  Directory of run_sample_maker.R, used to resolve relative paths.
                If NULL, the path settings in cfg are used as-is.

  Returns a named list:
    $admissions_path   Absolute path to the admissions CSV
    $discharges_path   Absolute path to the discharges CSV
    $target_dir        The directory that was searched


================================================================================
HOW IT WORKS — MODE A (cleaning pipeline output, default)
================================================================================

Mode A is used when cfg$cleaning_pipeline_output_dir is non-NULL (the default
value is "input").

1. RESOLVE THE ROOT DIRECTORY
   The pipeline folder is:
     file.path(script_dir, cfg$cleaning_pipeline_output_dir)   if script_dir given
     cfg$cleaning_pipeline_output_dir                           otherwise
   If the relative path does not exist, it is resolved against script_dir.

2. DETERMINE SOURCE CODE
   from_database → "db"
   from_metabase → "mb"

3. BUILD THE EXPECTED PREFIX
   {country_lower}_{src_short}_{type}_
   e.g. "zim_db_admissions_" or "mwi_mb_discharges_"

4. DISCOVER MATCHING SUBDIRECTORIES
   Lists all immediate subdirectories of the pipeline folder.
   Selects those whose basename starts with the expected prefix.
   Matching is CASE-INSENSITIVE (grepl(..., ignore.case = TRUE)).
   This handles Metabase Title Case subdirectory names transparently.

5. FIND THE CSV INSIDE THE SUBDIRECTORY
   Inside the matched subdirectory, looks for a file ending in _cleaned.csv.
   If exactly one match: that file is used.
   If multiple matches: the most recently modified file is used (with a warning).
   If no subdirectory or no CSV is found: stops with a clear error.

6. PRINT AND RETURN
   Prints the selected filenames to the console.
   Returns the paths and pipeline folder as a list.


================================================================================
HOW IT WORKS — MODE B (legacy hierarchy, fallback)
================================================================================

Mode B is used when cfg$cleaning_pipeline_output_dir is NULL.

1. RESOLVE THE ROOT DIRECTORY
   The cleaned_files root is:
     file.path(script_dir, cfg$cleaned_files_dir)     if script_dir is given
     cfg$cleaned_files_dir                              otherwise

2. BUILD THE TARGET SUBDIRECTORY
   Using country (lowercased), source, and cleaning from CONFIG:
     {cleaned_files_dir}/{country}/{source}/{cleaning}/
   e.g.  cleaned_files/zim/from_database/R_cleaned/

3. DETERMINE THE SHORT SOURCE CODE
   from_database → "db"
   from_metabase → "mb"

4. FIND EACH FILE BY PREFIX
   For each record type ("admissions" or "discharges"):
     Expected prefix: {country}_{src}_{type}_
     e.g. "zim_db_admissions_"

   All CSV files in the target directory are listed.
   Files whose basename starts with the prefix are retained (case-insensitive).
   If exactly one match: that file is used.
   If multiple matches: the most recently modified file is used (with a warning).
   If no match: the pipeline stops with an error showing the expected prefix
     and all files actually present in the directory.

5. PRINT AND RETURN
   Prints the selected filenames to the console.
   Returns the paths and target directory as a list.


================================================================================
INPUT FILE NAMING CONVENTION
================================================================================

Mode A — cleaning pipeline output structure:
  Subdirectory: {country}_{src}_{type}_{datestamp}/
  File inside:  {country}_{src}_{type}_{datestamp}_cleaned.csv

  Examples:
    zim_db_admissions_20260301/
      zim_db_admissions_20260301_cleaned.csv
    mwi_mb_discharges_2026-03-31/
      mwi_mb_discharges_2026-03-31_cleaned.csv
    mwi_mb_Combined_Maternity_Outcomes_2026-05-07/   ← Title Case, found OK
      mwi_mb_Combined_Maternity_Outcomes_2026-05-07_cleaned.csv

Mode B — legacy hierarchy:
  {cleaned_files_dir}/{country}/{source}/{cleaning}/{country}_{src}_{type}_{datestamp}_cleaned.csv

  Examples:
    cleaned_files/zim/from_database/R_cleaned/zim_db_admissions_20260301_cleaned.csv
    cleaned_files/mwi/from_metabase/R_cleaned/mwi_mb_discharges_2026-03-31_cleaned.csv

The finder matches on the prefix only, so any date stamp or additional suffix
is tolerated.

Accepted values for cfg$source:
  "from_database"  "from_metabase"

Accepted values for cfg$cleaning (Mode B only):
  "Python_cleaned"  "R_cleaned"

Any other value causes an immediate error with a clear message.


================================================================================
MULTIPLE DATA CUTS
================================================================================

If more than one data cut of the same dataset type is present in the same
directory (e.g. two admissions files with different dates), the module issues
a warning listing all matches and then uses the most recently modified file.
Old data extracts should be removed or moved to avoid ambiguity.


================================================================================
ERRORS AND WARNINGS
================================================================================

Mode A stop errors:
  "Cleaning pipeline folder not found: ..."
    → The input/ folder does not exist.  Check cleaning_pipeline_output_dir.

  "No admissions subdirectory found for prefix 'zim_db_admissions_' in: ..."
    → No matching subdirectory found.  Verify country and source settings.
    → Check that the input/ folder contains the correct cleaning pipeline output.

  "No _cleaned.csv file found inside: ..."
    → Subdirectory found but empty or without the expected file.

Mode B stop errors:
  "cleaned_files directory not found: ..."
    → The cleaned_files root does not exist.  Check cleaned_files_dir in config.

  "Target directory does not exist: ..."
    → The country/source/cleaning subdirectory does not exist.
    → Verify country, source, and cleaning values are correct.

  "No admissions file found in: ..."
  "No discharges file found in: ..."
    → No file with the expected prefix found.
    → The error lists all files present in the directory.

Warnings (both modes):
  "Multiple admissions files found — using the most recent: ..."
    → More than one file matched the prefix.
    → Only the most recently modified is used; others are ignored.
    → Remove old data extracts if this is unintentional.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (list.dirs, list.files, file.mtime, file.exists, dir.exists)
  - modules/pipeline_file_resolver.R  (Mode A helper, sourced automatically)
  - No other modules


================================================================================
