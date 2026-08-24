# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00: Setup & Configuration
# =============================================================================
# PURPOSE:
#   Centralises all file paths, country/dataset selection, library loading,
#   logging configuration, and feature lists used throughout every downstream
#   module.  Feature lists are derived DYNAMICALLY from the data dictionary
#   rather than being hard-coded.
#
# SUPPORTED COMBINATIONS:
#   COUNTRY  x DATASET
#   "ZIM"    x "admissions"                  -> dictionaries/dictionary_zim_admissions.xlsx
#   "ZIM"    x "discharges"                  -> dictionaries/dictionary_zim_discharges.xlsx
#   "ZIM"    x "maternal_outcomes"           -> dictionaries/dictionary_zim_maternal_outcomes.xlsx
#   "ZIM"    x "phc_admissions"              -> dictionaries/dictionary_zim_phc_admissions.xlsx
#   "ZIM"    x "phc_discharges"              -> dictionaries/dictionary_zim_phc_discharges.xlsx
#   "MWI"    x "admissions"                  -> dictionaries/dictionary_mwi_admissions.xlsx
#   "MWI"    x "discharges"                  -> dictionaries/dictionary_mwi_discharges.xlsx
#   "MWI"    x "maternal_outcomes"           -> dictionaries/dictionary_mwi_maternal_outcomes.xlsx
#   "MWI"    x "phc_admissions"              -> dictionaries/dictionary_mwi_phc_admissions.xlsx
#   "MWI"    x "phc_discharges"              -> dictionaries/dictionary_mwi_phc_discharges.xlsx
#   "MWI"    x "combined_maternity_outcomes" -> dictionaries/dictionary_mwi_combined_maternity_outcomes.xlsx
#   "MWI"    x "dhis2_maternal_outcomes"     -> dictionaries/dictionary_mwi_dhis2_maternal_outcomes.xlsx
#   "MWI"    x "maternity_completeness"      -> dictionaries/dictionary_mwi_maternity_completeness.xlsx
#   "ZIM"    x "neolab"                      -> dictionaries/dictionary_zim_neolab.xlsx
#   "MWI"    x "neolab"                      -> dictionaries/dictionary_mwi_neolab.xlsx
#
#   Special: "joined_admissions_discharges" is produced at analysis time by
#   joining the cleaned admissions + discharges outputs.  There is no separate
#   dictionary; it falls back automatically to the "admissions" dictionary.
#
# USAGE:
#   source("00_setup/00_setup.r")
#
# OUTPUTS (global objects):
#   cfg               - named list with all pipeline parameters & feature lists
#   dict_variables    - Variables sheet of the data dictionary (tibble)
#   dict_value_maps   - ValueMaps sheet of the data dictionary (tibble)
# =============================================================================

# -- Libraries -----------------------------------------------------------------
suppressPackageStartupMessages({
  library(readr) # Fast CSV reading
  library(readxl) # Excel dictionary loading
  library(dplyr) # Data manipulation
  library(tidyr) # Reshaping helpers
  library(stringr) # String operations
  library(lubridate) # Datetime parsing
  library(purrr) # Functional helpers
  library(logger) # Structured logging
  library(janitor) # clean_names helper
  library(tibble) # For deframe() function
})

# =============================================================================
# USER CONFIGURATION  -  Edit these lines before each run
# =============================================================================
# NOTE: If any of these variables are already defined in the calling environment
#       (e.g. set by run_all.r before sourcing this file), they are preserved as-is.
#       Only missing / undefined variables receive the default values below.
# =============================================================================

# Source country  :  "ZIM" (Zimbabwe) | "MWI" (Malawi)
if (!exists("COUNTRY"))     COUNTRY     <- "ZIM"

# Dataset type:
#   Standard        : "admissions" | "discharges" | "maternal_outcomes"
#   PHC             : "phc_admissions" | "phc_discharges"
#   Maternal sources: "combined_maternity_outcomes"   - all 3 source files merged
#                     "dhis2_maternal_outcomes"        - DHIS2-linked maternal source only
#                     "maternity_completeness"         - maternity completeness source only
#   Joined          : "joined_admissions_discharges"  (falls back to admissions dict)
#   Neolab          : "neolab"                        (blood culture dataset)
#   Zimbabwe-specific: "baseline"                     - retrospective baseline (ZIM)
#                      "infections"                   - longitudinal infection follow-up (ZIM)
#                      "twenty_8_day_follow_up"       - 28-day post-discharge follow-up (ZIM)
if (!exists("DATASET"))     DATASET     <- "admissions"

# Data source format  :  "database"  (direct PostgreSQL export)
#                     |  "metabase"  (Metabase export)
#
#   "database"  - System columns use snake_case  (unique_key, started_at)
#                 Data columns use CamelCase     (BabyCryTriage.value)
#                 Datetime values in ISO format  ("2021-10-08 13:51:01")
#
#   "metabase"  - System columns use Title Case with spaces (Unique Key)
#                 Data column names may have extra spaces (Baby Cry Tria Ge. Value)
#                 Datetime values in human-readable format ("March 2, 2026, 12:33 AM")
#
#   Both formats normalise to identical compact lowercase column names before
#   any processing.  Set this flag so that datetime-parsing modules (Module 14)
#   can apply the correct parsing strategy.
if (!exists("DATA_SOURCE")) DATA_SOURCE <- "database" # "database" or "metabase"

