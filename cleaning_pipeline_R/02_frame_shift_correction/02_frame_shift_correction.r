# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 02: Frame Shift Correction
# =============================================================================
# PURPOSE:
#   Detects and removes rows affected by a critical data structure issue called
#   a "frame shift", where values are misaligned across columns such that the
#   uid field contains data that belongs in a different column entirely.
#
# DETECTION STRATEGY (revised):
#   A row is considered irrecoverably frame-shifted ONLY if its uid is empty,
#   NA, or a recognised null-equivalent string ("NA", "NULL", "na", etc.).
#
#   The previous rule -- dropping any uid without a hyphen -- was too aggressive.
#   Investigation of ZIM discharges showed that 116 legitimate patients have
#   8-character alphanumeric UIDs without a hyphen (e.g. "EC330587", "75DA0016").
#   These are real Neotree records from specific facilities where the hyphen
#   separator was never stored. Dropping them silently loses clinical data.
#
#   Non-standard but non-empty UIDs (no hyphen, very short, unusual characters)
#   are retained and logged in the report. Downstream modules -- in particular
#   the probabilistic admissions-discharges matching -- have access to multiple
#   clinical variables and are better placed to decide whether an unusual record
#   can be linked. Silent deletion at this stage is worse than a logged anomaly.
#
# UID REPAIR:
#   UIDs of the form "XXXX,YYYY" (comma in place of a hyphen, e.g. "CDDA,0484")
#   are repaired to "XXXX-YYYY" before any further processing. The comma is
#   almost certainly a data-entry substitution for the standard hyphen separator.
#
# INPUTS:
#   df  - data.frame after Module 01
#
# OUTPUTS:
#   df  - data.frame with genuinely empty-uid rows removed; comma UIDs repaired
#
# REPORT:
#   reports/02_frame_shift_report.txt
#   reports/02_frame_shift_dirty_rows.csv  (rows with empty/NA uid only)
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("02_frame_shift_correction/02_frame_shift_correction.r")
# =============================================================================

source("00_setup/00_setup.r")

#' Remove Frame-Shifted Rows and Repair Malformed UIDs
#'
#' @param df              A data.frame with a "uid" column.
#' @param report_filepath Optional path for a plain-text report.
#' @param csv_filepath    Optional path to save removed dirty rows.
#' @return                Cleaned data.frame: empty-uid rows removed, comma
#'                        UIDs repaired, non-standard UIDs logged.
remove_frame_shift <- function(df,
                               report_filepath = NULL,
                               csv_filepath    = NULL) {

  n_input <- nrow(df)

  if (!"uid" %in% names(df)) {
    log_warn("remove_frame_shift: 'uid' column not found. Skipping.")
    return(df)
  }

  uid_chr <- trimws(as.character(df$uid))

  # -- Step 1: Repair comma-separated UIDs (e.g. "CDDA,0484" -> "CDDA-0484") --
  # A comma in a uid is almost certainly a mistyped hyphen.  Pattern:
  # 3-6 alphanumeric chars, a comma, then more alphanumeric chars.
  comma_mask <- grepl("^[A-Za-z0-9]{3,6},[A-Za-z0-9]+$", uid_chr)
  n_repaired <- sum(comma_mask)
  if (n_repaired > 0) {
    uid_chr[comma_mask] <- gsub(",", "-", uid_chr[comma_mask], fixed = TRUE)
    df$uid[comma_mask]  <- uid_chr[comma_mask]
    log_info("remove_frame_shift: %d comma-separated UID(s) repaired (comma -> hyphen).",
             n_repaired)
  }

  # -- Step 2: Identify truly empty / null UIDs --------------------------------
  # Only these are treated as irrecoverable frame shifts and removed.
  null_strings <- c("", "na", "null", "nan", "none", "n/a", "<na>")
  is_empty_uid <- is.na(df$uid) |
                  tolower(uid_chr) %in% null_strings

  dirty_df <- df[ is_empty_uid, ]
  clean_df <- df[!is_empty_uid, ]
  n_removed <- nrow(dirty_df)

  log_info("remove_frame_shift: %d empty/null uid row(s) removed.", n_removed)

  # -- Step 3: Identify non-standard UIDs (logged only, NOT removed) -----------
  # Standard Neotree UID: alphanumeric chars with a hyphen (e.g. "XXXX-YYYY").
  # Non-standard = no hyphen, or fewer than 6 characters, or unusual characters.
  uid_clean_chr <- trimws(as.character(clean_df$uid))
  has_hyphen    <- grepl("-", uid_clean_chr, fixed = TRUE)
  nonstandard_mask <- !has_hyphen
  nonstandard_df   <- clean_df[nonstandard_mask, ]
  n_nonstandard    <- nrow(nonstandard_df)

  if (n_nonstandard > 0) {
    log_warn(paste0("remove_frame_shift: %d row(s) have non-standard UIDs ",
                    "(no hyphen). These are RETAINED -- see report for details."),
             n_nonstandard)
  }

  # -- Step 4: Write dirty rows CSV (empty-uid rows only) ----------------------
  if (!is.null(csv_filepath) && nzchar(csv_filepath) && n_removed > 0) {
    tryCatch(
      readr::write_csv(dirty_df, csv_filepath),
      error = function(e) log_warn("Could not write frame-shift CSV: %s", e$message)
    )
  }

  # -- Step 5: Write report -----------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      removed_uids     <- sort(unique(as.character(dirty_df$uid)))
      nonstandard_uids <- sort(unique(as.character(nonstandard_df$uid)))
      repaired_uids    <- sort(unique(as.character(
                            clean_df$uid[comma_mask[!is_empty_uid]])))

      lines <- c(
        "Module 02 - Frame Shift Correction Report",
        "==========================================",
        sprintf("Run timestamp                : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                      : %s", toupper(cfg$country)),
        sprintf("Dataset                      : %s", cfg$dataset),
        "",
        sprintf("Rows on entry                : %d", n_input),
        sprintf("Comma UIDs repaired          : %d", n_repaired),
        sprintf("Empty/null uid rows removed  : %d", n_removed),
        sprintf("Rows after correction        : %d", nrow(clean_df)),
        sprintf("Non-standard UIDs retained   : %d unique UID(s) in %d row(s)",
                length(nonstandard_uids), n_nonstandard),
        ""
      )

      if (n_repaired > 0) {
        lines <- c(lines,
                   "=== Repaired UIDs (comma -> hyphen) ===",
                   paste0("  ", repaired_uids),
                   "")
      }

      if (n_removed > 0) {
        lines <- c(lines,
                   "=== Removed rows (empty/null uid) ===",
                   paste0("  ", removed_uids),
                   "")
      }

      if (n_nonstandard > 0) {
        lines <- c(lines,
                   "=== Non-standard UIDs retained (no hyphen) ===",
                   "  These records have been kept in the dataset.",
                   "  Downstream probabilistic matching will determine linkage.",
                   paste0("  ", nonstandard_uids))
      }

      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write frame-shift report: %s", e$message))
  }

  return(clean_df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "02_frame_shift_report.txt") else NULL

dirty_csv <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "02_frame_shift_dirty_rows.csv") else NULL

df <- remove_frame_shift(df, report_filepath = report_path, csv_filepath = dirty_csv)
log_info("Module 02 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
