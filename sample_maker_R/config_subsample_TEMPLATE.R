#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 2: Subsample Maker
# FILE:    config_subsample_TEMPLATE.R
# PURPOSE: Annotated template for run_subsample_maker.R.
#          Copy this file, rename it, and fill in the fields for the specific
#          data access request.
#
#          TWO MODES:
#            source_type = "master"   Subsample from the master joined files
#                                     produced by Pipeline 1 (run_sample_maker.R).
#                                     Admissions and discharges are already linked.
#                                     Use as the primary analysis dataset.
#
#            source_type = "cleaned"  Subsample directly from the per-type
#                                     cleaned CSV files in the input/ folder.
#                                     Produces one output CSV per enabled dataset
#                                     type (admissions, discharges, neolab,
#                                     maternal).  Use when you need standalone
#                                     datasets or a multi-type data package.
#
#          For a typical data access request, run BOTH configs:
#            1. A master config  (source_type = "master")  -- primary joined dataset
#            2. A cleaned config (source_type = "cleaned") -- standalone per-type files
#          Both configs should write their outputs to the SAME output_dir so that
#          run_subsample_user_dict.R can auto-discover all files in one pass.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.2  (2026-05)
#
# Usage (from sample_maker_R directory):
#   Rscript run_subsample_maker.R /path/to/this_config.R
################################################################################