# Raw CSV file (direct PostgreSQL export OR Metabase export)
# -- Input files available in input/ -------------------------------------------
# MWI (database):  input/mwi_db_admissions_20260501.csv
#                  input/mwi_db_discharges_20260501.csv
#                  input/mwi_db_combined_maternity_outcomes_20260501.csv
#                  input/mwi_db_neolab_20260501.csv
#                  input/mwi_db_phc_admissions_20260501.csv
#                  input/mwi_db_phc_discharges_20260501.csv
# MWI (metabase):  input/mwi_mb_admissions_2026-05-01.csv
#                  input/mwi_mb_discharges_2026-05-01.csv
#                  input/mwi_mb_combined_maternity_outcomes_2026-05-01.csv
#                  input/mwi_mb_neolab_2026-05-01.csv
#                  input/mwi_mb_phc_admissions_2026-05-01.csv
#                  input/mwi_mb_phc_discharges_2026-05-01.csv
# ZIM (database):  input/zim_db_admissions_20260501.csv
#                  input/zim_db_discharges_20260501.csv
#                  input/zim_db_maternal_outcomes_20260501.csv
#                  input/zim_db_neolab_20260501.csv
#                  input/zim_db_phc_admissions_20260501.csv    [if present]
#                  input/zim_db_phc_discharges_20260501.csv    [if present]
#                  input/zim_db_baseline_20260501.csv
#                  input/zim_db_infections_20260501.csv
#                  input/zim_db_twenty_8_day_follow_up_20260501.csv
# ZIM (metabase):  input/zim_mb_admissions_2026-05-01.csv
#                  input/zim_mb_discharges_2026-05-01.csv
#                  input/zim_mb_maternal_outcomes_2026-05-01.csv
#                  input/zim_mb_neolab_2026-05-01.csv
#                  input/zim_mb_baseline_2026-05-01.csv
#                  input/zim_mb_infections_2026-05-01.csv
#                  input/zim_mb_twenty_8_day_follow_up_2026-05-01.csv
# -----------------------------------------------------------------------------
if (!exists("CSV_FILEPATH")) CSV_FILEPATH <- "input/zim_db_admissions_20260501.csv"

# Dictionary path (auto-resolved if left as NULL)
if (!exists("DICT_FILEPATH"))       DICT_FILEPATH       <- NULL # NULL = auto: dictionaries/dictionary_{country}_{dataset}.xlsx

# Output file paths (NULL = auto-named from CSV_FILEPATH)
if (!exists("OUTPUT_CSV"))          OUTPUT_CSV          <- NULL
if (!exists("OUTPUT_RDS"))          OUTPUT_RDS          <- NULL

# Path to the neotree_scripts directory (used by Module 16: NA Reason Coding).
#   Should contain zim-scripts/ and mwi-scripts/ sub-directories, each holding
#   the downloaded Neotree script metadata JSON files.
#   NULL = auto-derived relative to this setup file (recommended).
if (!exists("NEOTREE_SCRIPTS_DIR")) NEOTREE_SCRIPTS_DIR <- NULL

# Report directory
#   NULL        = auto-named from the source CSV, country, and dataset (recommended)
#                 e.g. "discharges_202603201047_MWI_discharges_reports"
#                 Every run gets its own folder -- past reports are never overwritten,
#                 and the folder name makes the originating file immediately traceable.
#   "my_folder" = write all reports to that exact fixed path (will be overwritten on re-run)
#   FALSE       = suppress all reports entirely
if (!exists("REPORT_DIR"))          REPORT_DIR          <- NULL

# Output directory  :  all cleaned files, reports, and the pipeline log are saved here.
#   Mirrors the "input" folder -- raw source files stay in input/, everything
#   the pipeline produces goes into output/.
if (!exists("OUTPUT_DIR"))          OUTPUT_DIR          <- "output"

# =============================================================================
# OUTPUT FILE FLAGS  -  Toggle optional outputs on / off
# =============================================================================
# Each flag controls whether a specific output file is written.
# Set to FALSE to skip that output and save disk space / time.
# These can also be pre-set by run_all.r (same if(!exists()) pattern).

# De-identified raw CSV written by Module 00a.
# Large (same size as raw input), useful only if you need a pre-cleaning
# rollback point without re-running PII removal.
if (!exists("SAVE_DEIDENTIFIED"))      SAVE_DEIDENTIFIED      <- FALSE

# Stage-1 checkpoint RDS written by Module 10 after deduplication.
# Useful during pipeline development / debugging; not needed in production.
if (!exists("SAVE_STAGE1_CHECKPOINT")) SAVE_STAGE1_CHECKPOINT <- FALSE

# Skip Stage 2 (patient-level) deduplication in Module 10.
#   FALSE (default) -- both Stage 1 and Stage 2 run.
#   TRUE            -- only Stage 1 (visit-level) runs; all records per patient are kept.
#
#   Set TRUE automatically for longitudinal datasets where multiple rows per patient
#   are by design:
#     "infections"  -- NeoInfect serial review form: one row per clinical review visit.
#     "neolab"      -- NeoLab blood culture form: one row per culture event.
#   For all other datasets (admissions, discharges, etc.) the default FALSE is correct,
#   because each patient should appear only once.
#
#   Override explicitly in run_all.r if you need non-default behaviour for a specific run:
#     SKIP_DEDUP_STAGE2 <- TRUE
if (!exists("SKIP_DEDUP_STAGE2")) {
  SKIP_DEDUP_STAGE2 <- DATASET %in% c("infections", "neolab")
}

