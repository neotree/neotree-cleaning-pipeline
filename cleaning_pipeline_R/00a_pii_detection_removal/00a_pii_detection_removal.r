# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00a: PII Detection, Flagging, and Removal
# =============================================================================
# PURPOSE:
#   Runs immediately after 00_setup (and before any cleaning steps).
#   Detects, flags, and removes columns and values that contain Personally
#   Identifiable Information (PII), in accordance with data protection best
#   practice and research ethics requirements.
#
#   Neotree data is clinical / observational research data from hospitals in
#   Malawi and Zimbabwe.  The following types of PII are targeted:
#
#   PRIMARY SOURCE (data dictionary):
#     - Any column where confidential = TRUE in the dictionary is removed.
#       This is loaded as cfg$pii_columns by 00_setup.R.
#
#   FALLBACK PATTERNS (applied to any column NOT already covered above):
#     Direct identifiers -- always removed:
#       - Names:         columns matching *name.value
#       - Phone/cell:    columns matching *cell.value, *phone.value
#       - Addresses:     columns matching *address.value
#       - HCW IDs:       columns matching *hcwid*
#       - Hospital #s:   columns matching *hospnum*
#       - Study IDs:     stuid (catches .value + .label), uidbid, uiddc, drid, neotreeid
#       Patterns are loaded from the PII_Patterns sheet in the data dictionary.
#       If that sheet is unavailable, built-in defaults are used as a fallback.
#
#   QUASI-IDENTIFIERS (flagged, NOT automatically removed):
#     - Village, district, province, tribe, ethnicity, religion, address
#     These are listed in the audit report for manual review.
#
#   VALUE-LEVEL SCANNING:
#     - Phone numbers (international, Zimbabwe and Malawi mobile formats)
#     - Email addresses
#     - NHS/hospital number patterns
#
# DATA SOURCE COMPATIBILITY:
#   This module handles both data source formats transparently:
#
#   "database"  - Direct PostgreSQL export
#     System columns : snake_case  (unique_key, started_at, completed_at)
#     Data columns   : CamelCase   (BabyCryTriage.value, Temperature.value)
#     .label meaning : Full question text (e.g. "Respiratory Rate (breaths/min)")
#
#   "metabase"  - Metabase export connected to the PostgreSQL database
#     System columns : Title Case with spaces (Unique Key, Started At)
#     Data columns   : Fragmented CamelCase (Baby Cry Tria Ge. Value)
#     .label meaning : Display value / coded label (same field as .value)
#
#   Both formats are normalised to identical lowercase compact column names
#   (e.g., babycryptriage.value) before any PII pattern matching, so all
#   detection logic works identically regardless of source.
#   The active source format is set via DATA_SOURCE in 00_setup.R.
#
# STRATEGY:
#   1. Load raw CSV and normalise column names (handles both source formats).
#   2. Remove columns flagged as confidential in the data dictionary.
#   3. Remove additional columns matching PII name patterns (fallback).
#   4. Flag quasi-identifier columns (no automatic removal).
#   5. Scan remaining columns for PII-like values, redact to NA.
#   6. Write a PII audit report.
#   7. Save a de-identified CSV for all downstream modules.
#
# IMPORTANT:
#   The original raw file is never modified.  A new de-identified CSV is
#   written to disk and handed to all subsequent pipeline modules.
#
# INPUTS:
#   cfg$csv_filepath  - path to the raw CSV
#   cfg$pii_columns   - column names from confidential==TRUE in data dictionary
#   cfg$data_source   - "database" or "metabase" (for logging only; both are
#                       handled identically after normalisation)
#   cfg               - config list (output paths, report dir)
#
# OUTPUTS:
#   df_raw_deidentified  - de-identified data.frame (assigned globally)
#   PII audit report     - written to cfg$report_dir/00a_pii_audit_report.txt
#   De-identified CSV    - saved with "_deidentified" suffix
#
# USAGE (standalone or as part of run_pipeline.R):
#   source("00_setup/00_setup.r")
#   source("00a_pii_detection_removal/00a_pii_detection_removal.r")
# =============================================================================

source("00_setup/00_setup.r")

