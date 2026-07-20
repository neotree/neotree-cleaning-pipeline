================================================================================
  Neotree Sample Maker
  README: run_subsample_maker.R — Standalone subsample creation script
================================================================================
  Version: 1.2  (2026-05)
================================================================================

OVERVIEW
--------
run_subsample_maker.R is the entry point for Pipeline 2.  It supports two
source modes, selected by the source_type setting in the config:

  source_type = "master"  (default)
    Reads master_joined and master_joined_extended CSV files produced by
    run_sample_maker.R (Pipeline 1).  Outputs four parallel CSV files and a
    text report.  Use for analyses requiring both admission AND discharge data.

  source_type = "cleaned"
    Reads directly from cleaned CSV files in the input/ folder.  Each enabled
    dataset type (admissions, discharges, neolab, maternal) is processed
    independently and produces one CSV + report per type.  Use when sharing a
    multi-dataset data package, or when working with cleaned data before the
    join pipeline has been run.

This script is entirely independent of run_sample_maker.R.  Configuration is
defined in a SUBSAMPLE_CONFIG list, which can be supplied in three ways: by
editing the embedded block inside this script, by passing an external config
file as a command-line argument (terminal), or by sourcing an external config
file before sourcing this script (RStudio).  See HOW TO RUN below.

Typical use cases:
  - Create a subsample for a specific study period without re-running the full
    pipeline (which can be slow on large datasets).
  - Produce a lean dataset with only the columns needed for a particular analysis.
  - Share a restricted extract with collaborators without exposing the full
    master dataset.
  - Build a multi-type data package from cleaned files (admissions + neolab,
    for example) without running the join pipeline first.


================================================================================
HOW TO RUN
================================================================================

There are three ways to run this script, depending on whether you want to edit
the embedded config or keep separate config files per research request.

----------------------------------------------------------------------
OPTION A — Edit the embedded config, then Source (simplest / ad-hoc)
----------------------------------------------------------------------

1. Open run_subsample_maker.R.
2. Edit the SUBSAMPLE_CONFIG block near the top of the file.
3. In RStudio click "Source", or from a terminal:
     Rscript run_subsample_maker.R

----------------------------------------------------------------------
OPTION B — External config file per request (recommended)
----------------------------------------------------------------------

Keep a separate pair of config files for each data access request.
For a new request, copy the appropriate template(s) and rename them:

  MASTER MODE  (joined admission + discharge data):
    Copy config_subsample_master_TEMPLATE.R
    Rename:  config_subsample_{Researcher}_{Study}_Nvars.R
    Fill in: master file paths, date window, facility, variable list
    Run:
      Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_Nvars.R

  CLEANED MODE  (standalone per-type files for DSH / neolab / maternal):
    Copy config_subsample_cleaned_TEMPLATE.R
    Rename:  config_subsample_{Researcher}_{Study}_cleaned.R
    Fill in: country, source, date window, facility, per-dataset variables
    Run:
      Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_cleaned.R

  For most requests, run BOTH and write to the SAME output_dir so that
  run_subsample_user_dict.R can auto-discover all files in one pass.

  For worked examples see the template configs:
    config_subsample_master_TEMPLATE.R    (master mode)
    config_subsample_cleaned_TEMPLATE.R   (cleaned mode)

  For the full option reference see config_subsample_TEMPLATE.R.

The script reads the config file automatically and the embedded
SUBSAMPLE_CONFIG block is skipped.

----------------------------------------------------------------------
OPTION C — External config file, run from RStudio
----------------------------------------------------------------------

RStudio's Source button cannot pass arguments, so use the R console
instead.  Run these two lines, with your working directory set to the
sample_maker_R folder:

     source("config_subsample_StudyName.R")
     source("run_subsample_maker.R", encoding = "UTF-8")

The first line loads SUBSAMPLE_CONFIG into the session.  The second
line detects it and skips the embedded default block.

