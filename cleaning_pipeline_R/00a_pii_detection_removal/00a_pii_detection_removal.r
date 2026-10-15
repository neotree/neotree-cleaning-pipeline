# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00a: PII Detection, Flagging, and Removal
# =============================================================================
# PURPOSE:
#   Runs immediately after 00_setup and before any cleaning step.  Detects,
#   flags and removes columns and values that contain Personally Identifiable
#   Information (PII).
#
# METHOD:
#   1. Load the raw CSV and normalise column names.  Both source formats
#      ("database" and "metabase") are reduced to the same lowercase compact
#      names, so all detection logic is independent of the source.
#   2. Remove columns flagged confidential = TRUE in the data dictionary
#      (cfg$pii_columns).
#   3. Remove further columns whose names match PII_TIER2_PATTERNS, the union
#      of the dictionary's PII_Patterns sheet and the built-in defaults.
#   4. Flag quasi-identifier columns (PII_QUASI_COL_PATTERNS).  These are
#      listed in the audit report and are not removed.
#   5. Scan the values of the remaining columns against PII_VALUE_PATTERNS
#      (phone numbers, email addresses, hospital number patterns, national ID
#      numbers).  Values are trimmed before matching and matches are set to NA.
#      Columns in PII_VALUE_SCAN_EXEMPT (key and system columns such as uid,
#      facility, uniquekey and the system timestamps) are scanned but not
#      redacted, because a uid set to NA is removed by Module 02 as an empty
#      uid.  Matches in these columns are reported as counts only.
#   6. Write the PII audit report.
#   7. Optionally save a de-identified CSV (cfg$save_deidentified).
#   8. Write the completion marker.  Any marker left by an earlier run is
#      deleted at the start of this module.  Later modules call
#      assert_pii_removed(), which checks the marker.
#
#   The pattern constants (PII_FALLBACK_PATTERNS_DEFAULT, PII_VALUE_PATTERNS,
#   PII_VALUE_SCAN_EXEMPT) are defined in 00_setup.r.  The raw input file is
#   never modified.
#
# INPUTS:
#   cfg$csv_filepath  - path to the raw CSV
#   cfg$pii_columns   - column names with confidential == TRUE in the dictionary
#   cfg$data_source   - "database" or "metabase" (for logging only)
#   cfg               - config list (output paths, report dir)
#
# OUTPUTS:
#   df_raw_deidentified  - de-identified data.frame (assigned globally)
#   PII audit report     - cfg$report_dir/00a_pii_audit_report.txt
#   De-identified CSV    - <file stem>_deidentified.csv in the run output folder
#                          (only when cfg$save_deidentified is TRUE)
#   Completion marker    - PII_MARKER_PATH
#
# USAGE (standalone or as part of run_pipeline.R):
#   source("00_setup/00_setup.r")
#   source("00a_pii_detection_removal/00a_pii_detection_removal.r")
# =============================================================================

source("00_setup/00_setup.r")

# =============================================================================
# PII DETECTION CONFIGURATION
# =============================================================================

# -- Tier 2 column-name patterns ---------------------------------------------
# PII_TIER2_PATTERNS is built in 00_setup.r as the union of the dictionary's
# PII_Patterns sheet and PII_FALLBACK_PATTERNS_DEFAULT.
if (is.null(PII_SHEET_PATTERNS)) {
  log_warn("00a_pii: PII_Patterns sheet not found in %s -- using built-in default patterns only.",
           basename(cfg$dict_filepath))
} else {
  log_info("00a_pii: %d Tier 2 patterns from the PII_Patterns sheet in %s + built-in defaults = %d unique.",
           length(PII_SHEET_PATTERNS), basename(cfg$dict_filepath), length(PII_TIER2_PATTERNS))
}
PII_FALLBACK_PATTERNS <- PII_TIER2_PATTERNS

# A completion marker from an earlier run must not survive a failed run.
if (file.exists(PII_MARKER_PATH)) {
  file.remove(PII_MARKER_PATH)
  log_info("00a_pii: previous completion marker removed: %s", PII_MARKER_PATH)
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
  "matagedate"    # maternal age in hours (calculated from DOB) -- precise enough
                  # to increase re-identification risk when combined with other fields
)

# -- Value-level patterns and key/system exemptions ---------------------------
# PII_VALUE_PATTERNS and PII_VALUE_SCAN_EXEMPT are defined in 00_setup.r.
# Key/system columns are exempt from redaction only: they are still scanned and
# any match is reported.