# =============================================================================
# PII DETECTION CONFIGURATION
# =============================================================================

# -- Load Tier 2 patterns from the data dictionary's PII_Patterns sheet -------
# The data dictionary now embeds a PII_Patterns sheet (built by build_dictionary_v8.r)
# that serves as the single source of truth for all column-name patterns.
# This replaces the previous hardcoded PII_FALLBACK_PATTERNS constant.
#
# If the sheet is absent (e.g. older dictionaries), the function returns NULL
# and the built-in defaults below are used as a backward-compatible fallback.

load_pii_patterns <- function(dict_path) {
  tryCatch({
    pii_df <- readxl::read_excel(dict_path, sheet = "PII_Patterns")
    if (!is.null(pii_df) && "pattern" %in% names(pii_df) && nrow(pii_df) > 0) {
      log_info("00a_pii: %d Tier 2 patterns loaded from PII_Patterns sheet in %s",
               nrow(pii_df), basename(dict_path))
      return(pii_df$pattern)
    }
    return(NULL)
  }, error = function(e) {
    log_warn("00a_pii: Could not read PII_Patterns sheet from %s -- using defaults. (%s)",
             basename(dict_path), e$message)
    return(NULL)
  })
}

# -- Built-in defaults (used when PII_Patterns sheet is unavailable) ----------
PII_FALLBACK_PATTERNS_DEFAULT <- c(
  "name\\.value$",      # any *name.value  (baby name, mother name, etc.)
  "cell\\.value$",      # mobile/cell phone columns
  "phone\\.value$",     # landline/phone columns
  "address\\.value$",   # physical address columns
  "hcwid",              # healthcare worker ID (catches .value and .label)
  "hospnum",            # hospital patient number
  "neotreeid",          # internal Neotree patient ID
  "stuid",              # study/student HCW ID (catches both .value and .label)
  "uidbid\\.value$",    # baby unique ID
  "uiddc\\.value$",     # discharge unique ID
  "drid\\.value$"       # DR/practitioner ID
)

PII_FALLBACK_PATTERNS <- load_pii_patterns(cfg$dict_filepath)

if (is.null(PII_FALLBACK_PATTERNS)) {
  PII_FALLBACK_PATTERNS <- PII_FALLBACK_PATTERNS_DEFAULT
  log_warn("00a_pii: Using built-in default patterns (PII_Patterns sheet not found).")
}

# -- Quasi-identifier column patterns (flagged in report, NOT auto-removed) ---
PII_QUASI_COL_PATTERNS <- c(
  "village",
  "district",
  "province",
  "tribe\\.value$",
  "ethnicity\\.value$",
  "religion\\.value$",
  "address",
  "matagedate"    # maternal age in hours (auto-calculated from DOB) -- precise enough
                  # to increase re-identification risk when combined with other fields
)

# -- Value-level PII patterns (applied across remaining text columns) ---------
PII_VALUE_PATTERNS <- list(
  phone_international = "^\\+?[0-9]{7,15}$",
  phone_local_zw      = "^0[67][0-9]{8}$",    # Zimbabwe mobile (07xx, 06xx)
  phone_local_mwi     = "^0[89][0-9]{8}$",    # Malawi mobile   (08xx, 09xx)
  email               = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}",
  nhs_number          = "^[0-9]{3}[- ][0-9]{3}[- ][0-9]{4}$"
)

# =============================================================================
# COLUMN NAME NORMALISATION
# =============================================================================
# Converts both "database" and "metabase" column naming schemes to a
# consistent lowercase compact form used throughout the pipeline.
#
# Examples:
#   DB:        "BabyCryTriage.value"    -> "babycryptriage.value"
#              "unique_key"             -> "uniquekey"
#   Metabase:  "Baby Cry Tria Ge. Value"-> "babycryptriage.value"
#              "Unique Key"             -> "uniquekey"

clean_name_simple <- function(name) {
  name <- trimws(name)
  name <- gsub("\\s*\\.\\s*", ".", name)   # normalise spaces around dots
  name <- gsub("\\s+", "", name)           # remove all whitespace
  name <- gsub("_", "", name)              # remove underscores
  name <- tolower(name)
  name
}