# Resolve missing neolab datebct from admissions (Module 14a).
#   TRUE  (default) -- after datetime validation, Module 14a attempts to fill
#                      NA datebct.value entries by joining to the raw admissions
#                      file on uid + facility and using datetimeadmission as a
#                      proxy date.  Two new columns are added to the output:
#                        datebct_resolved  (POSIXct)   best available date
#                        datebct_source    (character)  "original" | "from_admission" | NA
#                      datebct.value itself is never modified.
#   FALSE           -- Module 14a runs but exits immediately; no new columns added.
#
#   Only has any effect when DATASET == "neolab".  Safe to leave TRUE for all
#   other datasets (the module checks and skips in < 1ms).
if (!exists("RESOLVE_NEOLAB_DATEBCT")) RESOLVE_NEOLAB_DATEBCT <- TRUE

# Separator characters treated as a mistyped hyphen in a uid (Module 02).
#   The standard Neotree uid is "XXXX-YYYY".  A uid of the form "XXXX,YYYY" or
#   "XXXX/YYYY" is a data-entry substitution for that hyphen and is repaired.
#   To recognise a further substitute character later, add it to this vector --
#   no code change is needed anywhere else.
#
#   Only characters with evidence in the raw data belong here.  Space and
#   backslash were checked across the ZIM and MWI admission and discharge files
#   (4 Aug 2026 extract) and occur zero times in any uid, so they are
#   deliberately NOT included: repairing a character no one has ever typed
#   invents corrections rather than fixing them.
if (!exists("UID_REPAIR_SEPARATORS")) UID_REPAIR_SEPARATORS <- c(",", "/")

# Raw data columns whose standardised base name collides with a reserved
# system key column (facility | uid | uniquekey).  Module 01 renames these
# immediately after name standardisation so Module 07's prefix-based
# duplicate-column logic never sees two columns sharing the "facility"
# prefix -- without this, Module 07 always keeps the always-populated system
# column and silently discards the genuine clinical data field.
#
# MWI phc_discharges: the NeoDischarge (PHC) script's own "Facility" field
# (dropdown; Name of Facility -- KRH/LH etc, confirmed via
# neotree_scripts/mwi-scripts/NeoDischarge (PHC) - metadata.json) exports as
# raw columns Facility.value / Facility.label, which standardise to
# facility.value / facility.label -- colliding with the system "facility"
# key column (always "PHC" in this extract). Renamed to facilityname.* so
# the field survives as its own variable; see dictionary question_key
# "facilityname" in dictionary_mwi_phc_discharges.xlsx.
#   Format: dataset -> named character vector (standardised name -> new name)
if (!exists("RESERVED_COLUMN_RENAMES")) {
  RESERVED_COLUMN_RENAMES <- list(
    phc_discharges = c(
      "facility.value" = "facilityname.value",
      "facility.label" = "facilityname.label"
    )
  )
}

# Harmonised (snake_case) CSV + RDS written by Module 00b.
# Set TRUE if your downstream analysis uses harmonised column names.
if (!exists("SAVE_HARMONISED"))        SAVE_HARMONISED        <- FALSE

# NA-coded CSV written by Module 16: cleaned data where every NA cell is
# replaced by its reason code (-6/-7/-8/-9).  Larger than the cleaned CSV
# alone but self-contained (no need to join with the separate na_reasons file).
if (!exists("SAVE_NA_CODED"))          SAVE_NA_CODED          <- TRUE

# Long-format NA reasons table written by Module 16.
# One row per NA cell -- very large; useful for row-level auditing but
# the wide _na_reasons.csv.gz and _na_reasons_summary.csv cover most needs.
if (!exists("SAVE_NA_REASONS_LONG"))   SAVE_NA_REASONS_LONG   <- FALSE

# =============================================================================
# INTERNAL SETUP  -  Do not edit below this line unless you know what you're doing
# =============================================================================

# -- Output directory ----------------------------------------------------------
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# -- Per-run output subdirectory -----------------------------------------------
# Named after the input CSV stem (e.g. "zim_db_admissions_20260501").
# All outputs for this run — cleaned files, reports, and the run log — land here.
file_stem      <- sub("\\.csv$", "", basename(CSV_FILEPATH))
RUN_OUTPUT_DIR <- file.path(OUTPUT_DIR, file_stem)
if (!dir.exists(RUN_OUTPUT_DIR)) dir.create(RUN_OUTPUT_DIR, recursive = TRUE)

# -- Neotree scripts directory (Module 16) ------------------------------------
if (is.null(NEOTREE_SCRIPTS_DIR)) {
  NEOTREE_SCRIPTS_DIR <- file.path(
    dirname(normalizePath("00_setup/00_setup.r", mustWork = FALSE)),
    "..", "neotree_scripts"
  )
}
NEOTREE_SCRIPTS_DIR <- normalizePath(NEOTREE_SCRIPTS_DIR, mustWork = FALSE)

# -- Pipeline version ----------------------------------------------------------
# Stamped into every per-run log so a cleaned output can always be traced back to
# the code that produced it.  Bump this together with CHANGELOG.md on release.
PIPELINE_VERSION <- "1.2.1"

