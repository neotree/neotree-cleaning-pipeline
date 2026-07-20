#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 2: Subsample Maker
# FILE:    config_subsample_maker.R
# PURPOSE: User configuration for run_subsample_maker.R.
#          Edit this file to specify the data source, date window, facility
#          filter, exclusion filters, and column selection.
#
# TWO MODES:
#   source_type = "master"  -- create subsamples from the joined master datasets
#                              produced by run_sample_maker.R / run_all.R.
#                              This is the original mode (default).
#   source_type = "cleaned" -- create subsamples directly from cleaned files
#                              in the input/ folder, without first joining
#                              admissions to discharges.  Supports admissions,
#                              discharges, neolab, and maternal datasets.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.2  (2026-05)
################################################################################

SUBSAMPLE_CONFIG <- list(

  # ============================================================================
  # 1. SOURCE TYPE
  # ============================================================================
  #
  # "master"  -- read from master_joined / master_joined_extended files
  #              (produced by run_sample_maker.R or run_all.R).
  #              Use for analyses requiring both admission AND discharge data.
  #
  # "cleaned" -- read directly from cleaned CSV files in the input/ folder.
  #              Each enabled dataset type produces one output CSV.
  #              Use when you only need one dataset, or when you want to share
  #              a data package covering multiple dataset types (admissions +
  #              neolab, for example) without running the join pipeline.
  #
  source_type = "master",   # "master" or "cleaned"

  # ============================================================================
  # 2a. MASTER SOURCE SETTINGS  (source_type = "master")
  # ============================================================================
  #
  # Full or relative paths to the master_joined and master_joined_extended CSV
  # files produced by run_all.R (Pipeline 1).
  # Relative paths are resolved from the directory of run_subsample_maker.R.
  #
  # Paths follow the run_all.R output convention:
  #   outputs/{country}_master/{source}/{PREFIX}_master_joined_{label}.csv
  #
  # Examples:
  #   "outputs/zim_master/from_database/ZIM_db_master_joined_to_20260401.csv"
  #   "outputs/mwi_master/from_database/MWI_db_master_joined_to_20260401.csv"
  #
  master_joined_file          = "outputs/zim_master/from_database/ZIM_db_master_joined_to_YYYYMMDD.csv",
  master_joined_extended_file = "outputs/zim_master/from_database/ZIM_db_master_joined_extended_to_YYYYMMDD.csv",

  # ============================================================================
  # 2b. CLEANED SOURCE SETTINGS  (source_type = "cleaned")
  # ============================================================================
  #
  # Set cleaning_pipeline_output_dir to the input/ folder (same folder used by
  # run_all.R).  The script will auto-resolve each enabled dataset type.
  # Matching is case-insensitive.
  #
  cleaning_pipeline_output_dir = "input",   # relative to script; or absolute path
  country = "zim",                          # "zim" or "mwi"
  source  = "from_metabase",                # "from_database" or "from_metabase"

  # ============================================================================
  # 2c. NA-CODED DUAL OUTPUT  (source_type = "cleaned" only)
  # ============================================================================
  #
  # FALSE (default) -- write only the standard blank-NA subsample CSV.
  # TRUE            -- also write a paired *_na_coded.csv for each enabled
  #                    dataset type.  The na_coded file contains the same rows
  #                    as the standard output but with NA values represented as
  #                    numeric sentinel codes (-7, -8, -9, etc.) exactly as in
  #                    the cleaning pipeline's *_cleaned_na_coded.csv source.
  #                    Row selection is driven by the blank-NA file so that
  #                    filter logic (date, facility, exclusions) always operates
  #                    on clean NA values rather than sentinel codes.
  #
  #   Output:  {prefix}_subsample_{type}_{label}.csv         (blank NA)
  #            {prefix}_subsample_{type}_{label}_na_coded.csv (sentinel NA)
  #
  output_na_coded = TRUE,

  # ============================================================================
  # 3. OUTPUT DIRECTORY
  # ============================================================================
  #
  # NULL  -> "subsamples/" folder next to this script (both modes).
  # Or provide an explicit path (absolute paths are most reliable).
  # The directory is created automatically if it does not exist.
  #
  output_dir = NULL,

  # ============================================================================
  # 4. GLOBAL DATE WINDOW
  # ============================================================================
  #
  # Applied to ALL dataset types in cleaned mode, and to the master file in
  # master mode.  For cleaned mode, each dataset type uses its own date column
  # (see Section 6 below) but the same date boundaries.
  #
  # sub_start_date / sub_end_date : "YYYY-MM-DD" or NULL (no bound).
  # Both NULL -> no date filter (full dataset used).
  #
  sub_start_date = "2024-01-01",   # "YYYY-MM-DD" or NULL
  sub_end_date   = "2026-02-28",   # "YYYY-MM-DD" or NULL

  # ============================================================================
  # 5. GLOBAL FACILITY FILTER
  # ============================================================================
  #
  # NULL              -> all facilities
  # "SMCH"            -> one facility only
  # c("SMCH", "BPH")  -> multiple facilities
  #
  # Ignored when sub_use_advanced_mode = TRUE (see below).
  #
  sub_facility_filter = NULL,

  # ============================================================================
  # 5b. ADVANCED MODE: per-facility date ranges
  # ============================================================================
  #
  # Use when different facilities need different date windows.
  # When sub_use_advanced_mode = TRUE, sections 4 and 5 above are IGNORED.
  # Each entry: c("FACILITY_NAME", "start_date", "end_date")
  #
  sub_use_advanced_mode    = FALSE,
  sub_facility_date_ranges = list(
    # c("SMCH", "2023-01-01", "2024-12-31"),
    # c("BPH",  "2024-01-01", "2024-12-31")
  ),

  # ============================================================================
  # 6. GLOBAL EXCLUSION FILTERS
  # ============================================================================
  #
  # Remove records where a variable meets a condition.
  # Applied after the date/facility filter, before column selection.
  # Rows where the filter variable is NA are KEPT (conservative default).
  #
  # These global filters apply to ALL enabled datasets in cleaned mode
  # (where the variable exists), and to the master file in master mode.
  # Per-dataset overrides can be set in Section 7 below.
  #
  # Format: list of entries with variable, operator, value.
  # Operators: "<", "<=", ">", ">=", "==", "!=", "in", "not_in"
  #
  sub_exclusion_filters = list(
    # list(variable = "gestation",      operator = "<",   value = 24),
    # list(variable = "birthweight",    operator = "<",   value = 400),
    # list(variable = "neotreeoutcome", operator = "in",  value = c("LAMA", "Absconded"))
  ),

  # ============================================================================
  # 7. GLOBAL COLUMN SELECTION
  # ============================================================================
  #
  # NULL   -> keep ALL columns (default).
  # vector -> keep only the listed variables plus the mandatory set for each
  #           dataset type (uid, facility, uniquekey, and the date column).
  #
  # Per-dataset column selections can be set in Section 8 below.
  # Per-dataset settings override this global setting.
  #
  # MASTER MODE mandatory columns (always kept):
  #   uid, facility, uniquekey, datetimeadmission, match_key, adm_date_parsed,
  #   match_type, prob_match_similarity
  #
  sub_variables = NULL,

  # ============================================================================
  # 8. DATASET SETTINGS  (source_type = "cleaned" only)
  # ============================================================================
  #
  # Controls which dataset types are included and allows per-type overrides
  # for date column, column selection, and exclusion filters.
  #
  # For each type:
  #   include               TRUE / FALSE
  #   date_column           Column name to use for date filtering, or NULL for
  #                         no date filter on this dataset.
  #   sub_variables         Column selection override for this type.
  #                         NULL = use global sub_variables.
  #                         character vector = use this list instead.
  #   sub_exclusion_filters Exclusion filter override for this type.
  #                         list() = use global sub_exclusion_filters.
  #                         non-empty list = use these instead of global filters.
  #
  # COUNTRY NOTE for maternal:
  #   Zimbabwe : dataset_type = "maternal_outcomes"    (auto-detected from country)
  #   Malawi   : dataset_type = "combined_maternity_outcomes"
  #
  datasets = list(

    admissions = list(
      include               = TRUE,
      date_column           = "datetimeadmission",   # admission datetime
      sub_variables         = NULL,   # NULL = use global sub_variables
      sub_exclusion_filters = list()  # empty = use global sub_exclusion_filters
      # Example:
      # sub_variables = c(
      #   "datetimeadmission", "facility", "birthweight", "gestation",
      #   "gender", "ofc", "temperature", "apgar1", "apgar5",
      #   "modedelivery", "typebirth", "methodestgest"
      # )
    ),

    discharges = list(
      include               = FALSE,  # default off: discharges are normally used joined
      date_column           = NULL,   # no standard date column for discharges
      sub_variables         = NULL,
      sub_exclusion_filters = list()
    ),

    neolab = list(
      include               = FALSE,
      date_column           = "datebct",   # blood culture taken date
      # date_column = "datebcr"            # alternative: result date
      sub_variables         = NULL,
      sub_exclusion_filters = list()
      # Example — positive FINAL cultures only:
      # sub_exclusion_filters = list(
      #   list(variable = "bcresult", operator = "==", value = "Pos"),
      #   list(variable = "bctype",   operator = "==", value = "FINAL")
      # )
    ),

    maternal = list(
      include               = FALSE,
      date_column           = "dateadmission",
      sub_variables         = NULL,
      sub_exclusion_filters = list()
      # Example — live births only:
      # sub_exclusion_filters = list(
      #   list(variable = "neotreeoutcome", operator = "not_in",
      #        value = c("SB", "MSB", "FD"))
      # )
    )

  )

)