# =============================================================================
# COLUMN NAME NORMALISATION
# =============================================================================
# Converts both "database" and "metabase" column naming schemes to a
# consistent lowercase compact form used throughout the pipeline.
#
# Examples:
#   DB:        "BabyCryTriage.value"    -> "babycrytriage.value"
#              "unique_key"             -> "uniquekey"
#   Metabase:  "Baby Cry Tria Ge. Value"-> "babycrytriage.value"
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
  # Key/system columns are scanned but never redacted: a uid set to NA is
  # dropped by Module 02 as an empty uid.  Matches on those columns are
  # collected for the audit report.
  exempt_present <- intersect(names(df), PII_VALUE_SCAN_EXEMPT)
  exempt_hits    <- list()

  if (length(exempt_present) > 0)
    log_info("00a_pii: %d key/system column(s) exempt from value-level redaction: %s",
             length(exempt_present), paste(exempt_present, collapse = ", "))

  for (col in names(df)) {
    vals       <- df[[col]]
    n_redacted <- 0L
    is_exempt  <- col %in% PII_VALUE_SCAN_EXEMPT

    for (pat_name in names(PII_VALUE_PATTERNS)) {
      pattern  <- PII_VALUE_PATTERNS[[pat_name]]
      pii_mask <- pii_value_hits(vals, pattern)   # trims before matching
      n_match  <- sum(pii_mask)
      if (n_match == 0) next

      if (is_exempt) {
        # Report counts only, never the matched values.
        exempt_hits[[length(exempt_hits) + 1L]] <- list(
          col = col, pattern = pat_name, n = n_match
        )
        log_warn(
          paste("00a_pii: %d value(s) in key/system column '%s' match '%s'.",
                "NOT redacted (redaction would destroy the record) -- review the source file."),
          n_match, col, pat_name
        )
        next
      }

      df[[col]][pii_mask] <- NA_character_
      n_redacted          <- n_redacted + n_match
      log_info("  00a_pii: %d value(s) matching '%s' redacted in '%s'.",
               n_match, pat_name, col)
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

      lines <- c(lines, "",
        "=== Key/System Columns Exempt From Redaction ===",
        sprintf("  Exempt columns present in this dataset (%d): %s",
                length(exempt_present), paste(exempt_present, collapse = ", ")),
        "  These are scanned but never redacted. They are structural identifiers the",
        "  pipeline keys on, not free text: redacting one destroys the record rather",
        "  than protecting anyone (a uid set to NA is dropped by Module 02 as an",
        "  empty uid, removing the patient from the cleaned output).")
      if (length(exempt_hits) > 0) {
        lines <- c(lines, "",
          "  PATTERN MATCHES FOUND IN EXEMPT COLUMNS -- review the source file:",
          vapply(exempt_hits, function(h)
            sprintf("  - %-40s : %d value(s) matching '%s'", h$col, h$n, h$pattern),
            character(1)),
          "",
          "  Values are deliberately not printed here: if a match were genuine PII,",
          "  printing it would leak exactly what this module exists to remove.",
          "  Almost always these are legitimate identifiers that happen to look",
          "  numeric (e.g. an all-digit uid). Confirm before treating one as PII.")
      } else {
        lines <- c(lines, "  No pattern matches found in exempt columns.")
      }

      writeLines(unlist(lines), report_filepath)
      log_info("00a_pii: audit report written to %s", report_filepath)
    }, error = function(e) {
      log_warn("Could not write PII report: %s", e$message)
    })
  }

  attr(df, "neotree_pii_n_removed")  <- length(removed_cols)
  attr(df, "neotree_pii_n_redacted") <- total_redacted
  return(df)
}

# =============================================================================
# RUN MODULE 00a
# =============================================================================

log_info(
  "Module 00a: Loading raw CSV [source=%s]: %s",
  cfg$data_source, cfg$csv_filepath
)

pii_input_path <- cfg$csv_filepath   # the raw input the marker must describe

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

# -- Completion marker --------------------------------------------------------
# Written only after every removal and redaction step has succeeded.  The run
# id is also attached to df_raw so that Module 01 can confirm it received the
# object this run produced.  The id is built from the clock and process id, not
# sample(), so the random number stream is left untouched.
pii_run_id <- sprintf("%s-%d", format(Sys.time(), "%Y%m%d%H%M%OS3"), Sys.getpid())
write_pii_marker(
  input_path        = pii_input_path,
  run_id            = pii_run_id,
  n_cols_removed    = attr(df_raw, "neotree_pii_n_removed"),
  n_values_redacted = attr(df_raw, "neotree_pii_n_redacted")
)
attr(df_raw, "neotree_pii_run_id") <- pii_run_id

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
