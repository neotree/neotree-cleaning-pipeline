================================================================================
  Neotree Sample Maker
  README: Subsample config files — Configuration for Pipeline 2
================================================================================

OVERVIEW — CONFIG FILE SYSTEM
------------------------------
Each data access request gets its own pair of config files (one per mode).
There are three tiers:

  TIER 1: TEMPLATES — DO NOT EDIT; copy instead
  -----------------------------------------------
  config_subsample_TEMPLATE.R
      Full annotated reference with every option documented.  Read this to
      understand any setting.  Do not edit or rename it.

  config_subsample_master_TEMPLATE.R
      Lean fill-in-the-blanks template for a MASTER MODE request
      (admissions linked to discharges, from the Pipeline 1 joined files).
      Copy and rename for each new data access request.

  config_subsample_cleaned_TEMPLATE.R
      Lean fill-in-the-blanks template for a CLEANED MODE request
      (standalone per-type files: admissions, discharges, neolab, maternal).
      Copy and rename for each new data access request.

  TIER 2: REQUEST CONFIGS — one pair per researcher
  --------------------------------------------------
  config_subsample_{Researcher}_{Study}_Nvars.R      (master mode)
  config_subsample_{Researcher}_{Study}_cleaned.R    (cleaned mode)

      Created by copying and renaming the appropriate TEMPLATE.  Fill in
      the date window, facility, variable list, and paths, then run:

        Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_Nvars.R
        Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_cleaned.R

      Both configs should write outputs to the SAME output_dir so that
      run_subsample_user_dict.R can auto-discover all files in one pass.

  TIER 3: DEFAULT / EMBEDDED CONFIG
  -----------------------------------
  config_subsample_maker.R  (and the embedded block in run_subsample_maker.R)
      Used for ad-hoc testing or when no external config is needed.

  WHICH MODE TO USE
  -----------------
  master mode   → researcher needs admission AND discharge data linked together;
                  the primary analysis dataset for most requests.
  cleaned mode  → researcher also needs standalone per-type files (e.g. for
                  DSH upload), or needs neolab/maternal records; run alongside
                  the master mode config and write to the same output_dir.

For a typical data access request, create BOTH a master config AND a cleaned
config and run them in sequence.  See the config_subsample_*_TEMPLATE.R files for examples.


================================================================================
SECTION 1 — INPUT FILES
================================================================================

  master_joined_file
      Path to the master_joined CSV produced by run_sample_maker.R.
      Can be relative (resolved from the run_subsample_maker.R directory)
      or absolute.

  master_joined_extended_file
      Path to the master_joined_extended CSV produced by run_sample_maker.R.

Example:
  master_joined_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_to_20260228.csv"
  master_joined_extended_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_extended_to_20260228.csv"

The file prefix used in all output names (e.g. "ZIM_db") is derived
automatically from the master_joined filename — you do not need to set it.


================================================================================
SECTION 2 — OUTPUT DIRECTORY
================================================================================

  output_dir   Path string or NULL

  NULL  → outputs go to "subsamples/" next to run_subsample_maker.R
          (the same unified subsamples folder for both master and cleaned mode).
  Or provide an explicit path: "subsamples/my_study" or an absolute path.

The directory is created automatically if it does not exist.


================================================================================
SECTION 2c — NA-CODED DUAL OUTPUT
================================================================================

  output_na_coded   TRUE or FALSE  (default FALSE)

  FALSE  → write only the standard blank-NA subsample CSVs (default).
  TRUE   → also write a paired *_na_coded.csv alongside each standard CSV.
           The na_coded files contain the same rows but with NA values as
           numeric sentinel codes (-7, -8, -9, etc.) matching the source
           *_cleaned_na_coded.csv (cleaned mode) or master_joined_na_coded.csv
           (master mode) produced by the cleaning/joining pipeline.

Row selection always operates on the blank-NA file.  The na_coded file has
the same rows extracted by position, so filter logic never touches sentinel codes.

Requires that the matching na_coded source file(s) exist:
  master mode  : {master_joined_file without .csv}_na_coded.csv  (auto-derived)
  cleaned mode : *_cleaned_na_coded.csv files in cleaning_pipeline_output_dir


================================================================================
SECTION 3 — ADMISSION DATE WINDOW
================================================================================

  sub_start_date   "YYYY-MM-DD" or NULL (no lower bound)
  sub_end_date     "YYYY-MM-DD" or NULL (no upper bound)

The filter applies to the datetimeadmission column in the master datasets.
Discharge data already joined to a kept admission is retained regardless of
when the discharge occurred.

