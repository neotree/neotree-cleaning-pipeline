# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 01: Standardise Column Headers
# =============================================================================
# PURPOSE:
#   Normalises the column names of the de-identified data and drops app
#   metadata columns that are not part of the clinical data.
#
# METHOD:
#   1. Normalise every column name:
#        - strip leading/trailing whitespace
#        - remove whitespace around dots  (" . " -> ".")
#        - remove all remaining spaces and underscores
#          ("unique_key" -> "uniquekey", "Baby Cry.Value" -> "babycry.value")
#        - convert to lowercase
#   2. Rename columns listed in cfg$reserved_column_renames, whose
#      standardised name collides with a reserved system key column.
#   3. Drop all `.parentKey` columns.
#   4. Drop any column listed in M01_META_COLS_TO_DROP (empty by default).
#      Other metadata columns (scriptid, transformed, etc.) are kept.
#
# INPUTS:
#   df_raw  - de-identified data.frame produced by Module 00a
#
# OUTPUTS:
#   df      - data.frame with standardised column names and metadata columns
#             dropped
#   Report  - cfg$report_dir/01_column_standardisation_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("00a_pii_detection_removal/00a_pii_detection_removal.r")
#   source("01_standardise_column_headers/01_standardise_column_headers.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Metadata columns to drop regardless of dataset ----------------------------
# Empty: session-level metadata columns are kept.  The name differs from
# EXTRA_META_COLS so that the dataset-specific EXTRA_META_COLS set by
# 00_setup.r in the global environment is not overwritten.
M01_META_COLS_TO_DROP <- character(0)

# -- Function ------------------------------------------------------------------

#' Standardise Column Headers and Drop Metadata Columns
#'
#' @param df              A data.frame with raw column names.
#' @param report_filepath Optional path for a text report.
#' @return                The same data.frame with cleaned column names and
#'                        metadata columns removed.
clean_columns <- function(df, report_filepath = NULL) {

  # -- Step 1: Normalise names -------------------------------------------------
  clean_name <- function(name) {
    name <- trimws(name)                         # Strip leading/trailing whitespace
    name <- gsub("\\s*\\.\\s*", ".", name)       # Normalise spaces around dots
    name <- gsub("\\s+", " ", name)              # Collapse multiple spaces
    name <- gsub(" ", "", name)                  # Remove remaining spaces
    name <- gsub("_", "", name)                  # Remove underscores
    name <- tolower(name)                        # Lowercase
    return(name)
  }

  original_names  <- names(df)
  cleaned_names   <- vapply(original_names, clean_name, character(1))
  names(df)       <- cleaned_names
  n_renamed       <- sum(cleaned_names != original_names)

  # -- Step 1b: Resolve collisions with reserved system key columns -----------
  # A raw data field whose standardised name equals "facility"/"uid"/
  # "uniquekey" (or shares that prefix once its .value/.label suffix is
  # stripped later) would otherwise be discarded by Module 07's prefix-based
  # duplicate-column logic, which keeps the system column.
  # cfg$reserved_column_renames (set per dataset in 00_setup.r) lists the
  # collisions to rename.
  reserved_renames <- if (exists("cfg")) cfg$reserved_column_renames else NULL
  n_reserved_renamed <- 0L
  if (!is.null(reserved_renames) && length(reserved_renames) > 0) {
    hits <- names(df) %in% names(reserved_renames)
    if (any(hits)) {
      old_hit_names <- names(df)[hits]
      names(df)[hits] <- unname(reserved_renames[old_hit_names])
      n_reserved_renamed <- length(old_hit_names)
      log_info(
        "clean_columns: renamed %d column(s) to avoid collision with a reserved system key column: %s",
        n_reserved_renamed,
        paste(sprintf("%s -> %s", old_hit_names, reserved_renames[old_hit_names]), collapse = ", ")
      )
    }
  }

  # -- Step 2: Drop .parentKey columns ----------------------------------------
  parentkey_cols  <- grep("\\.parentkey$", names(df), value = TRUE,
                          ignore.case = TRUE)
  n_parentkey     <- length(parentkey_cols)
  if (n_parentkey > 0) {
    df <- df[, !names(df) %in% parentkey_cols, drop = FALSE]
    log_info("clean_columns: %d .parentKey column(s) dropped.", n_parentkey)
  }

  # -- Step 3: Drop extra metadata columns ------------------------------------
  meta_drop       <- intersect(names(df), M01_META_COLS_TO_DROP)
  n_meta          <- length(meta_drop)
  if (n_meta > 0) {
    df <- df[, !names(df) %in% meta_drop, drop = FALSE]
    log_info("clean_columns: %d extra metadata column(s) dropped: %s",
             n_meta, paste(meta_drop, collapse = ", "))
  }

  n_total_dropped <- n_parentkey + n_meta

  log_info(
    "clean_columns: %d/%d column names standardised | %d columns dropped (%d parentKey + %d metadata) | final: %d cols",
    n_renamed, length(original_names),
    n_total_dropped, n_parentkey, n_meta,
    ncol(df)
  )

  # -- Write report ------------------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 01 - Column Standardisation Report",
        "==========================================",
        sprintf("Run timestamp            : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                  : %s", toupper(cfg$country)),
        sprintf("Dataset                  : %s", cfg$dataset),
        sprintf("Source file              : %s", cfg$csv_filepath),
        "",
        sprintf("Columns in raw file      : %d", length(original_names)),
        sprintf("Column names standardised: %d", n_renamed),
        sprintf("Reserved-collision renames: %d", n_reserved_renamed),
        sprintf(".parentKey cols dropped  : %d", n_parentkey),
        sprintf("Metadata cols dropped    : %d", n_meta),
        sprintf("Columns after cleaning   : %d", ncol(df)),
        ""
      )

      if (n_parentkey > 0) {
        lines <- c(lines,
          "=== .parentKey Columns Dropped ===",
          paste0("  - ", parentkey_cols),
          "")
      }

      if (n_meta > 0) {
        lines <- c(lines,
          "=== Metadata Columns Dropped ===",
          paste0("  - ", meta_drop),
          "")
      }

      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write Module 01 report: %s", e$message)
    })
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
# PII guard.  This module never reads the raw file: df_raw must be the
# de-identified object produced by Module 00a, and assert_pii_removed()
# (00_setup.r) confirms that before anything else happens.
if (!exists("df_raw")) {
  stop(paste(
    "Module 01: df_raw not found, so Module 00a (PII removal) has not run in this",
    "session. Module 01 does not load the raw CSV itself. Run run_pipeline.r",
    "(or run_all.r), or source 00a_pii_detection_removal.r first."
  ), call. = FALSE)
}
assert_pii_removed(df_raw, stage = "01_input", check_run_id = TRUE)

report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "01_column_standardisation_report.txt") else NULL

df <- clean_columns(df_raw, report_filepath = report_path)
log_info("Module 01 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