# -- Logging -------------------------------------------------------------------
log_appender(appender_tee(file = file.path(RUN_OUTPUT_DIR, paste0(file_stem, ".log"))))
log_threshold(INFO)
# logger >= 0.4.0 changed the default formatter to formatter_glue, which does
# not handle sprintf-style %s / %d placeholders -- it pastes extra arguments
# rather than substituting them.  Explicitly restore sprintf behaviour here so
# all log_info("text %s", value) calls throughout the pipeline work correctly.
#
# IMPORTANT -- the logger runs sprintf() on every message it is given.  Never
# hand it a string you have already formatted yourself: log_warn(sprintf(...))
# formats twice, so any literal % surviving the first pass (from %%, or from a
# %s filled with a data value containing %) throws "too few arguments" and
# aborts the module.  Always pass the format string and its arguments
# separately: log_warn("... %d of %d (%.1f%%) ...", a, b, pct).
log_formatter(formatter_sprintf)
log_info("Pipeline started (cleaning pipeline v%s).", PIPELINE_VERSION)

# -- Normalise inputs ----------------------------------------------------------
COUNTRY <- toupper(trimws(COUNTRY))
DATASET <- tolower(trimws(DATASET))
DATA_SOURCE <- tolower(trimws(DATA_SOURCE))

VALID_DATASETS <- c(
  "admissions", "discharges", "maternal_outcomes",
  "phc_admissions", "phc_discharges",
  "combined_maternity_outcomes",
  "dhis2_maternal_outcomes",      # individual DHIS2-linked maternal source file
  "maternity_completeness",       # individual maternity completeness source file
  "joined_admissions_discharges",
  "neolab",                       # blood culture / neolab dataset
  # Zimbabwe-specific extended datasets
  "baseline",                     # retrospective baseline admission+discharge in one form (ZIM)
  "infections",                   # longitudinal infection follow-up form (ZIM)
  "twenty_8_day_follow_up"        # 28-day post-discharge follow-up (ZIM)
)

if (!COUNTRY %in% c("ZIM", "MWI")) {
  stop(sprintf("COUNTRY must be 'ZIM' or 'MWI', got '%s'.", COUNTRY))
}
if (!DATASET %in% VALID_DATASETS) {
  stop(sprintf(
    "DATASET must be one of: %s\n  Got: '%s'",
    paste(VALID_DATASETS, collapse = ", "), DATASET
  ))
}
if (!DATA_SOURCE %in% c("database", "metabase")) {
  stop(sprintf("DATA_SOURCE must be 'database' or 'metabase', got '%s'.", DATA_SOURCE))
}

log_info("Data source format : %s", DATA_SOURCE)

# =============================================================================
# DICTIONARY FALLBACK MAP
# =============================================================================
# Some dataset types share a dictionary with a closely related standard type.
# E.g. "joined_admissions_discharges" uses the "admissions" dictionary because
# it has no dedicated dictionary of its own.
#
# For PHC datasets, the pipeline first tries the specific phc_* dictionary; if
# that file does not exist it falls back to the standard admissions/discharges
# dictionary (same keys, slightly different script titles).

DICT_FALLBACK <- list(
  joined_admissions_discharges = "admissions",
  phc_admissions               = "admissions",               # fallback only; specific dict preferred
  phc_discharges               = "discharges",               # fallback only; specific dict preferred
  dhis2_maternal_outcomes      = "combined_maternity_outcomes", # fallback -> combined -> maternal
  maternity_completeness       = "maternal_outcomes",         # fallback only; specific dict preferred
  # New ZIM-specific types: fall back to admissions (baseline shares many fields;
  # infections and 28-day follow-up have dedicated dicts once built).
  baseline                     = "admissions",               # fallback; dedicated dict preferred
  infections                   = NULL,                       # no sensible fallback; must have own dict
  twenty_8_day_follow_up       = NULL                        # no sensible fallback; must have own dict
)

# -- Resolve auto paths --------------------------------------------------------
if (is.null(DICT_FILEPATH)) {
  primary_path <- sprintf("dictionaries/dictionary_%s_%s.xlsx", tolower(COUNTRY), DATASET)
  fallback_type <- DICT_FALLBACK[[DATASET]]
  if (!file.exists(primary_path) && !is.null(fallback_type)) {
    fallback_path <- sprintf("dictionaries/dictionary_%s_%s.xlsx", tolower(COUNTRY), fallback_type)
    if (file.exists(fallback_path)) {
      log_info(
        "No specific dictionary for %s x %s; falling back to %s dictionary.",
        COUNTRY, DATASET, fallback_type
      )
      DICT_FILEPATH <- fallback_path
    } else {
      DICT_FILEPATH <- primary_path # will fail below with clear message
    }
  } else {
    DICT_FILEPATH <- primary_path
  }
}

if (is.null(OUTPUT_CSV)) {
  OUTPUT_CSV <- file.path(RUN_OUTPUT_DIR, paste0(file_stem, "_cleaned.csv"))
}

if (is.null(OUTPUT_RDS)) {
  OUTPUT_RDS <- file.path(RUN_OUTPUT_DIR, paste0(file_stem, "_cleaned.rds"))
}

# -- Report directory ----------------------------------------------------------
# Auto-derive as a reports/ subfolder inside the run output directory.
# Example: output/zim_db_admissions_20260501/reports/
if (is.null(REPORT_DIR)) {
  REPORT_DIR <- file.path(RUN_OUTPUT_DIR, "reports")
}
if (!isFALSE(REPORT_DIR) && nzchar(REPORT_DIR) && !dir.exists(REPORT_DIR)) {
  dir.create(REPORT_DIR, recursive = TRUE)
}
# Normalise suppression: treat FALSE or "" as NULL so downstream modules skip writing
if (isFALSE(REPORT_DIR) || identical(REPORT_DIR, "")) REPORT_DIR <- NULL