Both NULL → no date filter; the full master datasets are passed through
(column selection in Section 6 still applies if configured).

Examples:
  sub_start_date = "2024-01-01"   # keep admissions from 1 Jan 2024
  sub_end_date   = "2026-02-28"   # keep admissions up to 28 Feb 2026 (23:59:59)

  sub_start_date = NULL           # no lower bound
  sub_end_date   = "2025-12-31"   # keep all admissions up to end of 2025

Filter label in output filenames:
  Both set:   "20240101_to_20260228"
  End only:   "to_20260228"
  Start only: "from_20240101"
  Neither:    "ALL"


================================================================================
SECTION 4 — FACILITY FILTER  (simple mode)
================================================================================

  sub_facility_filter   NULL, a single string, or a character vector

  NULL              → all facilities included (default)
  "SMCH"            → one facility only
  c("SMCH", "BPH")  → multiple facilities

Applied to admissions only (after date filtering).  Discharge data for kept
admissions is retained regardless of facility.

This setting is ignored when sub_use_advanced_mode = TRUE (see Section 5).

When a facility filter is active, the facility name is appended to the filter
label in output filenames, e.g. "to_20260228_SMCH".


================================================================================
SECTION 5 — ADVANCED MODE: per-facility date ranges
================================================================================

  sub_use_advanced_mode      TRUE or FALSE
  sub_facility_date_ranges   list of c("FACILITY", "start_date", "end_date")

Use when different facilities need different date windows (e.g. different
Neotree deployment dates, or known data-quality gaps at specific sites).

When sub_use_advanced_mode = TRUE, Sections 3 and 4 above are COMPLETELY IGNORED.

Each entry must have exactly three elements: facility name, start date (YYYY-MM-DD),
end date (YYYY-MM-DD).

Example:
  sub_use_advanced_mode = TRUE,
  sub_facility_date_ranges = list(
    c("SMCH", "2023-01-01", "2024-12-31"),
    c("BPH",  "2024-01-01", "2024-12-31")
  )

The filter label is built from the earliest start, latest end, and all
facility names joined with underscores.


================================================================================
SECTION 6 — EXCLUSION FILTERS
================================================================================

  sub_exclusion_filters   empty list() or a list of filter entries

  list()  -> no exclusion (default).
  list of entries -> records matching any entry are removed.

Applied after the date/facility filter, before column selection.
Rows where the filter variable is NA are KEPT (conservative default).
Both master_joined and master_joined_extended are filtered identically.

Each filter entry is a list with three named fields:

  variable  -- exact column name as it appears in the master file
  operator  -- one of: "<", "<=", ">", ">=", "==", "!=", "in", "not_in"
  value     -- a single value, or a character/numeric vector for "in"/"not_in"

Multiple entries are all applied in sequence (a row is removed if it matches
ANY single filter).

When filters are active, "_excl" is appended to the output label so that
filtered and unfiltered subsamples are clearly distinguished.

The subsample report (section [4b]) shows exactly how many rows each filter
removed.

Numeric coercion is applied automatically: if value is numeric, the column
is coerced to numeric before comparison (handles CSV round-trip where numeric
columns may be stored as strings).

FINDING VALID VARIABLE NAMES AND RANGES
  Use the data profiler utility (run_data_profiler.R) to produce a variable
  summary CSV from any master file.  It shows variable names, types, and
  descriptive statistics (min, max, mean, median, mode) so you can set
  thresholds without having to open the data file directly.

Examples:

  Remove newborns with gestational age < 24 weeks:
    list(variable = "gestation", operator = "<", value = 24)

  Remove records with birthweight below 400 g:
    list(variable = "birthweight", operator = "<", value = 400)

  Remove a specific outcome category:
    list(variable = "neotreeoutcome", operator = "==", value = "LAMA")

  Combine multiple conditions:
    sub_exclusion_filters = list(
      list(variable = "gestation",      operator = "<",  value = 24),
      list(variable = "birthweight",    operator = "<",  value = 400)
    )


================================================================================
SECTION 7 — COLUMN SELECTION
================================================================================

  sub_variables   NULL or a character vector of column names

  NULL   -> keep ALL columns (default).
  vector -> keep only the listed columns, plus the following mandatory columns
           that are always retained regardless of this setting:
             uid, facility, uniquekey, datetimeadmission, match_key,
             adm_date_parsed, match_type, prob_match_similarity

Column names must match exactly as they appear in the master file header.
Column names listed that are not found in the input file are reported in
the output report under "not found" but do not cause an error.