SUBSAMPLE_CONFIG <- list(

  # ============================================================================
  # 1. SOURCE TYPE
  # ============================================================================
  #
  # "master"  -- reads master_joined / master_joined_extended (Pipeline 1 output).
  #              Sections 2a apply; sections 2b and 8 (datasets) are ignored.
  #
  # "cleaned" -- reads per-type cleaned CSVs from the input/ folder.
  #              Sections 2b and 8 apply; section 2a is ignored.
  #
  source_type = "master",   # "master" or "cleaned"

  # ============================================================================
  # 2a. MASTER SOURCE SETTINGS  (used when source_type = "master")
  # ============================================================================
  #
  # Full or relative paths to the Pipeline 1 master joined files.
  # Relative paths are resolved from the directory of run_subsample_maker.R.
  #
  # Example paths:
  #   "outputs/zim_master/from_database/ZIM_db_master_joined_to_20260401.csv"
  #   "outputs/mwi_master/from_metabase/MWI_mb_master_joined_to_20260401.csv"
  #
  master_joined_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_to_20260401.csv",

  master_joined_extended_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_extended_to_20260401.csv",

  # ============================================================================
  # 2b. CLEANED SOURCE SETTINGS  (used when source_type = "cleaned")
  # ============================================================================
  #
  # cleaning_pipeline_output_dir : path to the input/ folder (relative to the
  #   script or absolute).  Each enabled dataset type is auto-resolved from
  #   subdirectories named {country}_{source}_{type}_{date}/.
  # country : "zim" or "mwi"
  # source  : "from_database" or "from_metabase"
  #
  cleaning_pipeline_output_dir = "input",
  country = "zim",            # "zim" | "mwi"
  source  = "from_database",  # "from_database" | "from_metabase"

  # ============================================================================
  # 3. OUTPUT DIRECTORY
  # ============================================================================
  #
  # NULL  -> default location:
  #   master mode : same directory as master_joined_file
  #   cleaned mode: subsamples/{country}_{source}/ relative to the script
  #
  # Recommended: use an explicit shared directory so both master and cleaned
  # configs write to the same folder, enabling auto-discovery by the dict script.
  # Create a subdirectory per researcher.
  #
  # Example: "outputs/zim_master/from_database/subsamples/researcher_name"
  #
  output_dir = NULL,   # or "outputs/zim_master/from_database/subsamples/researcher_name"

  # ============================================================================
  # 4. GLOBAL DATE WINDOW
  # ============================================================================
  #
  # Applied to the master file (master mode) or to each enabled dataset type via
  # its date_column (cleaned mode).
  #
  # "YYYY-MM-DD" string or NULL (no bound).
  # Both NULL -> no date filter; the full dataset is used.
  #
  # In cleaned mode the same window applies to all dataset types unless a
  # per-dataset sub_start_date / sub_end_date / sub_end_date_offset_months
  # override is set in Section 8.
  #
  sub_start_date = "2024-01-01",   # "YYYY-MM-DD" or NULL
  sub_end_date   = "2024-12-31",   # "YYYY-MM-DD" or NULL

  # ============================================================================
  # 5. GLOBAL FACILITY FILTER
  # ============================================================================
  #
  # NULL              -> include all facilities
  # "SMCH"            -> single facility
  # c("SMCH", "BPH")  -> multiple facilities
  #
  # Ignored when sub_use_advanced_mode = TRUE (see Section 5b).
  #
  sub_facility_filter = NULL,

  # ============================================================================
  # 5b. ADVANCED MODE: per-facility date ranges
  # ============================================================================
  #
  # Use when different facilities require different date windows.
  # When sub_use_advanced_mode = TRUE, Sections 4 and 5 are IGNORED.
  # Format: list of c("FACILITY_NAME", "start_date", "end_date").
  # Use NA for an open bound.
  #
  sub_use_advanced_mode    = FALSE,
  sub_facility_date_ranges = list(
    # c("SMCH", "2023-01-01", "2024-12-31"),
    # c("BPH",  "2024-01-01", "2024-12-31"),
    # c("SBH",  NA,           "2024-06-30")   # NA = open lower bound
  ),

  # ============================================================================
  # 6. GLOBAL EXCLUSION FILTERS
  # ============================================================================
  #
  # Removes records matching the condition, AFTER the date/facility filter
  # and BEFORE column selection.  Records where the filter variable is NA
  # are KEPT (conservative default).
  #
  # Applied to ALL enabled dataset types (where the column exists) in cleaned
  # mode, and to the master file in master mode.  Per-dataset overrides can
  # be set in Section 8.
  #
  # Supported operators: "<" "<=" ">" ">=" "==" "!=" "in" "not_in"
  # For boolean columns use: operator = "==", value = TRUE / FALSE
  #
  sub_exclusion_filters = list(
    # list(variable = "gestation",      operator = "<",      value = 24),
    # list(variable = "birthweight",    operator = "<",      value = 400),
    # list(variable = "multiplicity",   operator = "==",     value = TRUE),
    # list(variable = "neotreeoutcome", operator = "in",     value = c("LAMA", "Absconded")),
    # list(variable = "gender",         operator = "not_in", value = c("NK", "NR"))
  ),

  # ============================================================================
  # 7. GLOBAL COLUMN SELECTION
  # ============================================================================
  #
  # NULL   -> retain ALL columns (default).
  # vector -> retain only the listed variables plus the mandatory set.
  #
  # Mandatory columns are always kept regardless of this setting:
  #   master mode  : uid, facility, uniquekey, datetimeadmission,
  #                  match_key, adm_date_parsed, match_type, prob_match_similarity
  #   cleaned mode : uid, facility, uniquekey, and the date column for each type
  #
  # Per-dataset column selections set in Section 8 override this global setting.
  #
  sub_variables = NULL,   # NULL = all columns; or c("age", "gestation", ...)

  # ============================================================================
  # 8. DATASET SETTINGS  (source_type = "cleaned" only)
  # ============================================================================
  #
  # One entry per dataset type.  Each entry supports:
  #
  #   include
  #       TRUE / FALSE -- whether to process this type.
  #
  #   date_column
  #       Column name for date filtering, or NULL for no date filter.
  #       Typical values:
  #         admissions: "datetimeadmission"
  #         discharges: "datetimedischarge"  (preferred -- see note below)
  #         neolab:     "datebct"            (blood culture taken date)
  #         maternal:   "dateadmission"
  #
  #       DISCHARGES DATE NOTE:
  #         datetimeadmission is re-entered manually on the discharge form
  #         and is typically ~44% blank at SMCH.  Use datetimedischarge instead,
  #         combined with sub_end_date_offset_months = 1 (see below), to capture
  #         babies admitted at the end of the global window who are discharged
  #         one month later.  Link to the admitted cohort within the DSH using uid.
  #
  #   sub_start_date
  #       "YYYY-MM-DD" or NULL.
  #       Overrides the global sub_start_date for this dataset type only.
  #
  #   sub_end_date
  #       "YYYY-MM-DD" or NULL.
  #       Overrides the global sub_end_date for this dataset type only.
  #
  #   sub_end_date_offset_months
  #       Integer.  Extends the effective end date by this many calendar months.
  #       Applied AFTER any sub_end_date override.  NULL or 0 = no extension.
  #       Recommended: set to 1 for discharges when filtering by datetimedischarge,
  #       so that babies admitted in the last month of the global window are not
  #       lost because they were discharged after the nominal end date.
  #       The pipeline calculates the exact extended date and logs it; no manual
  #       date arithmetic in the config is needed.
  #
  #   date_window_note
  #       Optional free-text explanation of a non-standard date window.
  #       Printed in the subsample report and included in the data package.
  #       If NULL and sub_end_date_offset_months is set, a note is auto-generated.
  #       Set to "" to suppress the auto-generated note.
  #
  #   sub_variables
  #       NULL  = use the global sub_variables setting.
  #       character vector = use this list instead of the global list.
  #
  #   sub_exclusion_filters
  #       list()          = use the global sub_exclusion_filters.
  #       non-empty list  = use these filters instead of the global ones.
  #
  datasets = list(

    # --------------------------------------------------------------------------
    # ADMISSIONS
    # --------------------------------------------------------------------------
    admissions = list(
      include               = TRUE,
      date_column           = "datetimeadmission",
      sub_variables         = NULL,   # NULL = use global sub_variables
      sub_exclusion_filters = list()  # empty = use global sub_exclusion_filters

      # Example: admit-side column selection
      # sub_variables = c(
      #   "age", "agecategory", "birthweight", "gestation", "modedelivery",
      #   "inorout", "admittedfrom", "admreason", "feedsadm", "respsup",
      #   "surgadm", "bloodsinitial", "bloodsdone", "bloodsfinal",
      #   "bloods1", "bloods2", "bcresist", "medsgiven", "rfsepsis"
      # )
    ),

    # --------------------------------------------------------------------------
    # DISCHARGES
    # --------------------------------------------------------------------------
    #
    # Filter by datetimedischarge + 1 month extension is recommended.
    # See date_column note above.
    #
    discharges = list(
      include                    = TRUE,
      date_column                = "datetimedischarge",
      sub_end_date_offset_months = 1L,   # extend global end by 1 month
      date_window_note           = NULL, # NULL = auto-generated from offset
      sub_variables              = NULL,
      sub_exclusion_filters      = list()

      # Example: discharge-side column selection
      # sub_variables = c(
      #   "neotreeoutcome", "diagdis1", "causedeath", "contcausedeath",
      #   "datetimedeath", "datetimedischarge",
      #   "respsup", "surgadm", "bloodsinitial", "bloodsdone", "bloodsfinal",
      #   "bloods1", "bloods2", "bcresist", "medsgiven"
      # )
    ),

    # --------------------------------------------------------------------------
    # NEOLAB  (blood culture records)
    # --------------------------------------------------------------------------
    neolab = list(
      include               = FALSE,
      date_column           = "datebct",   # blood culture taken date
      sub_variables         = NULL,
      sub_exclusion_filters = list()

      # Example: all neolab variables
      # sub_variables = c(
      #   "bcresult", "bctype", "datebcr", "org1", "org2",
      #   "gram", "sens", "resistance", "resmech", "poshours", "episode"
      # )
      # Example: restrict to positive FINAL cultures only
      # sub_exclusion_filters = list(
      #   list(variable = "bcresult", operator = "==", value = "Pos"),
      #   list(variable = "bctype",   operator = "==", value = "FINAL")
      # )
    ),

    # --------------------------------------------------------------------------
    # MATERNAL
    # --------------------------------------------------------------------------
    #
    # Dataset file pattern is country-dependent and auto-resolved:
    #   Zimbabwe : maternal_outcomes
    #   Malawi   : combined_maternity_outcomes
    #
    maternal = list(
      include               = FALSE,
      date_column           = "dateadmission",
      sub_variables         = NULL,
      sub_exclusion_filters = list()

      # Example: live births only (exclude stillbirths)
      # sub_exclusion_filters = list(
      #   list(variable = "neotreeoutcome", operator = "not_in",
      #        value = c("SB", "MSB", "FD"))
      # )
    )

  )

)