log_info("Running for: COUNTRY=%s  DATASET=%s", COUNTRY, DATASET)
log_info("Dictionary : %s", DICT_FILEPATH)

# =============================================================================
# PAIRED DATASET RESOLUTION
# =============================================================================
# Admissions and discharges are two halves of the same patient record, but the
# pipeline cleans one file at a time and never loads both together.  Some checks
# need to look the other half up -- Module 02, for example, can only call a
# repaired uid "confirmed" if the corrected uid actually exists in the paired
# file for the same country.
#
# This block resolves the paired raw CSV once, here, so that any module can use
# cfg$paired_csv_filepath without repeating the path arithmetic.  It resolves a
# path only; nothing is read.  Modules that need the file read the columns they
# want, when they want them (the same approach Module 14a takes for its
# neolab -> admissions lookup).
#
# NULL means "no paired file available" -- either the dataset has no pair, or
# the file is not in input/.  Modules must treat that as "cannot check", never
# as a negative result.

PAIRED_DATASET <- c(
  admissions     = "discharges",
  discharges     = "admissions",
  phc_admissions = "phc_discharges",
  phc_discharges = "phc_admissions"
)

#' Locate the paired admissions/discharges raw CSV for the current run
#'
#' Prefers the file from the same extract (identical date stamp).  If that is
#' absent -- extracts are dumped per table and the stamps often differ by a
#' minute or two -- it falls back to any extract of the paired dataset for the
#' same country and source, taking the most recent.
#'
#' @return list(dataset = <paired dataset name or NULL>, path = <path or NULL>)
.resolve_paired_csv <- function(csv_filepath, dataset) {
  paired <- unname(PAIRED_DATASET[dataset])
  if (is.na(paired)) return(list(dataset = NULL, path = NULL))

  in_dir <- dirname(csv_filepath)
  bname  <- basename(csv_filepath)

  # 1. Same extract: swap only the dataset token in the filename.
  direct <- file.path(
    in_dir,
    sub(sprintf("_%s_", dataset), sprintf("_%s_", paired), bname, fixed = TRUE)
  )
  if (file.exists(direct)) return(list(dataset = paired, path = direct))

  # 2. Any extract of the paired dataset for the same country + source.
  m <- regmatches(bname, regexec("^(mwi|zim)_(db|mb)_", bname, ignore.case = TRUE))[[1]]
  if (length(m) == 0) return(list(dataset = paired, path = NULL))

  pattern <- sprintf(
    "^%s%s_(\\d{12}|\\d{8}|\\d{4}-\\d{2}-\\d{2})\\.csv$",
    tolower(m[1]), paired
  )
  candidates <- sort(list.files(in_dir, pattern = pattern, ignore.case = TRUE))
  if (length(candidates) == 0) return(list(dataset = paired, path = NULL))

  if (length(candidates) > 1) {
    log_info(
      "Paired-file lookup: %d %s extracts found; using the most recent (%s).",
      length(candidates), paired, candidates[length(candidates)]
    )
  }
  list(dataset = paired, path = file.path(in_dir, candidates[length(candidates)]))
}

paired_info <- .resolve_paired_csv(CSV_FILEPATH, DATASET)

if (is.null(paired_info$dataset)) {
  log_info("Paired file : none (dataset '%s' has no admissions/discharges pair).", DATASET)
} else if (is.null(paired_info$path)) {
  log_warn(
    paste("Paired file : %s dataset not found in '%s'.",
          "Cross-file checks (e.g. Module 02 uid repair confirmation) will report 'unchecked'."),
    paired_info$dataset, dirname(CSV_FILEPATH)
  )
} else {
  log_info("Paired file : %s", paired_info$path)
}

# =============================================================================
# LOAD DICTIONARY
# =============================================================================

if (!file.exists(DICT_FILEPATH)) {
  stop(sprintf(
    "Dictionary not found: '%s'\n  Run 00_build_dictionary/00_build_dictionary_v8.r first.",
    DICT_FILEPATH
  ))
}

dict_variables <- readxl::read_excel(DICT_FILEPATH, sheet = "Variables") %>%
  janitor::clean_names()
dict_value_maps <- readxl::read_excel(DICT_FILEPATH, sheet = "ValueMaps") %>%
  janitor::clean_names()

log_info(
  "Dictionary loaded: %d variables | %d value-map rows",
  nrow(dict_variables), nrow(dict_value_maps)
)

# =============================================================================
# HELPER: EXTRACT FEATURE LISTS FROM DICTIONARY
# =============================================================================

#' Return raw_value_column names for a given r_type (plus KEY_COLS)
#'
#' @param r_type_filter  One of "numeric", "boolean", "categorical", "object",
#'                       "datetime"
#' @param include_keys   Prepend KEY_COLS (default TRUE)
cols_of_type <- function(r_type_filter, include_keys = TRUE) {
  cols <- dict_variables %>%
    filter(
      r_type == r_type_filter,
      use_in_analysis == TRUE,
      !is.na(raw_value_column)
    ) %>%
    pull(raw_value_column) %>%
    unique()
  if (include_keys) cols <- unique(c(KEY_COLS, cols))
  return(cols)
}

# =============================================================================
# PRIMARY KEY COLUMNS  (always present in every dataset)
# =============================================================================

KEY_COLS <- c("facility", "uid", "uniquekey")