When column selection is active, the number of selected variables is appended
to the filter label in output filenames (e.g. "to_20260228_12vars"), so that
full-column and restricted subsamples are clearly distinguished.

Example -- lean outcome analysis set (12 variables + mandatory cols):
  sub_variables = c(
    "birthweight", "gestation", "gender", "ofc",
    "temperature", "apgar1", "apgar5",
    "modedelivery", "typebirth",
    "neotreeoutcome", "datetimedischarge", "dischweight"
  )

Example -- keep everything (no column restriction):
  sub_variables = NULL


================================================================================
OUTPUT FILE NAMING
================================================================================

Output filenames are built as:
    {prefix}_{type}_{label}.{ext}

  prefix   Derived from master_joined filename:
           "ZIM_db_master_joined_to_20260228.csv" -> "ZIM_db"

  type     "subsample_master", "subsample_master_extended",
           "subsample_master_matched_only",
           "subsample_master_extended_matched_only", or "subsample_report"

  label    Encodes the date window, facility, exclusions, and column selection:
           "to_20260228"                       (end date only, no extras)
           "20240101_to_20260228"              (both dates)
           "20240101_to_20260228_SMCH"         (both dates, one facility)
           "to_20260228_excl"                  (with exclusion filters)
           "to_20260228_excl_12vars"           (exclusions + column selection)
           "ALL"                               (no filter, all cols)

Examples (the four CSVs always produced together):
  ZIM_db_subsample_master_20240101_to_20260228_excl.csv
  ZIM_db_subsample_master_extended_20240101_to_20260228_excl.csv
  ZIM_db_subsample_master_matched_only_20240101_to_20260228_excl.csv
  ZIM_db_subsample_master_extended_matched_only_20240101_to_20260228_excl.csv
  ZIM_db_subsample_report_20240101_to_20260228_excl.txt

When output_na_coded = TRUE, four additional na_coded CSVs are written:
  ZIM_db_subsample_master_20240101_to_20260228_excl_na_coded.csv
  ZIM_db_subsample_master_extended_20240101_to_20260228_excl_na_coded.csv
  ZIM_db_subsample_master_matched_only_20240101_to_20260228_excl_na_coded.csv
  ZIM_db_subsample_master_extended_matched_only_20240101_to_20260228_excl_na_coded.csv


================================================================================
QUICK REFERENCE — COMMON CONFIGURATIONS
================================================================================

Standard date window, all facilities, all columns:
  sub_start_date        = "2024-01-01"
  sub_end_date          = "2026-02-28"
  sub_facility_filter   = NULL
  sub_use_advanced_mode = FALSE
  sub_exclusion_filters = list()
  sub_variables         = NULL

Single facility, restricted columns:
  sub_start_date        = "2024-01-01"
  sub_end_date          = "2026-02-28"
  sub_facility_filter   = "SMCH"
  sub_exclusion_filters = list()
  sub_variables         = c("birthweight", "gestation", "gender",
                            "neotreeoutcome", "datetimedischarge")

Date window with gestational age exclusion:
  sub_start_date        = "2024-01-01"
  sub_end_date          = "2026-02-28"
  sub_exclusion_filters = list(
    list(variable = "gestation", operator = "<", value = 24)
  )
  sub_variables         = NULL

Full dataset, no date filter, column selection only:
  sub_start_date        = NULL
  sub_end_date          = NULL
  sub_facility_filter   = NULL
  sub_exclusion_filters = list()
  sub_variables         = c("birthweight", "gestation", "neotreeoutcome")

Per-facility windows (advanced mode):
  sub_use_advanced_mode = TRUE
  sub_facility_date_ranges = list(
    c("SMCH", "2022-03-01", "2026-02-28"),
    c("BPH",  "2023-09-01", "2026-02-28")
  )
  sub_exclusion_filters = list()
  sub_variables         = NULL

In all cases, the four subsample CSVs are produced automatically.
No extra configuration is needed for the matched-only files.


================================================================================
RELATIONSHIP TO OTHER CONFIG FILES
================================================================================

config_sample_maker.R              → used by run_sample_maker.R (Pipeline 1, single pair)
config_subsample_master_TEMPLATE.R → copy for each master mode data request
config_subsample_cleaned_TEMPLATE.R→ copy for each cleaned mode data request
config_subsample_TEMPLATE.R        → full reference documentation for all options
config_subsample_maker.R           → default/embedded config for ad-hoc use

The subsample configs are completely independent of config_sample_maker.R.
They only need paths to the master output files (master mode) or the input/
folder (cleaned mode) — no country, source, or matching settings required.

================================================================================
