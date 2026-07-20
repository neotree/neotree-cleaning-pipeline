================================================================================
  Neotree Sample Maker
  README: config_sample_maker.R — Configuration for Pipeline 1 (run_sample_maker.R)
================================================================================

OVERVIEW
--------
config_sample_maker.R is the configuration file for run_sample_maker.R
(Pipeline 1, single country/source pair).  It defines a CONFIG list with
four sections: data selection, admission date window, paths, and probabilistic
matching settings.

================================================================================
WHEN TO USE THIS FILE
================================================================================

  DEFAULT WORKFLOW — use run_all.R (no config needed):
    For most work, run run_all.R instead of this file.  run_all.R automatically
    discovers ALL datasets in the input/ folder and processes every
    admissions+discharges pair in a single command.  Neolab, maternal, and all
    other standalone dataset types are skipped and handled by run_subsample_maker.R.
    No config editing is required.

      Rscript run_all.R

  SINGLE-PAIR WORKFLOW — use this file + run_sample_maker.R:
    Edit config_sample_maker.R only when you need to (re-)process a specific
    country/source combination without running everything else.  Examples:
      - You want to reprocess only Zimbabwe database data after a new extract.
      - You need a non-default date window for one country/source pair.
      - You want to pass a custom config as a command-line argument:
          Rscript run_sample_maker.R /path/to/my_config.R

    In all other cases, use run_all.R.

================================================================================

Pipeline 1 is designed to produce complete master datasets covering all
facilities and all historical data.  Filtering for specific research requests
(date ranges, facilities, variable sub-populations) is handled separately by
the subsample makers — copy config_subsample_TEMPLATE.R and run
run_subsample_maker.R for that purpose.


================================================================================
SECTION 1 — DATA SELECTION
================================================================================

Input files come from the cleaning pipeline output/ folder, copied and renamed
to input/ in the sample_maker_R/ directory.

  cleaning_pipeline_output_dir  Path to the input/ folder.
                                Default: "input" (relative to the script).
                                Can also be an absolute path.

  country   "zim"  (Zimbabwe)
            "mwi"  (Malawi)

  source    "from_database"  — files extracted directly from the Neotree DB
            "from_metabase"  — files downloaded from Metabase reports

The script auto-discovers the matching admissions and discharges subdirectories
inside the folder.  Directory and file name matching is case-insensitive, so
Title Case Metabase folder names (e.g. mwi_mb_Combined_Maternity_Outcomes_...)
are found correctly.  If multiple data cuts of the same dataset are present,
the most recently modified is used and a warning is printed.

Output file prefix:  {COUNTRY}_{src}     e.g. ZIM_db, MWI_mb


================================================================================
SECTION 2 — ADMISSION DATE WINDOW
================================================================================

Because some babies are still admitted at the time the data is extracted,
selecting admissions right up to the data cut-off would inflate the
"unmatched admissions" count with babies who simply haven't been discharged yet.

  use_advanced_mode   FALSE (default) or TRUE

  FALSE — SIMPLE MODE: one global date window applied to all facilities.
  TRUE  — ADVANCED MODE: per-facility date ranges defined in
          facility_date_ranges (a list of c("FACILITY", "start", "end")
          vectors).  Use when facilities have different data cut-off dates.

  adm_start_date   "YYYY-MM-DD" or NULL  (simple mode only)
  adm_end_date     "YYYY-MM-DD" or NULL  (simple mode only)

AUTO MODE (recommended — set both to NULL, use_advanced_mode = FALSE):
  adm_end_date is computed automatically as:
      (most recent datetimeadmission in file) − 1 calendar month
  adm_start_date = NULL means no lower bound (all historical data).

  The month subtraction uses seq(max_date, by="-1 month", length.out=2)[2],
  which correctly handles month-end edge cases (e.g. 31 March → 28 Feb).

MANUAL MODE — provide explicit dates to override:
  adm_start_date = "2022-01-01"   # admit from this date (inclusive)
  adm_end_date   = "2026-02-28"   # admit up to this date (inclusive, 23:59:59)

IMPORTANT — Discharges are NEVER date-filtered.  All discharge records are
used so that babies admitted up to adm_end_date have the best possible chance
of finding a matching discharge.

NOTE — For analyses requiring a specific date range, facility subset, or
clinical sub-population, do not set those filters here.  Run Pipeline 1 once
to build the full master dataset, then use the subsample maker to create the
specific extract.