# Extra metadata columns present in PHC and some maternal files.
# (normalised column names after Module 01 standardisation)
# These may appear as leading OR trailing columns depending on the CSV export;
# they are carried through the pipeline as-is without validation or cleaning.
#
# Column positions per file:
#   phc_admissions              - script_version is the 1st column (leading)
#   phc_discharges              - script_version is the 1st column (leading)
#   combined_maternity_outcomes - scriptid + script_version are the 1st two columns (leading)
#   dhis2_maternal_outcomes     - script_version is the 1st column (leading);
#                                 scriptid appears as a trailing column
#   maternity_completeness      - script_version + scriptid are trailing columns
EXTRA_META_COLS <- switch(DATASET,
  phc_admissions              = c("scriptversion"),
  phc_discharges              = c("scriptversion"),
  combined_maternity_outcomes = c("scriptversion", "scriptid"),
  dhis2_maternal_outcomes     = c("scriptversion", "scriptid"),
  maternity_completeness      = c("scriptversion", "scriptid"),
  # neolab: ZIM has script_version as leading column; MWI has it trailing.
  # Both have scriptid as a trailing column.
  neolab                      = c("scriptversion", "scriptid"),
  # baseline: script_version + scriptid appear as trailing columns
  baseline                    = c("scriptversion", "scriptid"),
  # infections: script_version leading + scriptid trailing; review_number and
  # completed_time are kept as regular data columns (not stripped as metadata)
  infections                  = c("scriptversion", "scriptid"),
  # twenty_8_day_follow_up: script_version + scriptid trailing
  twenty_8_day_follow_up      = c("scriptversion", "scriptid"),
  character(0) # all other datasets: no extra metadata columns
)

# Dataset-specific timestamp columns included in the datetime frame
TIMESTAMP_COLS <- switch(DATASET,
  admissions = c(
    "ingestedat", "startedat", "completedat"
  ),
  discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  maternal_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  phc_admissions = c(
    "ingestedat", "startedat", "completedat"
  ),
  phc_discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  combined_maternity_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  dhis2_maternal_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  maternity_completeness = c(
    "ingestedat", "startedat", "completedat"
  ),
  joined_admissions_discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  neolab = c(
    "ingestedat", "startedat", "completedat"
  ),
  # baseline: combined admission+discharge form — carries standard system timestamps only.
  # DateTimeDischarge, DateTimeDeath etc. are clinical datetime variables handled by
  # the dictionary and Module 14, not system metadata timestamps.
  baseline = c(
    "ingestedat", "startedat", "completedat"
  ),
  # infections: also has completed_time (wall-clock completion) but that is kept as a
  # regular data column rather than a system timestamp.
  infections = c(
    "ingestedat", "startedat", "completedat"
  ),
  twenty_8_day_follow_up = c(
    "ingestedat", "startedat", "completedat"
  )
)

# =============================================================================
# FEATURE LISTS  (derived from dictionary)
# =============================================================================

numeric_features <- cols_of_type("numeric")
bool_features <- cols_of_type("boolean")
cat_features <- cols_of_type("categorical")
obj_features <- cols_of_type("object")
dt_features <- unique(c(KEY_COLS, TIMESTAMP_COLS, cols_of_type("datetime",
  include_keys = FALSE
)))

log_info(
  "Feature lists: num=%d | bool=%d | cat=%d | obj=%d | dt=%d",
  length(numeric_features), length(bool_features),
  length(cat_features), length(obj_features), length(dt_features)
)

# =============================================================================
# WEIGHT COLUMNS  (kg -> g conversion in Module 11)
# =============================================================================

weight_cols <- dict_variables %>%
  filter(!is.na(weight_unit), tolower(weight_unit) == "grams") %>%
  pull(question_key) %>%
  unique()

log_info("Weight columns (kg->g): %s", paste(weight_cols, collapse = ", "))

# =============================================================================
# PII COLUMNS  (from confidential flag in dictionary)
# =============================================================================
# Used by Module 00a instead of the hardcoded list.
# raw_value_column + raw_label_column for every confidential variable.

pii_columns <- dict_variables %>%
  filter(confidential == TRUE) %>%
  select(raw_value_column, raw_label_column) %>%
  tidyr::pivot_longer(everything(), values_to = "col_name") %>%
  filter(!is.na(col_name)) %>%
  pull(col_name) %>%
  unique()

log_info("PII columns from dictionary: %d", length(pii_columns))

# =============================================================================
# HARMONISED NAME MAP  (question_key -> harmonised_variable_name)
# Used by Module 00b to rename columns in the final clean dataset.
# =============================================================================

harmonised_name_map <- dict_variables %>%
  filter(
    !is.na(harmonised_variable_name),
    use_in_analysis == TRUE
  ) %>%
  select(question_key, harmonised_variable_name) %>%
  deframe() # named character vector: names=question_key, values=harmonised

log_info("Harmonised name map: %d entries", length(harmonised_name_map))

# =============================================================================
# RANGE LOOKUP  (for Module 11 numeric validation)
# =============================================================================

range_lookup <- dict_variables %>%
  filter(
    r_type == "numeric",
    !is.na(suggested_plausible_min) | !is.na(suggested_plausible_max)
  ) %>%
  select(question_key, suggested_plausible_min, suggested_plausible_max) %>%
  rename(min = suggested_plausible_min, max = suggested_plausible_max)

log_info("Range lookup entries: %d", nrow(range_lookup))

