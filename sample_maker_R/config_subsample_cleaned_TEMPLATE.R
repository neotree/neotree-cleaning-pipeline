#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 2: Subsample from cleaned pipeline files
# FILE:    config_subsample_cleaned_TEMPLATE.R
# PURPOSE: Template for data access requests requiring standalone subsamples
#          from the CLEANED source files (admissions, discharges, neolab,
#          maternal — each processed independently, no join required).
#
#          Use this template when the researcher needs:
#            - Standalone per-type files for upload to a DSH or data safe haven
#            - Custom variable lists per dataset type
#            - Neolab or maternal records alongside admission/discharge records
#
#          COPY AND RENAME this file for each request, e.g.:
#            config_subsample_SmithJ_SMCH_2024_cleaned.R
#
#          Then run:
#            Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_cleaned.R
#
#          For most data access requests, run BOTH configs:
#            1. config_subsample_..._Nvars.R    (master mode — primary joined dataset)
#            2. config_subsample_..._cleaned.R  (this file — standalone per-type files)
#          Write both to the SAME output_dir so that run_subsample_user_dict.R
#          can auto-discover all files in one pass.
#
# FULL OPTION REFERENCE: see config_subsample_TEMPLATE.R
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-05)
################################################################################

SUBSAMPLE_CONFIG <- list(

  # ============================================================================
  # 1. SOURCE TYPE
  # ============================================================================
  source_type = "cleaned",

  # ============================================================================
  # 2. CLEANED SOURCE SETTINGS
  # ============================================================================
  #
  # Path to the input/ folder (relative to run_subsample_maker.R, or absolute).
  # country and source must match the subdirectory names in input/.
  #
  cleaning_pipeline_output_dir = "input",
  country = "zim",            # "zim" | "mwi"
  source  = "from_database",  # "from_database" | "from_metabase"

  # ============================================================================
  # 3. OUTPUT DIRECTORY
  # ============================================================================
  #
  # Use the SAME directory as the companion master config so that
  # run_subsample_user_dict.R finds both in one pass.
  #
  # Convention: outputs/{country}/{source}/subsamples/{researcher_name}/
  #
  output_dir = "outputs/zim_master/from_database/subsamples/researcher_name",

  # ============================================================================
  # 4. GLOBAL DATE WINDOW
  # ============================================================================
  #
  # Applied to each dataset type via its date_column (Section 8).
  # Per-dataset overrides can be set in Section 8 if needed.
  #
  sub_start_date = "YYYY-MM-DD",   # first day of study period (inclusive)
  sub_end_date   = "YYYY-MM-DD",   # last day of study period (inclusive)

  # ============================================================================
  # 5. GLOBAL FACILITY FILTER
  # ============================================================================
  #
  # NULL    -> all facilities
  # "SMCH"  -> single facility
  # c("SMCH", "BPH")  -> multiple facilities
  #
  sub_facility_filter = NULL,

  # ============================================================================
  # 5b. ADVANCED MODE  (leave FALSE for most requests)
  # ============================================================================
  sub_use_advanced_mode    = FALSE,
  sub_facility_date_ranges = list(),

  # ============================================================================
  # 6. GLOBAL EXCLUSION FILTERS  (leave empty for most requests)
  # ============================================================================
  sub_exclusion_filters = list(),

  # ============================================================================
  # 7. GLOBAL COLUMN SELECTION
  # ============================================================================
  #
  # NULL here — column selection is controlled per dataset in Section 8.
  # This avoids applying an admission-side variable list to the discharge file
  # (which has different column names).
  #
  sub_variables = NULL,

  # ============================================================================
  # 8. DATASET SETTINGS
  # ============================================================================
  #
  # Set include = TRUE for each dataset type the researcher needs.
  # Mandatory columns are always retained:
  #   admissions : uid, facility, uniquekey, datetimeadmission
  #   discharges : uid, facility, uniquekey
  #   neolab     : uid, facility, uniquekey, datebct
  #   maternal   : uid, facility, uniquekey, dateadmission
  #

  datasets = list(

    # --------------------------------------------------------------------------
    # ADMISSIONS
    # --------------------------------------------------------------------------
    admissions = list(
      include               = TRUE,
      date_column           = "datetimeadmission",
      sub_exclusion_filters = list(),   # empty = use global filters
      sub_variables = c(
        # Uncomment / add the variables the researcher needs.
        # Use the variable profile to confirm names and completeness.
        # "age",
        # "agecategory",
        # "birthweight",
        # "gestation",
        # "modedelivery",
        # "inorout",
        # "admittedfrom",
        # "admreason",
        # "feedsadm",
        # "respsup",
        # "surgadm",
        # "bloodsinitial",
        # "bloodsdone",
        # "bloodsfinal",
        # "bloods1",
        # "bloods2",
        # "bcresist",
        # "medsgiven",
        # "rfsepsis"
      )
    ),

    # --------------------------------------------------------------------------
    # DISCHARGES
    # --------------------------------------------------------------------------
    #
    # datetimeadmission is re-entered manually on the discharge form and is
    # typically ~44% blank at SMCH.  If filtering by admission date, use the
    # master mode config instead (which filters by datetimeadmission on the
    # admission record and links discharges via uid).
    #
    # For a standalone discharge file filtered by discharge date:
    #   date_column = "datetimedischarge"
    #   sub_end_date_offset_months = 1L   (to capture babies discharged after the window)
    #
    # For a standalone discharge file with no date filter (all records, facility only):
    #   date_column = NULL
    #
    discharges = list(
      include                    = TRUE,
      date_column                = "datetimeadmission",   # or "datetimedischarge" or NULL
      sub_end_date_offset_months = NULL,                  # set to 1L if using datetimedischarge
      date_window_note           = NULL,
      sub_exclusion_filters      = list(),
      sub_variables = c(
        # "neotreeoutcome",
        # "diagdis1",
        # "causedeath",
        # "contcausedeath",
        # "datetimedeath",
        # "datetimedischarge",
        # "respsup",
        # "surgadm",
        # "bloodsinitial",
        # "bloodsdone",
        # "bloodsfinal",
        # "bloods1",
        # "bloods2",
        # "bcresist",
        # "medsgiven"
      )
    ),

    # --------------------------------------------------------------------------
    # NEOLAB  (blood culture records)
    # --------------------------------------------------------------------------
    neolab = list(
      include               = FALSE,    # set TRUE if neolab records are requested
      date_column           = "datebct",
      sub_exclusion_filters = list(),
      sub_variables = c(
        # "bcresult",
        # "bctype",
        # "datebcr",
        # "org1",
        # "org2",
        # "gram",
        # "sens",
        # "resistance",
        # "resmech",
        # "poshours",
        # "episode"
      )
    ),

    # --------------------------------------------------------------------------
    # MATERNAL
    # --------------------------------------------------------------------------
    maternal = list(
      include               = FALSE,    # set TRUE if maternal records are requested
      date_column           = "dateadmission",
      sub_exclusion_filters = list(),
      sub_variables         = NULL      # NULL = all columns
    )

  )

)
