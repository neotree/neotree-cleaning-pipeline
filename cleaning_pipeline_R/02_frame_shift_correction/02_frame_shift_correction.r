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
#   Retained non-standard UIDs are reported in TWO separate groups, because they
#   are not the same kind of anomaly and should not be tracked as one number:
#     standard-length : 8-character alphanumeric, hyphen simply absent
#                       (e.g. "EC330587") -- a formatting variant of a
#                       well-formed uid, and by far the largest group.
#     other           : everything else (e.g. "EC", "X", "BS1262") -- truncated
#                       or incomplete submissions with no recoverable structure.
#
# UID REPAIR:
#   UIDs of the form "XXXX<sep>YYYY", where <sep> is a character typed in place
#   of the standard hyphen, are repaired to "XXXX-YYYY" before any further
#   processing (e.g. "CDDA,0484" -> "CDDA-0484", "F55F/0700" -> "F55F-0700").
#
#   The set of substitute characters is configuration, not code:
#   cfg$uid_repair_separators (set in 00_setup.r, currently comma and slash).
#   Recognising a further character later is a one-line change there.
#
#   Each repair is reported as confirmed or unconfirmed:
#     confirmed   the corrected (hyphenated) uid also exists in the paired
#                 admissions/discharges file for the same country, so the
#                 repair is backed by a real matching record.
#     unconfirmed no such record exists, so the repair is inferred from the
#                 facility's uid naming pattern alone.
#     unchecked   the paired file was not available to check against.
#   The paired file is resolved once in 00_setup.r as cfg$paired_csv_filepath;
#   only its uid and facility columns are read, and only when a repair actually
#   needs confirming.
#
#   An unconfirmed repair is still applied. The distinction is reported, not
#   acted on: the repair rests on the facility's uid pattern either way, and the
#   report is what tells a reader how much weight it carries.
#
# INPUTS:
#   df  - data.frame after Module 01
#
# OUTPUTS:
#   df  - data.frame with genuinely empty-uid rows removed; separator UIDs
#         repaired
#
# REPORT:
#   reports/02_frame_shift_report.txt
#   reports/02_frame_shift_dirty_rows.csv  (rows with empty/null uid only)
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("02_frame_shift_correction/02_frame_shift_correction.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Constants -----------------------------------------------------------------

# A hyphen-less uid of exactly this shape is a formatting variant of a
# well-formed uid, not a broken one: "XXXXYYYY" is "XXXX-YYYY" with the
# separator never stored.  Anything else without a hyphen is a different problem.
STANDARD_NOHYPHEN_PATTERN <- "^[A-Za-z0-9]{8}$"

# Fallback if cfg is unavailable (module sourced standalone).
DEFAULT_UID_SEPARATORS <- c(",", "/")


#' Build a regex bracket expression from a set of separator characters
#'
#' Keeps cfg$uid_repair_separators a plain vector of characters -- callers never
#' have to think about regex escaping when they add one.
#'
#' The class is built for PCRE (perl = TRUE), where a backslash inside a bracket
#' expression is unambiguously an escape.  R's default TRE engine treats "[\\^]"
#' as the two-character set {backslash, caret} rather than an escaped caret, so
#' every use of the returned class must pass perl = TRUE.
#'
#' @param seps Character vector of single characters.
#' @return A bracket expression such as "[,/]", or NULL if seps is empty.
.uid_separator_class <- function(seps) {
  seps <- unique(seps[!is.na(seps) & nzchar(seps)])
  if (length(seps) == 0) return(NULL)

  # Backslash first, so escapes added below are not themselves re-escaped.
  esc <- gsub("\\", "\\\\", seps, fixed = TRUE)
  for (ch in c("]", "^", "-")) {
    esc <- gsub(ch, paste0("\\", ch), esc, fixed = TRUE)
  }
  paste0("[", paste(esc, collapse = ""), "]")
}


#' Read uid + facility from a paired admissions/discharges raw CSV
#'
#' Only two columns are read, so the cost is small even for the largest export.
#'
#' @param paired_path Path to the paired raw CSV (may be NULL).
#' @return data.frame(uid, facility), or NULL if unavailable/unreadable.
.read_paired_uids <- function(paired_path) {
  if (is.null(paired_path) || !nzchar(paired_path) || !file.exists(paired_path))
    return(NULL)

  header <- tryCatch(
    readr::read_csv(paired_path, n_max = 0L, show_col_types = FALSE,
                    col_types = readr::cols()),
    error = function(e) {
      log_warn("remove_frame_shift: could not read paired file header: %s", e$message)
      NULL
    }
  )
  if (is.null(header)) return(NULL)

  # Mirror Module 01's normalisation so raw exports in either naming convention
  # ("uid" / "Unique Key"-style titles) resolve to the same columns.
  cols_norm <- tolower(gsub("[[:space:]]", "", names(header)))
  uid_col      <- names(header)[match("uid",      cols_norm)]
  facility_col <- names(header)[match("facility", cols_norm)]

  if (is.na(uid_col) || is.na(facility_col)) {
    log_warn(
      "remove_frame_shift: paired file lacks uid and/or facility columns; repairs cannot be confirmed."
    )
    return(NULL)
  }

  paired <- tryCatch(
    readr::read_csv(
      paired_path,
      col_select     = dplyr::all_of(c(uid_col, facility_col)),
      col_types      = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE,
      progress       = FALSE
    ),
    error = function(e) {
      log_warn("remove_frame_shift: error reading paired file: %s", e$message)
      NULL
    }
  )
  if (is.null(paired)) return(NULL)

  names(paired) <- tolower(gsub("[[:space:]]", "", names(paired)))
  paired$uid      <- trimws(as.character(paired$uid))
  paired$facility <- trimws(as.character(paired$facility))
  paired
}


#' Remove Frame-Shifted Rows and Repair Malformed UIDs
#'
#' @param df                  A data.frame with a "uid" column.
#' @param separators          Character vector of substitute separators to treat
#'                            as a mistyped hyphen. Defaults to
#'                            cfg$uid_repair_separators.
#' @param paired_csv_filepath Paired admissions/discharges raw CSV used to
#'                            confirm repairs. NULL = cannot check.
#' @param report_filepath     Optional path for a plain-text report.
#' @param csv_filepath        Optional path to save removed dirty rows.
#' @return                    Cleaned data.frame: empty-uid rows removed,
#'                            separator UIDs repaired, non-standard UIDs logged.
remove_frame_shift <- function(df,
                               separators          = NULL,
                               paired_csv_filepath = NULL,
                               report_filepath     = NULL,
                               csv_filepath        = NULL) {

  n_input <- nrow(df)

  if (!"uid" %in% names(df)) {
    log_warn("remove_frame_shift: 'uid' column not found. Skipping.")
    return(df)
  }

  if (is.null(separators)) {
    separators <- if (exists("cfg") && !is.null(cfg$uid_repair_separators))
      cfg$uid_repair_separators else DEFAULT_UID_SEPARATORS
  }
  sep_class <- .uid_separator_class(separators)

  uid_chr  <- trimws(as.character(df$uid))
  facility <- if ("facility" %in% names(df))
    trimws(as.character(df$facility)) else rep(NA_character_, nrow(df))

  # -- Step 1: Repair separator UIDs (e.g. "CDDA,0484" -> "CDDA-0484") ---------
  # A comma or slash in a uid is almost certainly a mistyped hyphen.  Pattern:
  # 3-6 alphanumeric chars, one separator, then more alphanumeric chars.
  repair_mask <- rep(FALSE, nrow(df))
  repairs     <- NULL

  if (!is.null(sep_class)) {
    uid_pattern <- sprintf("^[A-Za-z0-9]{3,6}%s[A-Za-z0-9]+$", sep_class)
    repair_mask <- grepl(uid_pattern, uid_chr, perl = TRUE)
  }
  n_repaired <- sum(repair_mask)

  if (n_repaired > 0) {
    uid_before  <- uid_chr[repair_mask]
    # The pattern guarantees exactly one separator, so sub() replaces it alone.
    uid_after   <- sub(sep_class, "-", uid_before, perl = TRUE)
    sep_used    <- regmatches(uid_before, regexpr(sep_class, uid_before, perl = TRUE))

    uid_chr[repair_mask] <- uid_after
    df$uid[repair_mask]  <- uid_after

    repairs <- data.frame(
      uid_original = uid_before,
      uid_repaired = uid_after,
      facility     = facility[repair_mask],
      separator    = sep_used,
      stringsAsFactors = FALSE
    )

    log_info(
      "remove_frame_shift: %d uid(s) repaired (separator -> hyphen); separators checked: %s.",
      n_repaired, paste(separators, collapse = " ")
    )
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

  # -- Step 3: Confirm repairs against the paired file -------------------------
  # "Confirmed" means the corrected uid exists in the paired admissions/
  # discharges file, so the repair is backed by a real record rather than
  # inferred from the facility's naming pattern alone.  The paired file is read
  # only when there is something to confirm.
  paired_used <- NA_character_

  if (n_repaired > 0) {
    paired <- .read_paired_uids(paired_csv_filepath)

    if (is.null(paired)) {
      repairs$status <- "unchecked"
    } else {
      paired_used <- paired_csv_filepath
      uid_fac     <- paste(paired$uid, paired$facility, sep = "\r")
      repairs$status <- ifelse(
        paste(repairs$uid_repaired, repairs$facility, sep = "\r") %in% uid_fac,
        "confirmed",
        ifelse(repairs$uid_repaired %in% paired$uid,
               "confirmed (other facility)",
               "unconfirmed")
      )
    }

    # Does the hyphenated form ALSO occur in this same file, on a row that was
    # not itself repaired?  That is the signature of a duplicate/retry
    # submission rather than a plain typo, and it is Module 10 -- not this
    # module -- that has to collapse the pair.  Reported, never acted on here.
    unrepaired_uids <- uid_chr[!repair_mask]
    unrepaired_fac  <- facility[!repair_mask]
    repairs$duplicate_in_file <- paste(repairs$uid_repaired, repairs$facility, sep = "\r") %in%
      paste(unrepaired_uids, unrepaired_fac, sep = "\r")

    n_conf   <- sum(startsWith(repairs$status, "confirmed"))
    n_unconf <- sum(repairs$status == "unconfirmed")
    n_unchk  <- sum(repairs$status == "unchecked")
    log_info(
      "remove_frame_shift: repaired uid status -- confirmed: %d | unconfirmed: %d | unchecked: %d.",
      n_conf, n_unconf, n_unchk
    )
    if (any(repairs$duplicate_in_file)) {
      log_warn(
        paste("remove_frame_shift: %d repaired uid(s) now match another row in this file",
              "(likely duplicate submission) -- Module 10 handles the collapse."),
        sum(repairs$duplicate_in_file)
      )
    }
  }

  # -- Step 4: Identify non-standard UIDs (logged only, NOT removed) -----------
  # Standard Neotree UID: alphanumeric chars with a hyphen (e.g. "XXXX-YYYY").
  # Non-standard = no hyphen.  These split into two groups that are tracked
  # separately because they are different problems (see header).  A uid repaired
  # in Step 1 now carries a hyphen and therefore appears in neither group.
  uid_clean_chr <- trimws(as.character(clean_df$uid))
  has_hyphen    <- grepl("-", uid_clean_chr, fixed = TRUE)

  nonstandard_mask <- !has_hyphen
  std_len_mask     <- nonstandard_mask &  grepl(STANDARD_NOHYPHEN_PATTERN, uid_clean_chr)
  other_mask       <- nonstandard_mask & !grepl(STANDARD_NOHYPHEN_PATTERN, uid_clean_chr)

  n_nonstandard <- sum(nonstandard_mask)
  n_std_len     <- sum(std_len_mask)
  n_other       <- sum(other_mask)

  std_len_uids <- sort(unique(uid_clean_chr[std_len_mask]))
  other_uids   <- sort(unique(uid_clean_chr[other_mask]))

  if (n_nonstandard > 0) {
    log_warn(
      paste0("remove_frame_shift: %d row(s) have non-standard UIDs (no hyphen) -- ",
             "%d standard-length (8-char alphanumeric), %d other. ",
             "All RETAINED -- see report for details."),
      n_nonstandard, n_std_len, n_other
    )
  }

  # -- Step 5: Write dirty rows CSV (empty-uid rows only) ----------------------
  if (!is.null(csv_filepath) && nzchar(csv_filepath) && n_removed > 0) {
    tryCatch(
      readr::write_csv(dirty_df, csv_filepath),
      error = function(e) log_warn("Could not write frame-shift CSV: %s", e$message)
    )
  }

  # -- Step 6: Write report -----------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      removed_uids <- sort(unique(as.character(dirty_df$uid)))

      n_conf   <- if (n_repaired > 0) sum(startsWith(repairs$status, "confirmed")) else 0L
      n_unconf <- if (n_repaired > 0) sum(repairs$status == "unconfirmed")         else 0L
      n_unchk  <- if (n_repaired > 0) sum(repairs$status == "unchecked")           else 0L

      lines <- c(
        "Module 02 - Frame Shift Correction Report",
        "==========================================",
        sprintf("Run timestamp                : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                      : %s", toupper(cfg$country)),
        sprintf("Dataset                      : %s", cfg$dataset),
        sprintf("Separator set (uid repair)   : %s",
                if (is.null(sep_class)) "(none configured)"
                else paste(sprintf("'%s'", separators), collapse = " ")),
        sprintf("Paired file (confirmation)   : %s",
                if (!is.na(paired_used)) paired_used
                else if (is.null(paired_csv_filepath)) "not available"
                else if (n_repaired == 0) "not needed (no repairs)"
                else sprintf("%s (unreadable)", paired_csv_filepath)),
        "",
        sprintf("Rows on entry                : %d", n_input),
        sprintf("Separator UIDs repaired      : %d row(s)", n_repaired),
        sprintf("  confirmed                  : %d", n_conf),
        sprintf("  unconfirmed                : %d", n_unconf),
        sprintf("  unchecked                  : %d", n_unchk),
        sprintf("Empty/null uid rows removed  : %d", n_removed),
        sprintf("Rows after correction        : %d", nrow(clean_df)),
        sprintf("Non-standard UIDs retained   : %d unique UID(s) in %d row(s)",
                length(std_len_uids) + length(other_uids), n_nonstandard),
        sprintf("  standard-length (8-char)   : %d unique UID(s) in %d row(s)",
                length(std_len_uids), n_std_len),
        sprintf("  other non-standard         : %d unique UID(s) in %d row(s)",
                length(other_uids), n_other),
        ""
      )

      if (n_repaired > 0) {
        # Collapse to one line per distinct repair, with a row count.
        key <- paste(repairs$uid_original, repairs$facility, sep = "\r")
        idx <- !duplicated(key)
        tab <- repairs[idx, , drop = FALSE]
        tab$n_rows <- as.integer(table(key)[key[idx]])

        lines <- c(lines,
                   "=== Repaired UIDs (separator -> hyphen) ===",
                   "  confirmed   = corrected uid found in the paired file (real matching record)",
                   "  unconfirmed = not found there; repair inferred from the facility uid pattern",
                   "  unchecked   = paired file unavailable, so no cross-check was possible",
                   "",
                   sprintf("  %-14s %-14s %-9s %-4s %6s  %s",
                           "ORIGINAL", "REPAIRED", "FACILITY", "SEP", "ROWS", "STATUS"),
                   sprintf("  %-14s %-14s %-9s %-4s %6d  %s%s",
                           tab$uid_original, tab$uid_repaired,
                           ifelse(is.na(tab$facility), "-", tab$facility),
                           tab$separator, tab$n_rows, tab$status,
                           ifelse(tab$duplicate_in_file,
                                  "  [also present in this file -- likely duplicate submission]",
                                  "")),
                   "")

        if (any(tab$duplicate_in_file)) {
          lines <- c(lines,
                     "  NOTE: a repaired uid marked [also present in this file] means the",
                     "  hyphenated form already exists on another row of this dataset. That is",
                     "  a duplicate/retry submission of the same event rather than a typo alone.",
                     "  Module 02 does not collapse it -- deduplication is Module 10's job.",
                     "")
        }
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
                   "")

        lines <- c(lines,
                   sprintf("  -- Standard-length, hyphen absent (8-char alphanumeric): %d unique in %d row(s) --",
                           length(std_len_uids), n_std_len),
                   "     A formatting variant of a well-formed uid: the same data with the",
                   "     separator never stored. Expected to link normally downstream.",
                   if (length(std_len_uids) > 0) paste0("     ", std_len_uids) else "     (none)",
                   "")

        lines <- c(lines,
                   sprintf("  -- Other non-standard: %d unique in %d row(s) --",
                           length(other_uids), n_other),
                   "     Truncated or incomplete submissions with no recoverable uid structure.",
                   "     Unlikely to link; retained for audit rather than analysis.",
                   if (length(other_uids) > 0) paste0("     ", other_uids) else "     (none)")
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

df <- remove_frame_shift(df,
                         separators          = cfg$uid_repair_separators,
                         paired_csv_filepath = cfg$paired_csv_filepath,
                         report_filepath     = report_path,
                         csv_filepath        = dirty_csv)
log_info("Module 02 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