To set the working directory to the script folder in RStudio:
  Session menu -> Set Working Directory -> To Source File Location

----------------------------------------------------------------------
Requirements (all options)
----------------------------------------------------------------------

  - R (any recent version)
  - Base R only — no external packages required
  - modules/ directory in the same folder as run_subsample_maker.R
    (needs modules/subsample_maker.R for master mode,
     modules/subsample_maker_cleaned.R + modules/pipeline_file_resolver.R
     for cleaned mode)
  - master mode: master_joined and master_joined_extended CSV files from Pipeline 1
  - cleaned mode: input/ folder containing cleaning pipeline output


================================================================================
CONFIGURATION (SUBSAMPLE_CONFIG — embedded in the script)
================================================================================

----------------------------------------------------------------------
SOURCE TYPE
----------------------------------------------------------------------

  source_type   "master" (default) or "cleaned"

  "master"  Reads master_joined / master_joined_extended files from Pipeline 1.
            All settings below apply.

  "cleaned" Reads directly from cleaned CSV files in the input/ folder.
            Uses modules/pipeline_file_resolver.R to locate files.
            Supports admissions, discharges, neolab, and maternal datasets.
            See DATASET SETTINGS (CLEANED MODE) below.

----------------------------------------------------------------------
INPUT FILES — MASTER MODE  (source_type = "master")
----------------------------------------------------------------------

  master_joined_file
      Path to the master_joined CSV from Pipeline 1.
      Relative paths are resolved from the script's directory.

  master_joined_extended_file
      Path to the master_joined_extended CSV from Pipeline 1.

The file prefix used in output names (e.g. "ZIM_db") is derived
automatically from the master_joined filename.

----------------------------------------------------------------------
INPUT FILES — CLEANED MODE  (source_type = "cleaned")
----------------------------------------------------------------------

  cleaning_pipeline_output_dir
      Path to the input/ folder (or any folder containing cleaning pipeline
      output subdirectories).  Relative paths are resolved from the script
      directory.  Default: "input"

  country   "zim" or "mwi"
  source    "from_database" or "from_metabase"

The output prefix is derived automatically as {COUNTRY}_{src_short}
(e.g. ZIM_db, MWI_mb).  Individual dataset types are enabled or disabled
in the datasets list (see DATASET SETTINGS below).

----------------------------------------------------------------------
OUTPUT DIRECTORY
----------------------------------------------------------------------

  output_dir
      NULL  → outputs go to "subsamples/" next to run_subsample_maker.R
              (both master and cleaned modes).
      Or provide a path: "subsamples/my_study" or an absolute path.
      The directory is created automatically if it does not exist.

----------------------------------------------------------------------
NA-CODED DUAL OUTPUT
----------------------------------------------------------------------

  output_na_coded   TRUE or FALSE  (default FALSE)

  FALSE  → write only the standard blank-NA subsample CSVs (default).
  TRUE   → also write a paired *_na_coded.csv alongside each standard
           output CSV.  The na_coded files contain the same rows but
           with NA values represented as numeric sentinel codes (-7, -8,
           -9, etc.) exactly as they appear in the source na_coded files
           produced by the cleaning/joining pipeline.

  Row selection always operates on the blank-NA file.  The na_coded
  file has the same rows extracted by row position, so filter logic
  (date, facility, exclusions) never has to interpret sentinel codes.

  Requires that the matching na_coded source file exists:
    master mode  : master_joined_na_coded.csv and
                   master_joined_extended_na_coded.csv  (auto-derived
                   from the master_joined_file path)
    cleaned mode : *_cleaned_na_coded.csv files in the input/ folder
                   (located automatically by pipeline_file_resolver.R)

----------------------------------------------------------------------
ADMISSION DATE WINDOW
----------------------------------------------------------------------

  sub_start_date   "YYYY-MM-DD" or NULL (no lower bound)
  sub_end_date     "YYYY-MM-DD" or NULL (no upper bound)

