# =============================================================================
# MODULE 16 -- HELPER 03: Facility-to-Script Mapping
# =============================================================================
# PURPOSE:
#   Maps each (country, facility, dataset) combination to the appropriate
#   Neotree script.  This is necessary because the script IDs recorded in
#   older data rows use Firebase-style IDs that no longer appear in the web
#   editor -- the scripts have since been re-published with new UUIDs.
#
# MATCHING STRATEGY (in priority order):
#   1. Exact scriptId match  -- used for the three Kasungu and DHIS2 scripts
#      whose IDs in the raw data match the downloaded JSON exactly.
#   2. Facility + dataset match -- used for all other records, mapping the
#      (facility, dataset) pair to the current production script.
#   3. No match -- records from third-party imports or unrecognised facilities
#      receive no skip-logic evaluation; their empty cells are coded -9.
#
# HOW TO UPDATE THIS MAP:
#   If new hospitals are added or scripts are replaced, update the
#   FACILITY_SCRIPT_MAP list below.  Each entry maps:
#     country -> dataset -> facility_code -> script_id (UUID from the JSON)
#
# SCRIPT IDs (from downloaded JSON files):
#   ZIM:
#     SMCH admissions         : e7da1901-f1c3-43ca-abf9-a7cd01c922b0
#     SMCH discharges         : 6e774101-841c-4388-ad11-033ff7028daa
#     SMCH maternal           : 9df77822-b8ff-43e6-8c3a-c455e9cf4a02
#     SMCH neolab             : 2f771883-c473-488c-9d1e-9e054eaa93bb  (NeoLab - Zim)
#     SMCH 28-day follow-up   : 9de01fe4-e18c-4051-83f6-90efa3354e13
#     CPH  admissions         : 0ccf5891-1672-4aa0-8d92-796c22d283d7
#     CPH  discharges         : a0372aa9-f53d-4038-b5c0-62b4d4327b87
#     CPH  maternal           : fd81a5ac-cece-487c-8737-c98cfd046be1
#     CPH  28-day follow-up   : b3701e8c-61e3-457d-b96f-150c9603e4b2
#     CPH  baseline           : b3354f32-dd63-4a40-9c3d-5645581d39c7
#     BPH  admissions         : 40eefcd8-42c1-4c4f-9b5d-3f391e1438d0
#     BPH  discharges         : 6364caaa-7899-47b9-975e-f05151e4e13c
#     BPH  maternal           : 4e69e777-f680-4615-9bbe-fad81d85d6cd
#     BPH  baseline           : 047db8ad-f921-4d14-b4b1-ed500d0df805
#     PGH  admissions         : 683d8b08-1e6d-4694-87b3-c3d8b9dc557b
#     PGH  discharges         : aea9db53-b185-46c1-84cf-9243f87cc246
#   MWI:
#     KCH  admissions         : c04f628d-3d1a-46f1-8d9a-14c203a45463
#     KCH  discharges         : d02ca53d-d4bc-41a3-83dd-9dc29f3f83b4
#     KCH  maternal(*)        : f1e2757a-e12c-47f5-8949-007bbb883c75  (DHIS2 / exact match)
#     KCH  maternal(*)        : 1630f7ea-1e2d-45e6-ba0a-01f16de5b456  (Retro / fallback)
#     KCH  neolab             : a5085256-3514-4be3-bf40-56074cd92e3f  (NeoLab - Malawi)
#     KDH  admissions         : fa11721e-b8d9-4884-9d6e-dbe586eefb48  (exact match)
#     KDH  discharges         : 388f5990-1a25-46ed-bb27-49a71cde88ad  (exact match)
#     PHC  admissions         : 88e3dfc6-218c-4d72-8d24-190acc31a77f  (Generic PHC Admission - Bua)
#     PHC  discharges         : 11c3eac9-456f-4dbf-9580-14908e4be942  (Generic PHC Discharge - Bua)
#                            + 465d856a-848f-4026-aff5-f1bdea5c2425  (NeoDischarge PHC)
#
#   (*) MWI maternal uses scriptId-exact matching where possible:
#       f1e2757a -> DHIS2 Mat Outcomes (exact, high confidence)
#       Firebase IDs -> Maternal Outcomes (Retrospective) as best approximation
#       Third-party IDs -> no script (coded -9)
# =============================================================================