# =============================================================================
# MAIN FUNCTION: remove_pii
# =============================================================================

#' Detect, Flag, and Remove PII from Raw Data
#'
#' @param df              Raw data.frame (columns will be normalised internally)
#' @param pii_columns     Character vector of normalised column names from the
#'                        data dictionary (cfg$pii_columns)
#' @param report_filepath Optional path for the PII audit report text file.
#' @return                De-identified data.frame with normalised column names.
remove_pii <- function(df,
                       pii_columns     = character(0),
                       report_filepath = NULL) {

  col_names     <- names(df)
  removed_cols  <- character(0)
  flagged_cols  <- character(0)
  redacted_vals <- list()

  # -- Step 1: Remove dictionary-defined PII columns (confidential == TRUE) ---
  dict_pii_present <- intersect(pii_columns, col_names)
  if (length(dict_pii_present) > 0) {
    removed_cols <- c(removed_cols, dict_pii_present)
    log_info("00a_pii: %d column(s) removed via data dictionary confidential flag.",
             length(dict_pii_present))
  }

  # -- Step 2: Fallback pattern matching on normalised column names ---------
  for (pattern in PII_FALLBACK_PATTERNS) {
    matches <- col_names[grepl(pattern, col_names, ignore.case = TRUE, perl = TRUE)]
    matches <- setdiff(matches, removed_cols)
    if (length(matches) > 0) {
      removed_cols <- c(removed_cols, matches)
      log_info("00a_pii: fallback pattern '%s' matched %d col(s): %s",
               pattern, length(matches), paste(matches, collapse = ", "))
    }
  }

  # -- Step 3: Flag quasi-identifier columns (report only, do not remove) ----
  for (pattern in PII_QUASI_COL_PATTERNS) {
    matches <- col_names[grepl(pattern, col_names, ignore.case = TRUE, perl = TRUE)]
    matches <- setdiff(matches, c(removed_cols, flagged_cols))
    if (length(matches) > 0)
      flagged_cols <- c(flagged_cols, matches)
  }
  if (length(flagged_cols) > 0)
    log_info("00a_pii: %d quasi-identifier column(s) flagged (not removed): %s",
             length(flagged_cols), paste(flagged_cols, collapse = ", "))

  # -- Step 4: Remove identified PII columns from data.frame ----------------
  removed_cols     <- unique(removed_cols)
  df               <- df[, !col_names %in% removed_cols, drop = FALSE]
  n_cols_remaining <- ncol(df)   # capture post-removal count for the audit report

  # -- Step 5: Value-level scan across remaining columns ---------------------
  for (col in names(df)) {
    vals       <- as.character(df[[col]])
    n_redacted <- 0L

    for (pat_name in names(PII_VALUE_PATTERNS)) {
      pattern  <- PII_VALUE_PATTERNS[[pat_name]]
      pii_mask <- grepl(pattern, vals, perl = TRUE) & !is.na(vals)
      n_match  <- sum(pii_mask)
      if (n_match > 0) {
        df[[col]][pii_mask] <- NA_character_
        n_redacted          <- n_redacted + n_match
        log_info("  00a_pii: %d value(s) matching '%s' redacted in '%s'.",
                 n_match, pat_name, col)
      }
    }

    if (n_redacted > 0) redacted_vals[[col]] <- n_redacted
  }

  # -- Step 6: PII audit report ---------------------------------------------
  total_redacted <- sum(unlist(redacted_vals))
  log_info(
    "00a_pii: %d col(s) removed | %d col(s) flagged | %d value(s) redacted",
    length(removed_cols), length(flagged_cols), total_redacted
  )

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 00a - PII Detection & Removal Audit Report",
        "==================================================",
        sprintf("Run timestamp             : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                   : %s", toupper(cfg$country)),
        sprintf("Dataset                   : %s", cfg$dataset),
        sprintf("Data source format        : %s", cfg$data_source),
        sprintf("Source file               : %s", cfg$csv_filepath),
        "",
        sprintf("Total columns removed     : %d", length(removed_cols)),
        sprintf("  From data dictionary      : %d", length(dict_pii_present)),
        sprintf("  From fallback patterns  : %d",
                length(removed_cols) - length(dict_pii_present)),
        sprintf("Columns flagged (quasi)   : %d", length(flagged_cols)),
        sprintf("Values redacted           : %d (across %d column(s))",
                total_redacted, length(redacted_vals)),
        sprintf("Columns remaining         : %d", n_cols_remaining),
        ""
      )

      lines <- c(lines, "=== Direct Identifier Columns Removed ===")
      if (length(removed_cols) > 0) {
        lines <- c(lines,
                   sprintf("  [dict]    %s", dict_pii_present),
                   sprintf("  [pattern] %s",
                           setdiff(removed_cols, dict_pii_present)))
      } else {
        lines <- c(lines, "  (none detected)")
      }

      lines <- c(lines, "",
        "=== Quasi-Identifiers Flagged (NOT removed -- review before sharing) ===")
      if (length(flagged_cols) > 0) {
        lines <- c(lines,
                   paste0("  - ", flagged_cols),
                   "",
                   "  ACTION REQUIRED: Review flagged columns before sharing data.")
      } else {
        lines <- c(lines, "  (none detected)")
      }

      lines <- c(lines, "", "=== Value-Level PII Redacted ===")
      if (total_redacted > 0) {
        lines <- c(lines,
                   sapply(names(redacted_vals), function(col)
                     sprintf("  - %-40s : %d value(s)", col, redacted_vals[[col]])))
      } else {
        lines <- c(lines, "  (none detected)")
      }

      writeLines(unlist(lines), report_filepath)
      log_info("00a_pii: audit report written to %s", report_filepath)
    }, error = function(e) {
      log_warn("Could not write PII report: %s", e$message)
    })
  }

  return(df)
}

