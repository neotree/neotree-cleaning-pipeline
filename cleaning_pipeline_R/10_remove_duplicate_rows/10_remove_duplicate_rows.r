# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 10: Remove Duplicate Rows
# =============================================================================
# PURPOSE:
#   Final deduplication after first-stage cleaning (Modules 01-09).
#
#   STAGE 1 - Visit-level deduplication:
#     Group by (uid, facility, visit-date columns).  Where multiple rows share
#     the same patient + visit, retain the record with the fewest missing values
#     across all non-key columns (the most complete record per visit).
#
#   STAGE 2 - Patient-level deduplication:
#     After collapsing same-visit duplicates, keep the single most complete
#     record per (uid, facility) -- i.e. the record with the fewest missing
#     values across all non-key columns.
#
#     Rationale: the Neotree app sometimes fails to transmit a record fully
#     (connection drop) and then retransmits it with a new timestamp.  The
#     retransmitted record is the authoritative one because it is complete.
#     Keeping the earliest record would systematically retain the truncated
#     copy; keeping the most complete record retains the correct one.
#
#     Tie-breaking (equal completeness): the most recently submitted record
#     is preferred (highest uniquekey value), as it is most likely to be the
#     correction.
#
#   Visit-date columns checked (whichever are present in df):
#     startedat, startedatdischarge,
#     datetimeadmission.value, dateadmission.value, datebct.value,
#     completedat, completedatdischarge
#
# INPUTS:
#   df  - data.frame after Module 09
#
# OUTPUTS:
#   df  - deduplicated data.frame
#   *_stage1.rds  - checkpoint RDS
#
# REPORT:
#   reports/10_duplicate_row_removal_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("10_remove_duplicate_rows/10_remove_duplicate_rows.r")
# =============================================================================

source("00_setup/00_setup.r")