# =============================================================================
# VALUE MAP LIST  (for Module 04 dictionary-based value cleaning)
# =============================================================================
# Nested list: question_key -> list(allowed_codes, canonical_codes,
#                                   label_to_code, code_to_canonical)
#   allowed_codes     : character vector of valid raw_code values
#   canonical_codes   : character vector of valid canonical_code values (the
#                       harmonisation targets Module 04 should emit)
#   label_to_code     : named list  option_label -> canonical_code
#   code_to_canonical : named list  raw_code     -> canonical_code
#                       (lets Module 04 convert a raw code to its canonical form
#                       and underpins case-insensitive matching)

value_map_list <- dict_value_maps %>%
  group_by(question_key) %>%
  group_map(function(rows, key) {
    allowed   <- unique(na.omit(rows$raw_code))
    canonical <- unique(na.omit(rows$canonical_code))
    lbl_map <- setNames(
      as.list(rows$canonical_code),
      rows$option_label
    )
    lbl_map <- lbl_map[!is.na(names(lbl_map)) & names(lbl_map) != ""]
    # raw_code -> canonical_code (drop rows with missing raw_code or canonical)
    c2c_keep <- !is.na(rows$raw_code) & !is.na(rows$canonical_code) &
                rows$raw_code != ""  & rows$canonical_code != ""
    code_map <- setNames(
      as.list(rows$canonical_code[c2c_keep]),
      rows$raw_code[c2c_keep]
    )
    list(
      allowed_codes     = allowed,
      canonical_codes   = canonical,
      label_to_code     = lbl_map,
      code_to_canonical = code_map
    )
  }) %>%
  # Use group_keys() to extract names in the same sorted order that group_map()
  # processes groups.  Previously used unique(dict_value_maps$question_key) which
  # preserves original file order -- if that differed from group_map's sorted order
  # the names would be silently misassigned.
  setNames(
    dict_value_maps %>%
      group_by(question_key) %>%
      group_keys() %>%
      pull(question_key)
  )

log_info("Value map list: %d keys", length(value_map_list))

# =============================================================================
# CANONICAL CONFIGURATION OBJECT
# =============================================================================

cfg <- list(
  # Identity
  country = COUNTRY,
  dataset = DATASET,
  data_source = DATA_SOURCE, # "database" or "metabase"

  # File paths
  csv_filepath   = CSV_FILEPATH,
  dict_filepath  = DICT_FILEPATH,

  # Paired admissions/discharges raw CSV for cross-file checks (Module 02).
  # Both are NULL when the dataset has no pair or the file is absent.
  paired_dataset      = paired_info$dataset,
  paired_csv_filepath = paired_info$path,

  output_dir     = OUTPUT_DIR,        # base output/ directory
  run_output_dir = RUN_OUTPUT_DIR,    # per-run subfolder (output/<file_stem>/)
  file_stem      = file_stem,         # input CSV stem (no extension)
  output_csv     = OUTPUT_CSV,
  output_rds     = OUTPUT_RDS,
  report_dir     = REPORT_DIR,

  # Feature lists
  num = numeric_features,
  bool = bool_features,
  cat = cat_features,
  obj = obj_features,
  dt = dt_features,

  # Extra metadata columns (PHC / combined maternity leading columns).
  # Stored here for reference; Module 01 handles the actual drop of raw
  # metadata column names via its own internal list.
  extra_meta_cols = EXTRA_META_COLS,

  # Validation helpers
  weight_cols = weight_cols,
  range_lookup = range_lookup, # tibble: question_key, min, max
  value_map_list = value_map_list, # nested list for Module 04

  # Module 13 optional configuration.
  # value_mappings : named list of alias -> canonical mappings applied per column
  #   during categorical validation (Step 1 of validate_categorical).
  #   Format: list(column_base = list(canonical = c("alias1", "alias2")))
  #   Leave as list() to skip this step.
  # values_to_delete : named list of known-bad values to force-NA per column
  #   during categorical validation (Step 3 of validate_categorical).
  #   Format: list(column_base = c("bad_value_1", "bad_value_2"))
  #   Leave as list() to skip this step.
  value_mappings = list(),
  values_to_delete = list(),

  # PII & harmonisation
  pii_columns = pii_columns, # vector of column names to drop
  harmonised_map = harmonised_name_map, # named vector for Module 00b

  # Module 02: characters treated as a mistyped hyphen in a uid.
  uid_repair_separators = UID_REPAIR_SEPARATORS,

  # Module 01: raw columns to rename to avoid colliding with a reserved
  # system key column (facility/uid/uniquekey) after suffix stripping.
  # NULL when the current dataset has no known collision.
  reserved_column_renames = RESERVED_COLUMN_RENAMES[[DATASET]],

  # Module 16: NA Reason Coding
  neotree_scripts_dir = NEOTREE_SCRIPTS_DIR, # path to neotree_scripts/

  # Output file flags (set in User Configuration block above)
  save_deidentified      = SAVE_DEIDENTIFIED,
  save_stage1_checkpoint = SAVE_STAGE1_CHECKPOINT,
  save_harmonised        = SAVE_HARMONISED,
  save_na_coded          = SAVE_NA_CODED,
  save_na_reasons_long   = SAVE_NA_REASONS_LONG,

  # Module 10: deduplication behaviour
  # TRUE  = skip Stage 2 (patient-level dedup) -- used for longitudinal datasets
  #         where multiple rows per patient are by design (infections, neolab).
  # FALSE = run both Stage 1 and Stage 2 (default for all other datasets).
  skip_dedup_stage2 = SKIP_DEDUP_STAGE2,

  # Module 14a: resolve missing neolab datebct from raw admissions file.
  # TRUE  = attempt to fill NA datebct.value by joining to the admissions CSV
  #         on uid + facility and using datetimeadmission as a proxy date.
  #         Adds datebct_resolved (POSIXct) and datebct_source (character) columns.
  # FALSE = skip; no new columns added.
  # Only has any effect when dataset == "neolab".
  resolve_neolab_datebct = RESOLVE_NEOLAB_DATEBCT
)

