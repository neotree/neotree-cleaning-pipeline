#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 1: Join Admissions & Discharges
# FILE:    config_sample_maker.R
# PURPOSE: Central user configuration for run_sample_maker.R.
#          Edit the fields below to select data sources, date windows,
#          and probabilistic matching settings.
#
# INPUT:   Set cleaning_pipeline_output_dir (section 3) to the cleaning
#          pipeline's output/ folder.  The script auto-discovers admissions and
#          discharges from subdirectories matching:
#            {cleaning_pipeline_output_dir}/{country}_{src}_{type}_{date}/{country}_{src}_{type}_{date}_cleaned.csv
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.1  (2026-05)
################################################################################

CONFIG <- list(

  # ============================================================================
  # 1. DATA SELECTION
  # ============================================================================
  #
  # country : "zim" (Zimbabwe) | "mwi" (Malawi)
  # source  : "from_database"  -- files extracted directly from the Neotree DB
  #           "from_metabase"  -- files downloaded from Metabase reports
  #
  country = "zim",
  source  = "from_database",

  # ============================================================================
  # 2. ADMISSION DATE WINDOW
  # ============================================================================
  #
  # AUTO MODE (recommended):
  #   Set adm_start_date and adm_end_date to NULL.
  #   adm_end_date is automatically set to (last admission date - 1 month).
  #   adm_start_date = NULL means no lower bound (all historical data included).
  #   Discharges are NOT filtered by date: all discharge records are used so
  #   that babies admitted up to adm_end_date have the best chance of a match.
  #
  # MANUAL MODE:
  #   Provide explicit ISO dates ("YYYY-MM-DD") to override.
  #
  # ADVANCED MODE (per-facility date ranges):
  #   Set use_advanced_mode = TRUE and provide facility_date_ranges.
  #   adm_start_date and adm_end_date are IGNORED in advanced mode.
  #   Each entry: c("FACILITY_NAME", "start_date", "end_date")
  #   Use NA for an open bound.
  #
  use_advanced_mode    = FALSE,
  adm_start_date       = NULL,   # "YYYY-MM-DD" or NULL (no lower bound)
  adm_end_date         = NULL,   # "YYYY-MM-DD" or NULL (auto = last date - 1 month)
  facility_date_ranges = list(), # used only when use_advanced_mode = TRUE

  # ============================================================================
  # 3. PATHS
  # ============================================================================
  #
  # cleaning_pipeline_output_dir points directly to the cleaning pipeline's
  # output/ folder.  Subdirectories are auto-discovered; no manual copying needed.
  #
  cleaning_pipeline_output_dir = "../cleaning_pipeline_R/output",
  output_dir                   = "outputs",

  # ============================================================================
  # 4. PROBABILISTIC MATCHING
  # ============================================================================
  #
  # After the direct uid+facility join, unmatched admissions are compared to
  # unmatched discharges using shared clinical variables.  The best one-to-one
  # pairs above the minimum similarity threshold are accepted.
  #
  # prob_match_min_similarity         : minimum score (0-100).  Default 100 =
  #                                     exact match on all available variables.
  #                                     Lower to 90-95 for higher recall.
  # prob_match_max_candidates         : max candidates per unmatched admission
  #                                     in the investigation report.
  # prob_match_completeness_threshold : minimum proportion of non-NA values (0-1)
  #                                     for a variable to be used in matching.
  # prob_match_cross_facility         : if TRUE, search across all facilities
  #                                     when no within-facility candidate found.
  #
  # Per-variable tolerances (numeric variables):
  #   Score decays linearly from 100 at diff=0 to 0 at diff=2xtolerance.
  #   Set to 0 for exact-match-only.
  #   NOTE: birthweight is stored in GRAMS in the cleaned Neotree data.
  #
  prob_match_min_similarity         = 100,
  prob_match_max_candidates         = 5,
  prob_match_completeness_threshold = 0.3,
  prob_match_cross_facility         = FALSE,
  prob_match_birthweight_tolerance  = 20,   # grams
  prob_match_gestation_tolerance    = 0,    # exact -- whole weeks
  prob_match_ofc_tolerance          = 0.5,  # cm    -- one measurement step
  prob_match_temperature_tolerance  = 0.1,  # degC  -- one decimal rounding difference
  prob_match_apgar1_tolerance       = 0,    # exact -- integer score
  prob_match_apgar5_tolerance       = 0,    # exact -- integer score
  prob_match_apgar10_tolerance      = 0,    # exact -- integer score

  # ============================================================================
  # 5. NA-CODED OUTPUT
  # ============================================================================
  #
  # TRUE  (default) -- also write *_na_coded.csv variants of master_joined and
  #                    master_joined_extended alongside the standard blank-NA files.
  #                    These contain the same rows but with NA represented as
  #                    numeric sentinel codes (-7, -8, -9, etc.) exactly as in
  #                    the cleaning pipeline's *_cleaned_na_coded.csv sources.
  # FALSE           -- write only the standard blank-NA master files.
  #
  # Requires that the cleaning pipeline produced *_cleaned_na_coded.csv files
  # alongside the standard *_cleaned.csv files in the input/ folder.
  # If the na_coded source files are not found the pipeline continues normally
  # and emits a warning (no error).
  #
  # The na_coded master files are the ML-training variants used to preserve
  # the distinction between different types of missingness.
  #
  output_na_coded = TRUE

)