Filters rows by datetimeadmission.  Discharge data joined to a kept
admission is retained regardless of discharge date.
Both NULL → no date filter.

----------------------------------------------------------------------
FACILITY FILTER  (simple mode)
----------------------------------------------------------------------

  sub_facility_filter   NULL, single string, or character vector

  NULL              → all facilities
  "SMCH"            → one facility only
  c("SMCH", "BPH")  → multiple facilities

Ignored when sub_use_advanced_mode = TRUE.

----------------------------------------------------------------------
ADVANCED MODE: per-facility date ranges
----------------------------------------------------------------------

  sub_use_advanced_mode      TRUE or FALSE
  sub_facility_date_ranges   list of c("FACILITY", "start", "end")

When TRUE, sub_start_date / sub_end_date / sub_facility_filter are ignored.

----------------------------------------------------------------------
EXCLUSION FILTERS
----------------------------------------------------------------------

  sub_exclusion_filters   list() or a list of filter entries

  list()           -> no exclusion (default).
  list of entries  -> records matching any entry are removed.

Each entry: list(variable = "colname", operator = "...", value = ...)
Operators: "<", "<=", ">", ">=", "==", "!=", "in", "not_in"
Rows where the filter variable is NA are kept (conservative).
Applied after date/facility filter, before column selection.
When active, "_excl" is appended to the output label.

  Example -- remove gestational age < 24 weeks:
    list(variable = "gestation", operator = "<", value = 24)

  Example -- multiple conditions:
    sub_exclusion_filters = list(
      list(variable = "gestation",   operator = "<",  value = 24),
      list(variable = "birthweight", operator = "<",  value = 400)
    )

Use run_data_profiler.R to see variable names, types, and descriptive
statistics before setting exclusion thresholds.

----------------------------------------------------------------------
COLUMN SELECTION
----------------------------------------------------------------------

  sub_variables   NULL or a character vector of column names

  NULL   -> keep ALL columns.
  vector -> keep only listed columns plus mandatory ones always retained:
    master mode:  uid, facility, uniquekey, datetimeadmission, match_key,
                  adm_date_parsed, match_type, prob_match_similarity
    cleaned mode: uid, facility, uniquekey, and the date column for each type

Use exact column names as they appear in the file header.
Names not found are reported but cause no error.

When active, "_Nvars" is appended to the filter label in output filenames.

----------------------------------------------------------------------
DATASET SETTINGS (CLEANED MODE ONLY)
----------------------------------------------------------------------

The datasets list controls which dataset types are processed when
source_type = "cleaned".  Each entry has:

  include               TRUE / FALSE — whether to process this type.

  date_column           Column name to use for date filtering, or NULL for
                        no date filter on this type.  Defaults:
                          admissions: "datetimeadmission"
                          discharges: NULL  (no standard date column)
                          neolab:     "datebct" (blood culture taken date)
                          maternal:   "dateadmission"

  sub_start_date        Per-dataset date window start override ("YYYY-MM-DD").
                        When set, takes precedence over the global sub_start_date
                        for this dataset type only.  NULL = use global value.

  sub_end_date          Per-dataset date window end override ("YYYY-MM-DD").
                        When set, takes precedence over the global sub_end_date
                        for this dataset type only.  NULL = use global value.

  sub_end_date_offset_months
                        Integer.  Extends the effective end date by this many
                        calendar months AFTER any sub_end_date override is applied.
                        NULL or 0 = no extension.  Negative values are not supported.

                        Typical use: set to 1 for the discharges dataset when
                        filtering by datetimedischarge.  Babies admitted in the
                        last month of the global window may still be in the NNU at
                        the nominal end date; a 1-month extension ensures their
                        discharge records are included.  The pipeline calculates
                        the exact extended date and logs it.

                        No manual date arithmetic in the config is needed -- the
                        extension is always relative to the effective end date, so
                        the config remains correct when the global sub_end_date is
                        changed.

                        A date_window_note is auto-generated in the report if
                        sub_end_date_offset_months is set and no explicit
                        date_window_note is provided.

                        Example:
                          discharges = list(
                            include                    = TRUE,
                            date_column                = "datetimedischarge",
                            sub_end_date_offset_months = 1L,
                            sub_variables              = c(...)
                          )

  date_window_note      Optional free-text string explaining a non-standard date
                        window (e.g. why the end date was extended).  Printed in
                        the subsample report under "Date window note".
                        If NULL and sub_end_date_offset_months is set, a note is
                        generated automatically.  Set to "" to suppress the note.

  sub_variables         Column selection override for this type.
                        NULL = use global sub_variables.
                        character vector = use instead of global list.

  sub_exclusion_filters Exclusion filter override for this type.
                        list() = use global sub_exclusion_filters.
                        non-empty list = use these filters instead of global.