FACILITY_SCRIPT_MAP <- list(
  ZIM = list(
    admissions = list(
      SMCH = "e7da1901-f1c3-43ca-abf9-a7cd01c922b0",
      CPH  = "0ccf5891-1672-4aa0-8d92-796c22d283d7",
      BPH  = "40eefcd8-42c1-4c4f-9b5d-3f391e1438d0",
      PGH  = "683d8b08-1e6d-4694-87b3-c3d8b9dc557b"
    ),
    discharges = list(
      SMCH = "6e774101-841c-4388-ad11-033ff7028daa",
      CPH  = "a0372aa9-f53d-4038-b5c0-62b4d4327b87",
      BPH  = "6364caaa-7899-47b9-975e-f05151e4e13c",
      PGH  = "aea9db53-b185-46c1-84cf-9243f87cc246"
    ),
    maternal_outcomes = list(
      SMCH = "9df77822-b8ff-43e6-8c3a-c455e9cf4a02",
      CPH  = "fd81a5ac-cece-487c-8737-c98cfd046be1",
      BPH  = "4e69e777-f680-4615-9bbe-fad81d85d6cd"
    ),
    # Neolab (blood culture) -- "NeoLab - Zim"
    neolab = list(
      SMCH = "2f771883-c473-488c-9d1e-9e054eaa93bb"
    ),
    # 28-day follow-up
    twenty_8_day_follow_up = list(
      SMCH = "9de01fe4-e18c-4051-83f6-90efa3354e13",  # 28 Day Follow Up Form (SMCH)
      CPH  = "b3701e8c-61e3-457d-b96f-150c9603e4b2"   # 28 Day Follow Up Form (CPH)
    ),
    # Baseline data collection
    baseline = list(
      CPH  = "b3354f32-dd63-4a40-9c3d-5645581d39c7",  # Chinhoyi Baseline
      BPH  = "047db8ad-f921-4d14-b4b1-ed500d0df805"   # Bindura Baseline Data Collection
    )
  ),
  MWI = list(
    admissions = list(
      KCH = "c04f628d-3d1a-46f1-8d9a-14c203a45463",
      KDH = "fa11721e-b8d9-4884-9d6e-dbe586eefb48"
    ),
    discharges = list(
      KCH = "d02ca53d-d4bc-41a3-83dd-9dc29f3f83b4",
      KDH = "388f5990-1a25-46ed-bb27-49a71cde88ad"
    ),
    # MWI maternal: exact scriptId matching is preferred (see resolve_script_id)
    maternal_outcomes = list(
      KCH = "1630f7ea-1e2d-45e6-ba0a-01f16de5b456"  # Retro fallback for Firebase IDs
    ),
    # Neolab (blood culture) -- "NeoLab - Malawi"
    neolab = list(
      KCH = "a5085256-3514-4be3-bf40-56074cd92e3f"
    ),
    # PHC -- facility code "PHC" assumed; update if raw data uses a different code
    phc_admissions = list(
      PHC = "88e3dfc6-218c-4d72-8d24-190acc31a77f"   # Generic PHC Admission (Bua)
    ),
    phc_discharges = list(
      PHC = "11c3eac9-456f-4dbf-9580-14908e4be942",  # Generic PHC Discharge (Bua)
      PHC2 = "465d856a-848f-4026-aff5-f1bdea5c2425"  # NeoDischarge (PHC) -- secondary script
    )
  )
)

# Script IDs that match the raw data exactly (high-confidence exact match)
EXACT_MATCH_SCRIPT_IDS <- c(
  "fa11721e-b8d9-4884-9d6e-dbe586eefb48",  # KDH Admission
  "388f5990-1a25-46ed-bb27-49a71cde88ad",  # KDH Discharge
  "f1e2757a-e12c-47f5-8949-007bbb883c75"   # DHIS2 Mat Outcomes MWI (exact)
)

# Firebase-style MWI maternal script IDs that approximate to the Retro script
MWI_MATERNAL_FIREBASE_IDS <- c(
  "-MeiOtRPbZKqsr4A9DoA",
  "-NuYUxAu0Qwetk-wtINE",
  "-MOAjJ_In4TOoe0l_Gl5"
)

#' Resolve the Script ID for a Given Row
#'
#' @param scriptid_raw  The raw scriptid value from the data row.
#' @param facility      The facility code (e.g. "SMCH", "KCH").
#' @param country       "ZIM" or "MWI".
#' @param dataset       Pipeline dataset name (e.g. "admissions", "discharges",
#'                      "maternal_outcomes", "combined_maternity_outcomes").
#' @return  A script UUID string, or NA_character_ if no match found.
resolve_script_id <- function(scriptid_raw, facility, country, dataset) {

  # Normalise dataset name (combined_maternity_outcomes -> maternal_outcomes)
  ds <- normalise_dataset_name(dataset)
  ctry <- toupper(country)

  # 1. Exact scriptId match (highest confidence)
  if (!is.na(scriptid_raw) && scriptid_raw %in% EXACT_MATCH_SCRIPT_IDS) {
    return(scriptid_raw)
  }

  # 2. Special case: MWI maternal Firebase IDs -> Retro script approximation
  if (ctry == "MWI" && ds == "maternal_outcomes" &&
      !is.na(scriptid_raw) && scriptid_raw %in% MWI_MATERNAL_FIREBASE_IDS) {
    return("1630f7ea-1e2d-45e6-ba0a-01f16de5b456")
  }

  # 3. Facility + dataset lookup
  fac <- toupper(trimws(facility %||% ""))
  map_country <- FACILITY_SCRIPT_MAP[[ctry]]
  if (is.null(map_country)) return(NA_character_)

  map_dataset <- map_country[[ds]]
  if (is.null(map_dataset)) return(NA_character_)

  sid <- map_dataset[[fac]]
  if (is.null(sid)) return(NA_character_)
  sid
}

#' Normalise Dataset Name to the Map Keys Used Above
normalise_dataset_name <- function(dataset) {
  d <- tolower(trimws(dataset))
  if (d %in% c("combined_maternity_outcomes", "dhis2_maternal_outcomes",
               "maternal_outcomes", "maternity_completeness")) {
    return("maternal_outcomes")
  }
  # "infections" is the pipeline dataset name for blood-culture / NeoLab data
  if (d == "infections") return("neolab")
  d
}