# =============================================================================
# RUN MODULE 00a
# =============================================================================

log_info(
  "Module 00a: Loading raw CSV [source=%s]: %s",
  cfg$data_source, cfg$csv_filepath
)

df_raw <- readr::read_csv(
  cfg$csv_filepath,
  col_types      = readr::cols(.default = "c"),
  show_col_types = FALSE
)

log_info("Module 00a: Raw dimensions: %d rows x %d cols.", nrow(df_raw), ncol(df_raw))

# Normalise column names -- handles both "database" and "metabase" formats
names(df_raw) <- vapply(names(df_raw), clean_name_simple, character(1))

report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "00a_pii_audit_report.txt") else NULL

df_raw <- remove_pii(
  df              = df_raw,
  pii_columns     = cfg$pii_columns,
  report_filepath = report_path
)

# Save de-identified raw data (optional -- controlled by cfg$save_deidentified).
# PII removal always runs; this flag only controls whether the result is written
# to disk.  When FALSE, cfg$csv_filepath continues to point at the original raw
# file, so downstream modules read the (in-memory) de-identified data frame
# rather than reloading from disk.
if (isTRUE(cfg$save_deidentified)) {
  deidentified_csv <- file.path(
    cfg$run_output_dir,
    paste0(cfg$file_stem, "_deidentified.csv")
  )
  csv_saved <- tryCatch({
    readr::write_csv(df_raw, deidentified_csv, na = "")
    log_info("De-identified CSV saved: %s", deidentified_csv)
    TRUE
  }, error = function(e) {
    log_warn("Could not save de-identified CSV: %s", e$message)
    FALSE
  })
  # Update cfg$csv_filepath so downstream report entries reference the de-identified
  # file rather than the original raw input.
  if (csv_saved) cfg$csv_filepath <- deidentified_csv
} else {
  log_info("De-identified CSV skipped (SAVE_DEIDENTIFIED = FALSE).")
}

df_raw_deidentified <- df_raw

log_info(
  "Module 00a complete. De-identified dimensions: %d rows x %d cols.",
  nrow(df_raw_deidentified), ncol(df_raw_deidentified)
)
log_warn(
  paste(
    "REMINDER: Quasi-identifier columns (village, district, tribe, ethnicity,",
    "religion, address, matagedate) have been FLAGGED but NOT removed.",
    "Review %s before sharing this dataset."
  ),
  if (!is.null(report_path)) report_path else "the PII audit report"
)