For the maternal type, the dataset file pattern is country-dependent:
  Zimbabwe : maternal_outcomes
  Malawi   : combined_maternity_outcomes
This is handled automatically using the country setting.


================================================================================
OUTPUTS — MASTER MODE  (source_type = "master")
================================================================================

Five files are always written per run (to output_dir):

  {prefix}_subsample_master_{label}.csv
      Subsample of master_joined: all admissions within the date/facility
      filter.  Matched rows have full discharge data; unmatched rows have NA
      discharge columns.  Use for admission-level analyses.

  {prefix}_subsample_master_extended_{label}.csv
      Subsample of master_joined_extended: same admissions, but with
      probabilistically recovered discharge data where available.
      match_type column: "direct_match", "prob_match", or "unmatched".
      Always report the match_type breakdown when using this file.

  {prefix}_subsample_master_matched_only_{label}.csv
      Direct uid+facility matched pairs only (match_type == "direct_match").
      Every row has paired discharge data.  Mirrors Pipeline 1's
      joined_admissions_discharges.  Use when only direct matches are needed.

  {prefix}_subsample_master_extended_matched_only_{label}.csv
      Direct + probabilistic matched pairs (match_type != "unmatched").
      Every row has paired discharge data.  Mirrors Pipeline 1's
      joined_admissions_discharges_extended.  Use to maximise sample size for
      outcome analyses.  Report the match_type breakdown.

  {prefix}_subsample_report_{label}.txt
      Detailed report: filter counts, column selection, facility breakdown,
      matched-only row counts, outcome distributions, output file list.

When output_na_coded = TRUE, four additional files are written alongside
the four CSVs above:

  {prefix}_subsample_master_{label}_na_coded.csv
  {prefix}_subsample_master_extended_{label}_na_coded.csv
  {prefix}_subsample_master_matched_only_{label}_na_coded.csv
  {prefix}_subsample_master_extended_matched_only_{label}_na_coded.csv

  Same rows as the standard CSVs but with NA represented as numeric
  sentinel codes.  Row positions match exactly; the files can be used
  interchangeably by switching which variant is loaded.

Filter label examples:
  to_20260228            (end date only)
  20240101_to_20260228   (both dates)
  ALL                    (no filter)
  to_20260228_SMCH       (with facility)
  to_20260228_12vars     (with column selection)

================================================================================
OUTPUTS — CLEANED MODE  (source_type = "cleaned")
================================================================================

One pair of files per enabled dataset type (written to output_dir):

  {prefix}_subsample_admissions_{label}.csv   + _report.txt
  {prefix}_subsample_discharges_{label}.csv   + _report.txt
  {prefix}_subsample_neolab_{label}.csv       + _report.txt
  {prefix}_subsample_maternal_{label}.csv     + _report.txt

Only types with include = TRUE in the datasets list are produced.
A one-line batch summary is printed at the end of the run showing each type,
its row count, and pass/fail status.