log_info(
  paste(
    "Config ready: COUNTRY=%s | DATASET=%s | SOURCE=%s |",
    "num=%d | bool=%d | cat=%d | obj=%d | dt=%d |",
    "pii_cols=%d | weight_cols=%d | range_entries=%d | extra_meta_cols=%d"
  ),
  toupper(cfg$country), cfg$dataset, cfg$data_source,
  length(cfg$num), length(cfg$bool),
  length(cfg$cat), length(cfg$obj), length(cfg$dt),
  length(cfg$pii_columns), length(cfg$weight_cols),
  nrow(cfg$range_lookup), length(cfg$extra_meta_cols)
)
log_info(
  "Output flags: deidentified=%s | stage1=%s | harmonised=%s | na_coded=%s | na_reasons_long=%s | skip_dedup_stage2=%s | resolve_neolab_datebct=%s",
  cfg$save_deidentified, cfg$save_stage1_checkpoint, cfg$save_harmonised,
  cfg$save_na_coded, cfg$save_na_reasons_long, cfg$skip_dedup_stage2,
  cfg$resolve_neolab_datebct
)

# =============================================================================
# DATA DICTIONARY COVERAGE CHECK
# =============================================================================
# Reads just the header row of the raw CSV and checks whether every data
# column is covered by the dictionary (dict_variables).
# Columns present in the CSV but absent from the dictionary will pass through
# uncleaned -- no type coercion, no value validation, no NA reason coding.
# A warning is printed to the console AND written to the log so the issue
# is visible regardless of whether the user is watching the log file.
# =============================================================================

.check_dict_coverage <- function() {
  raw_cols <- tryCatch(
    names(readr::read_csv(cfg$csv_filepath, n_max = 0, show_col_types = FALSE)),
    error = function(e) {
      log_warn("Dict coverage check: could not read '%s' — %s", cfg$csv_filepath, e$message)
      return(NULL)
    }
  )
  if (is.null(raw_cols)) return(invisible(character(0)))

  # Columns always present and handled outside the dictionary
  system_cols <- tolower(unique(c(
    "uid", "facility", "uniquekey",
    "startedat", "completedat", "ingestedat",
    "startedatdischarge", "completedatdischarge", "ingestedatdischarge",
    "scriptversion", "scriptid",
    cfg$extra_meta_cols
  )))

  # Exclude .parentKey columns (dropped by Module 01) and system columns
  data_cols <- raw_cols[
    !grepl("\\.parentKey$", raw_cols, ignore.case = TRUE) &
    !tolower(raw_cols) %in% system_cols
  ]

  # All column names the dictionary accounts for
  known_cols <- union(
    na.omit(dict_variables$raw_value_column),
    na.omit(dict_variables$raw_label_column)
  )

  undocumented <- data_cols[!data_cols %in% known_cols]

  if (length(undocumented) == 0) {
    log_info(
      "Dict coverage check: all %d data columns are in the dictionary.",
      length(data_cols)
    )
  } else {
    msg <- paste(undocumented, collapse = "\n    ")
    log_warn(
      paste(
        "Dict coverage check: %d column(s) in the raw CSV are NOT in the dictionary.",
        "They will pass through uncleaned (no type coercion, no value validation).",
        "Download updated data keys from the web editor and rebuild the dictionary.",
        "Undocumented columns:\n    %s"
      ),
      length(undocumented), msg
    )
    cat(sprintf(
      paste0(
        "\n",
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n",
        "!! DICT COVERAGE WARNING: %d undocumented column(s) found     !!\n",
        "!! Download updated data keys and rebuild the dictionary.     !!\n",
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n",
        "%s\n\n"
      ),
      length(undocumented),
      paste0("  - ", undocumented, collapse = "\n")
    ))

    # Save to file in the report directory (or run output dir if reports suppressed)
    out_dir <- if (!is.null(cfg$report_dir)) cfg$report_dir else cfg$run_output_dir
    out_path <- file.path(out_dir, "00c_undocumented_columns.txt")
    writeLines(
      c(
        sprintf("Undocumented columns — %s x %s — %s",
                cfg$country, cfg$dataset, format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Input file : %s", cfg$csv_filepath),
        sprintf("Dictionary : %s", cfg$dict_filepath),
        sprintf("Total data columns in CSV        : %d", length(data_cols)),
        sprintf("Columns missing from dictionary  : %d", length(undocumented)),
        "",
        "These columns will pass through uncleaned (no type coercion, no value",
        "validation, no NA reason coding). Download updated data keys from the",
        "web editor and rebuild the dictionary to cover them.",
        "",
        "--- Undocumented columns ---",
        undocumented
      ),
      out_path
    )
    log_info("Undocumented columns saved to: %s", out_path)
  }
  invisible(undocumented)
}

cfg$undocumented_cols <- .check_dict_coverage()
