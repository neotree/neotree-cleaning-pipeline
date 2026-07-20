#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 2: Subsample from master joined files
# FILE:    config_subsample_master_TEMPLATE.R
# PURPOSE: Template for data access requests requiring a subsample from the
#          JOINED master dataset (admissions linked to discharges).
#
#          Use this template when the researcher needs:
#            - Both admission AND discharge data for each patient
#            - A defined date window (by admission date)
#            - Optionally restricted to specific facilities
#            - Optionally restricted to a defined variable list
#
#          COPY AND RENAME this file for each request, e.g.:
#            config_subsample_SmithJ_SMCH_2024_20vars.R
#
#          Then run:
#            Rscript run_subsample_maker.R config_subsample_SmithJ_SMCH_2024_20vars.R
#
#          If standalone cleaned files are ALSO needed (e.g. for DSH upload),
#          create a companion config using config_subsample_cleaned_TEMPLATE.R
#          and write both to the SAME output_dir so that run_subsample_user_dict.R
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
  source_type = "master",

  # ============================================================================
  # 2. MASTER SOURCE FILES
  # ============================================================================
  #
  # Paths to the Pipeline 1 master joined files (relative to this script, or
  # absolute).  These are produced by run_all.R / run_sample_maker.R.
  # Update the date label (_to_YYYYMMDD) to match the actual file on disk.
  #
  master_joined_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_to_YYYYMMDD.csv",

  master_joined_extended_file =
    "outputs/zim_master/from_database/ZIM_db_master_joined_extended_to_YYYYMMDD.csv",

  # ============================================================================
  # 3. OUTPUT DIRECTORY
  # ============================================================================
  #
  # Use a shared subdirectory per researcher so that all outputs from both
  # master and cleaned configs are auto-discovered in one pass by
  # run_subsample_user_dict.R.
  #
  # Convention: outputs/{country}/{source}/subsamples/{researcher_name}/
  #
  output_dir = "outputs/zim_master/from_database/subsamples/researcher_name",

  # ============================================================================
  # 4. DATE WINDOW  (applied to datetimeadmission)
  # ============================================================================
  sub_start_date = "YYYY-MM-DD",   # first day of study period (inclusive)
  sub_end_date   = "YYYY-MM-DD",   # last day of study period (inclusive)

  # ============================================================================
  # 5. FACILITY FILTER
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
  # 6. EXCLUSION FILTERS  (leave empty for most requests)
  # ============================================================================
  #
  # Examples:
  #   list(variable = "gestation",    operator = "<",  value = 24),
  #   list(variable = "multiplicity", operator = "==", value = TRUE)
  #
  sub_exclusion_filters = list(),

  # ============================================================================
  # 7. VARIABLE SELECTION
  # ============================================================================
  #
  # NULL -> retain ALL columns (default).
  # List only the variables the researcher needs.  Mandatory columns (uid,
  # facility, uniquekey, datetimeadmission, match_key, adm_date_parsed,
  # match_type, prob_match_similarity) are always retained.
  #
  # Use the variable profile (outputs/.../profiles/*_variable_profile.txt)
  # to check exact column names and completeness before finalising this list.
  #
  sub_variables = c(
    # ---- Admission-side ----
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
    # "rfsepsis",

    # ---- Discharge-side ----
    # "neotreeoutcome",
    # "diagdis1",
    # "causedeath",
    # "contcausedeath",
    # "datetimedeath",
    # "datetimedischarge"
  ),

)
# NOTE: the `datasets` block (admissions, discharges, neolab, maternal) is
# only used in cleaned mode (source_type = "cleaned").  It is not needed here
# and should not be added to master mode configs.