Filter label encoding is the same as master mode, but applied per dataset type
using that type's own date column.

When output_na_coded = TRUE, an additional *_na_coded.csv is written for each
enabled dataset type:

  {prefix}_subsample_admissions_{label}_na_coded.csv
  {prefix}_subsample_discharges_{label}_na_coded.csv
  etc.

  Same rows as the standard CSV but with NA as numeric sentinel codes.
  Requires matching *_cleaned_na_coded.csv files in the input/ folder.


================================================================================
WHICH FILE TO USE
================================================================================

The four CSV outputs mirror the corresponding Pipeline 1 files:

  Pipeline 2 (subsample)                        Pipeline 1 (full dataset)
  --------------------------------------------  --------------------------------
  subsample_master                              master_joined
  subsample_master_extended                     master_joined_extended
  subsample_master_matched_only                 joined_admissions_discharges
  subsample_master_extended_matched_only        joined_admissions_discharges_extended

subsample_master / subsample_master_extended
    All admissions within the date/facility filter.  Unmatched rows have NA
    discharge columns in _master; prob-matched discharge data is filled in for
    _master_extended.  Use for admission-level analyses.

subsample_master_matched_only
    Direct uid+facility matches only.  Every row has paired discharge data.
    Strictest "clean" matched set.

subsample_master_extended_matched_only
    Direct + probabilistic matches.  Every row has paired discharge data.
    Maximises sample size for outcome analyses; report match_type breakdown.


================================================================================
RELATIONSHIP TO OTHER SCRIPTS
================================================================================

run_sample_maker.R (Pipeline 1)         produces master_joined, master_joined_extended
run_subsample_maker.R (this script)     produces subsamples for specific research requests
                                          master mode: reads from Pipeline 1 outputs
                                          cleaned mode: reads from input/ directly
run_data_profiler.R                     profiles any CSV; use before configuring filters
run_subsample_user_dict.R               combines user dictionary + statistical profile
                                          into a researcher data package Excel workbook
                                          (run after this script, on its output CSVs)
run_anonymizer.R                        de-identifies any of the above for sharing


================================================================================
TROUBLESHOOTING
================================================================================

"Input file not found"
  → The script is running with the wrong SUBSAMPLE_CONFIG.
  → If using Option C (RStudio), make sure you sourced the external config
    file BEFORE sourcing run_subsample_maker.R.  If SUBSAMPLE_CONFIG is
    already set from a previous run, clear it first:
        rm(SUBSAMPLE_CONFIG)
        source("config_subsample_StudyName.R")
        source("run_subsample_maker.R", encoding = "UTF-8")
  → If editing the embedded block (Option A), check the file paths there.
  → Relative paths are resolved from the script's directory; make sure
    the working directory is set to the sample_maker_R folder.

"No rows remain after subsample filter"
  → The date/facility filter excludes all records.
  → Error message shows available date range and facilities.

"Module not found: modules/subsample_maker.R"  (master mode)
  → modules/subsample_maker.R must be in the same folder as this script.

"Module not found: modules/subsample_maker_cleaned.R"  (cleaned mode)
  → modules/subsample_maker_cleaned.R and modules/pipeline_file_resolver.R
    must be in the same folder as this script.

"No matching subdirectory found for ..."  (cleaned mode)
  → The input/ folder does not contain a matching subdirectory for the
    requested dataset type (admissions, neolab, etc.).
  → Check that the cleaning pipeline output has been copied to input/.
  → Matching is case-insensitive; underscores and hyphens in the date part
    are both accepted.

Column names in sub_variables not appearing in output:
  → Check the "not found" section of the subsample report.
  → Column names are case-sensitive.

"All enabled dataset types failed"  (cleaned mode)
  → Each type error is printed above this message.
  → Run the script with only one dataset type enabled to isolate the issue.

================================================================================