================================================================================
SECTION 3 — PATHS
================================================================================

  cleaning_pipeline_output_dir  Path to the input/ folder.
                                Default: "input" (relative to the script).

  output_dir          Root of the outputs folder.
                      The pipeline creates subdirectories automatically:
                        outputs/{country}_master/{source}/
                        e.g. outputs/zim_master/from_database/
                      Default: "outputs"


================================================================================
SECTION 4 — PROBABILISTIC MATCHING
================================================================================

After the direct uid+facility join, unmatched admissions are compared to
unmatched discharges using shared clinical variables.  See
modules/README_prob_matcher.txt for a full explanation of the algorithm.

Core settings:

  prob_match_min_similarity          Minimum overall score (0–100) for a pair
                                     to be a candidate.
                                     Default: 100
                                     At 100, only pairs where every available
                                     variable matches exactly (within tolerance)
                                     are accepted — highest precision, lowest
                                     false-match rate.
                                     Lower to 90–95 for slightly higher recall
                                     at the cost of some false positives.

  prob_match_max_candidates          Maximum candidates reported per unmatched
                                     admission in the investigation report.
                                     Default: 5
                                     Does not affect the accepted assignments.

  prob_match_completeness_threshold  Minimum proportion of non-NA values (0–1)
                                     for a variable to be used in matching.
                                     Assessed on the full files, not just the
                                     unmatched subsets.
                                     Default: 0.3

  prob_match_cross_facility          If TRUE, admissions that find no candidate
                                     within their own facility are searched
                                     against all unmatched discharges.
                                     Catches facility name mismatches.
                                     Can be slow on large datasets.
                                     Default: FALSE

Per-variable numeric tolerances (linear decay):

  prob_match_birthweight_tolerance   grams       Default: 20
                                     NOTE: birthweight is stored in grams in the
                                     cleaned Neotree data.  The tolerance must
                                     be expressed in grams to match data units.
                                     20 g allows minor scale/rounding variation.
  prob_match_gestation_tolerance     weeks       Default: 0  (exact)
  prob_match_ofc_tolerance           cm          Default: 0.5
  prob_match_temperature_tolerance   °C          Default: 0.1
  prob_match_apgar1_tolerance        score       Default: 0  (exact)
  prob_match_apgar5_tolerance        score       Default: 0  (exact)
  prob_match_apgar10_tolerance       score       Default: 0  (exact)

A tolerance of 0 means exact-match-only for that variable.
A tolerance of T means a difference of T scores 50 (halfway to zero).
A difference of 2×T scores 0.


================================================================================
SECTION 5 — NA-CODED OUTPUT
================================================================================

  output_na_coded   TRUE (default) or FALSE

  TRUE  — also writes *_na_coded.csv variants of master_joined and
          master_joined_extended alongside the standard blank-NA files.
          These files contain the same rows and columns, but NA values are
          represented as numeric sentinel codes (-7, -8, -9, etc.) exactly as
          they appear in the cleaning pipeline's *_cleaned_na_coded.csv sources.

          NA codes distinguish between different types of missingness (e.g.
          "not asked", "not answered", "not applicable").  These distinctions
          are needed when training machine learning models.

          Requires that the cleaning pipeline produced *_cleaned_na_coded.csv
          files alongside the standard *_cleaned.csv files in the input/ folder.
          If the na_coded source files are not found, the pipeline continues
          normally and emits a warning (no error).

  FALSE — writes only the standard blank-NA master files.

  Output files (written alongside the standard master files):
    {prefix}_master_joined_{label}_na_coded.csv
    {prefix}_master_joined_extended_{label}_na_coded.csv


================================================================================
QUICK REFERENCE — COMMON CONFIGURATIONS
================================================================================

REMINDER: For batch processing all datasets at once, use run_all.R.
This file is only needed when running a single country/source pair manually.

Standard run (Zimbabwe database, auto date window):
  country      = "zim"
  source       = "from_database"
  adm_start_date = NULL
  adm_end_date   = NULL

Malawi Metabase run:
  country = "mwi"
  source  = "from_metabase"

Explicit date range (e.g. a defined study period):
  adm_start_date = "2022-01-01"
  adm_end_date   = "2025-12-31"

Maximum-precision probabilistic matching (default — recommended):
  prob_match_min_similarity        = 100
  prob_match_birthweight_tolerance = 20   # grams

Slightly more permissive matching (higher recall, some false positives):
  prob_match_min_similarity        = 95
  prob_match_birthweight_tolerance = 50   # grams

For facility filtering, variable sub-populations, or column selection:
  → Copy config_subsample_TEMPLATE.R, fill in the settings, and run
    run_subsample_maker.R with that config file.

================================================================================