#' Remove Duplicate Rows (Two-Stage, Most-Complete-Record Strategy)
#'
#' Stage 1 - collapse exact-visit duplicates (uid + facility + visit dates),
#'           keeping the record with the fewest missing values per visit.
#' Stage 2 - collapse cross-visit duplicates (uid + facility),
#'           keeping the most complete record overall (fewest missing values).
#'           Tie-break: latest uniquekey (most recent submission).
#'
#'   Stage 2 can be disabled via `skip_stage2 = TRUE` for longitudinal datasets
#'   where multiple rows per patient are by design (e.g. NeoInfect serial review
#'   records, NeoLab blood culture events).  In those cases Stage 1 still runs to
#'   collapse true same-visit duplicates (connection-drop retransmissions).
#'
#' @param df              A data.frame (typed, after Module 09).
#' @param skip_stage2     Logical. If TRUE, Stage 2 (patient-level) dedup is
#'                        skipped. Default FALSE. Set via cfg$skip_dedup_stage2.
#' @param report_filepath Optional path for a text report.
#' @return                Deduplicated data.frame.
remove_duplicate_rows <- function(df, skip_stage2 = FALSE, report_filepath = NULL) {

  n_start <- nrow(df)

  # Visit-date columns used for Stage 1 grouping (use whichever are present)
  visit_date_candidates <- c(
    "startedat", "startedatdischarge",
    "datetimeadmission.value", "dateadmission.value", "datebct.value",
    "completedat", "completedatdischarge"
  )
  visit_date_cols <- intersect(visit_date_candidates, names(df))

  # -- Stage 1: Visit-level deduplication --------------------------------------
  # Group by uid + facility + visit dates; keep the most complete record per
  # unique visit (fewest NAs across non-key columns).
  #
  # Tie-breaking pre-sort: when two rows in the same group are equally complete,
  # slice_min(with_ties = FALSE) keeps the first row in dataframe order.
  # We therefore sort so alphanumeric uniquekeys precede timestamp-format keys
  # (e.g. "2020-12-20T12:41:39.867Z") -- alphanumeric UUIDs are the canonical
  # Neotree identifiers; timestamp keys are a legacy fallback from older app
  # versions and batch re-imports.  Only activates when both forms exist for the
  # same UID; has no effect on rows whose group has a unique completeness winner.
  if ("uniquekey" %in% names(df)) {
    df$.key_is_ts <- grepl("^\\d{4}-\\d{2}-\\d{2}T", df$uniquekey)
    df <- df[order(df$.key_is_ts), ]        # FALSE (alphanumeric) sorts before TRUE (timestamp)
    df$.key_is_ts <- NULL
  }

  stage1_keys <- unique(c("uid", "facility", visit_date_cols))
  stage1_keys <- intersect(stage1_keys, names(df))

  non_key_cols <- setdiff(names(df), stage1_keys)
  df$.miss      <- rowSums(is.na(df[, non_key_cols, drop = FALSE]))

  df_s1 <- df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(stage1_keys))) %>%
    dplyr::slice_min(.miss, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.miss)

  n_after_s1 <- nrow(df_s1)
  n_removed_s1 <- n_start - n_after_s1

  # -- Stage 2: Patient-level deduplication ------------------------------------
  # Keep the single most complete record per (uid, facility): the one with the
  # fewest missing values across all non-(uid,facility) columns.
  #
  # Rationale: the Neotree app sometimes drops a connection mid-transmission,
  # producing a truncated record, then retransmits fully.  The retransmitted
  # record may carry a different visit-date timestamp, so Stage 1 does not
  # collapse it.  Keeping the most complete record (rather than the earliest)
  # ensures the authoritative, fully-transmitted copy is retained.
  #
  # Tie-break (equal completeness): prefer the most recently submitted record
  # (latest uniquekey string) -- most recent re-submission is most likely to be
  # the authoritative correction.
  #
  # EXCEPTION -- longitudinal datasets (skip_stage2 = TRUE):
  #   NeoInfect ("infections") records one row per serial clinical review visit.
  #   NeoLab ("neolab") records one row per blood culture event.
  #   In both cases, multiple rows per (uid, facility) are by design and must
  #   not be collapsed.  Stage 1 still runs to handle true same-visit duplicates
  #   (connection-drop retransmissions that share identical visit timestamps).
  if (isTRUE(skip_stage2)) {
    df_s2        <- df_s1
    n_after_s2   <- n_after_s1
    n_removed_s2 <- 0L
    n_removed_total <- n_start - n_after_s2
    log_info(
      paste("remove_duplicate_rows: Stage 1 (visit-level) removed %d row(s);",
            "Stage 2 (patient-level) SKIPPED (longitudinal dataset).",
            "Total removed: %d. Rows remaining: %d."),
      n_removed_s1, n_removed_total, n_after_s2
    )
  } else {
    if ("uniquekey" %in% names(df_s1)) {
      df_s1 <- df_s1[order(df_s1$uniquekey, decreasing = TRUE, na.last = TRUE), ]
    }

    non_key_cols_s2 <- setdiff(names(df_s1), c("uid", "facility"))
    df_s1$.miss_s2  <- rowSums(is.na(df_s1[, non_key_cols_s2, drop = FALSE]))

    df_s2 <- df_s1 %>%
      dplyr::group_by(uid, facility) %>%
      dplyr::slice_min(.miss_s2, n = 1, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::select(-.miss_s2)

    n_after_s2   <- nrow(df_s2)
    n_removed_s2 <- n_after_s1 - n_after_s2
    n_removed_total <- n_start - n_after_s2

    log_info(
      paste("remove_duplicate_rows: Stage 1 (visit-level) removed %d row(s);",
            "Stage 2 (patient-level) removed %d row(s).",
            "Total removed: %d. Rows remaining: %d."),
      n_removed_s1, n_removed_s2, n_removed_total, n_after_s2
    )
  }

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      stage2_line <- if (isTRUE(skip_stage2))
        "  Stage 2 (patient-level)       : SKIPPED (longitudinal dataset -- multiple rows per patient by design)"
      else
        sprintf("  Stage 2 (patient-level) removed: %d", n_removed_s2)
      lines <- c(
        "Module 10 - Duplicate Row Removal Report",
        "=========================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        "",
        sprintf("Rows before deduplication   : %d", n_start),
        sprintf("  Stage 1 (visit-level) removed  : %d", n_removed_s1),
        stage2_line,
        sprintf("Total duplicate rows removed: %d", n_removed_total),
        sprintf("Rows after deduplication    : %d", n_after_s2),
        sprintf("Retention rate              : %.1f%%",
                100 * n_after_s2 / max(n_start, 1)),
        "",
        if (length(visit_date_cols) > 0)
          paste0("Visit-date columns used (Stage 1 grouping): ",
                 paste(visit_date_cols, collapse = ", "))
        else
          "Visit-date columns used (Stage 1 grouping): none found",
        "",
        if (isTRUE(skip_stage2))
          "Stage 2 strategy : SKIPPED (cfg$skip_dedup_stage2 = TRUE)"
        else
          "Stage 2 strategy : most complete record (fewest NAs); tie-break = latest uniquekey"
      )
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 10 report: %s", e$message))
  }

  return(df_s2)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "10_duplicate_row_removal_report.txt") else NULL

df <- remove_duplicate_rows(df,
                            skip_stage2     = isTRUE(cfg$skip_dedup_stage2),
                            report_filepath = report_path)

# -- Checkpoint: save first-stage cleaned data (optional) ---------------------
if (isTRUE(cfg$save_stage1_checkpoint)) {
  checkpoint_rds <- file.path(
    dirname(cfg$output_rds),
    sub("\\.rds$", "_stage1.rds", basename(cfg$output_rds))
  )
  tryCatch(
    saveRDS(df, checkpoint_rds),
    error = function(e) log_warn("Could not save stage-1 checkpoint: %s", e$message)
  )
  log_info("First-stage cleaning complete. Checkpoint saved: %s", checkpoint_rds)
} else {
  log_info("Stage-1 checkpoint skipped (SAVE_STAGE1_CHECKPOINT = FALSE).")
}
log_info("Module 10 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
