# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 10: Remove Duplicate Rows
# =============================================================================
# PURPOSE:
#   Removes duplicate rows in two stages.
#
# METHOD:
#   Stage 1 - visit level:
#     Group by (uid, facility, visit-date columns).  Where several rows share
#     the same group, keep the row with the fewest missing values across all
#     non-key columns.  On a tie, a row with an alphanumeric uniquekey is
#     preferred over one with a timestamp-format uniquekey.
#
#   Stage 2 - patient level:
#     Keep one row per (uid, facility): the row with the fewest missing
#     values.  On a tie, the row with the highest uniquekey is kept.
#     Stage 2 is skipped when cfg$skip_dedup_stage2 is TRUE (datasets with
#     several rows per patient by design).
#
#   Stage 2 - episode mode (cfg$dedup_mode = "episode"; admissions,
#   discharges, phc_admissions, phc_discharges, ZIM maternal_outcomes and
#   MWI combined_maternity_outcomes only): rows are collapsed only when they are the same event,
#   and every row gets baby_id and stay_no.  See episode_ids.r.  The
#   admissions run writes <stem>_episode_keys.rds to its output folder; the
#   discharges run reads the one written for the paired admissions file.
#
#   Visit-date columns used (whichever are present in df):
#     startedat, startedatdischarge,
#     datetimeadmission.value, dateadmission.value, datebct.value,
#     completedat, completedatdischarge
#
# INPUTS:
#   df  - data.frame after Module 09
#
# OUTPUTS:
#   df            - deduplicated data.frame
#   *_stage1.rds  - checkpoint RDS (only when cfg$save_stage1_checkpoint is TRUE)
#   Report        - cfg$report_dir/10_duplicate_row_removal_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("10_remove_duplicate_rows/10_remove_duplicate_rows.r")
# =============================================================================

source("00_setup/00_setup.r")
source("10_remove_duplicate_rows/episode_ids.r")

#' Remove Duplicate Rows (Two-Stage, Most-Complete-Record Strategy)
#'
#' Stage 1 - collapse same-visit duplicates (uid + facility + visit dates),
#'           keeping the record with the fewest missing values per visit.
#' Stage 2 - collapse to one record per (uid + facility), keeping the record
#'           with the fewest missing values.  Tie-break: highest uniquekey.
#'
#'   Stage 2 can be disabled via `skip_stage2 = TRUE` for longitudinal datasets
#'   where multiple rows per patient are by design (e.g. serial review records,
#'   blood culture events).  Stage 1 still runs in that case.
#'
#' @param df              A data.frame (typed, after Module 09).
#' @param skip_stage2     Logical. If TRUE, Stage 2 (patient-level) dedup is
#'                        skipped. Default FALSE. Set via cfg$skip_dedup_stage2.
#' @param report_filepath Optional path for a text report.
#' @return                Deduplicated data.frame.
remove_duplicate_rows <- function(df, skip_stage2 = FALSE, report_filepath = NULL,
                                  episode_dataset = NULL, adm_keys = NULL) {

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
  # group (fewest NAs across non-key columns).
  #
  # When two rows in a group are equally complete, slice_min(with_ties = FALSE)
  # keeps the first row in data frame order.  The rows are therefore sorted so
  # that alphanumeric uniquekeys precede timestamp-format keys
  # (e.g. "2020-01-01T00:00:00.000Z").
  if ("uniquekey" %in% names(df)) {
    df$.key_is_ts <- grepl("^\\d{4}-\\d{2}-\\d{2}T", df$uniquekey)
    df <- df[order(df$.key_is_ts), ]        # FALSE (alphanumeric) sorts before TRUE (timestamp)
    df$.key_is_ts <- NULL
  }

  stage1_keys <- unique(c("uid", "facility", visit_date_cols))
  stage1_keys <- intersect(stage1_keys, names(df))

  non_key_cols <- setdiff(names(df), stage1_keys)
  df$.miss      <- rowSums(is.na(df[, non_key_cols, drop = FALSE]))

  # In episode mode Stage 1 is not applied: rows with identical visit dates
  # can belong to different babies, so they are left to the episode rule,
  # which checks identity before collapsing.
  episode_on <- !isTRUE(skip_stage2) && !is.null(episode_dataset)
  df_s1 <- if (episode_on) df %>% dplyr::select(-.miss) else df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(stage1_keys))) %>%
    dplyr::slice_min(.miss, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.miss)

  n_after_s1 <- nrow(df_s1)
  n_removed_s1 <- n_start - n_after_s1

  # -- Stage 2: Patient-level deduplication ------------------------------------
  # Keep the single most complete record per (uid, facility): the one with the
  # fewest missing values across all non-(uid, facility) columns.  A partial
  # and a complete transmission of the same record can carry different
  # visit-date timestamps, so Stage 1 does not collapse them.
  #
  # Tie-break (equal completeness): the highest uniquekey string, obtained by
  # sorting uniquekey in decreasing order before slice_min().
  #
  # With skip_stage2 = TRUE the Stage 1 result is returned unchanged, for
  # datasets with one row per review visit or per blood culture event.
  n_shared_key <- NA_integer_
  ep <- NULL
  if (episode_on) {
    ep           <- ep_dedup(df_s1, episode_dataset, adm_keys)
    df_s2        <- ep$df
    n_after_s2   <- nrow(df_s2)
    n_removed_s2 <- n_after_s1 - n_after_s2
    n_removed_total <- n_start - n_after_s2
    if (ep$summary[["rows_sharing_uid_facility_uniquekey"]] > 0)
      stop(sprintf(paste("Module 10 (episode mode): %d kept row(s) share uid + facility + uniquekey",
                         "with another row; later modules would merge them. Stopped."),
                   ep$summary[["rows_sharing_uid_facility_uniquekey"]]))
    log_info(
      paste("remove_duplicate_rows: Stage 1 (visit-level) removed %d row(s);",
            "Stage 2 (episode mode) removed %d row(s). Rows remaining: %d;",
            "babies %d; stays %d; flagged rows %d."),
      n_removed_s1, n_removed_s2, n_after_s2, ep$summary[["distinct_babies"]],
      ep$summary[["distinct_stays"]], ep$summary[["rows_flagged"]]
    )
  } else if (isTRUE(skip_stage2)) {
    df_s2        <- df_s1
    n_after_s2   <- n_after_s1
    n_removed_s2 <- 0L
    n_removed_total <- n_start - n_after_s2

    # Rows that share uid + facility + uniquekey are merged by Modules 11 to
    # 15, so they are counted here and reported.
    if ("uniquekey" %in% names(df_s2)) {
      visit_keys   <- intersect(c("uid", "facility", "uniquekey"), names(df_s2))
      visit_id     <- do.call(paste, c(df_s2[, visit_keys, drop = FALSE], sep = "\r"))
      n_shared_key <- sum(visit_id %in% visit_id[duplicated(visit_id)])
      if (n_shared_key > 0)
        log_warn(
          paste("remove_duplicate_rows: %d row(s) share uid + facility + uniquekey",
                "with another row; later modules keep one row per key."),
          n_shared_key
        )
    } else {
      log_warn(paste("remove_duplicate_rows: no uniquekey column;",
                     "later modules keep one row per uid + facility."))
    }
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
      stage2_line <- if (!is.null(ep))
        sprintf("  Stage 2 (episode mode) removed : %d", n_removed_s2)
      else if (isTRUE(skip_stage2))
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
        if (episode_on) "  Stage 1 (visit-level)          : not applied (episode mode)"
        else sprintf("  Stage 1 (visit-level) removed  : %d", n_removed_s1),
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
        if (isTRUE(skip_stage2)) {
          if (is.na(n_shared_key))
            "Rows sharing uid + facility + uniquekey : not checked (no uniquekey column); later modules keep one row per uid + facility"
          else
            sprintf("Rows sharing uid + facility + uniquekey : %d%s", n_shared_key,
                    if (n_shared_key > 0) "  (later modules keep one row per key)" else "")
        },
        if (!is.null(ep))
          "Stage 2 strategy : episode mode (same event only; baby_id and stay_no added)"
        else if (isTRUE(skip_stage2))
          "Stage 2 strategy : SKIPPED (cfg$skip_dedup_stage2 = TRUE)"
        else
          "Stage 2 strategy : most complete record (fewest NAs); tie-break = latest uniquekey"
      )
      if (!is.null(ep)) {
        tab_lines <- function(title, tb)
          c("", title, sprintf("  %-62s %8d", names(tb), as.integer(tb)))
        lines <- c(lines, "", "Episode mode counts:",
                   sprintf("  %-62s %8d", names(ep$summary), as.integer(ep$summary)),
                   tab_lines("Rows by basis of baby_id / stay_no:", ep$basis_counts),
                   tab_lines("Rows by flag (a row can carry several):", ep$flag_counts))
      }
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 10 report: %s", e$message))
  }

  attr(df_s2, "episode") <- ep
  return(df_s2)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "10_duplicate_row_removal_report.txt") else NULL

episode_dataset <- if (isTRUE(cfg$dedup_episode)) ep_role(cfg$dataset, cfg$country) else NULL
adm_keys        <- NULL
if (identical(episode_dataset, "discharges")) {
  if (is.null(cfg$paired_csv_filepath))
    stop("Module 10 (episode mode): no admissions file found for this discharges file.")
  adm_stem <- sub("\\.csv$", "", basename(cfg$paired_csv_filepath))
  adm_keys_path <- file.path(dirname(cfg$run_output_dir), adm_stem,
                             paste0(adm_stem, "_episode_keys.rds"))
  adm_keys <- ep_read_keys(adm_keys_path, cfg$paired_csv_filepath)
  log_info("Module 10 (episode mode): admission keys read from %s", adm_keys_path)
}

df <- remove_duplicate_rows(df,
                            skip_stage2     = isTRUE(cfg$skip_dedup_stage2),
                            report_filepath = report_path,
                            episode_dataset = episode_dataset,
                            adm_keys        = adm_keys)

ep_result <- attr(df, "episode")
attr(df, "episode") <- NULL
keys_path <- file.path(cfg$run_output_dir,
                       paste0(sub("\\.csv$", "", basename(cfg$csv_filepath)), "_episode_keys.rds"))
if (identical(episode_dataset, "admissions")) {
  dir.create(cfg$run_output_dir, recursive = TRUE, showWarnings = FALSE)
  ep_write_keys(ep_result$keys, keys_path, cfg$csv_filepath,
                dict_file = cfg$dict_filepath,
                dict_md5  = if (exists("RUN_DICT_MD5")) RUN_DICT_MD5 else cfg$dict_md5)
  log_info("Module 10 (episode mode): admission keys written to %s", keys_path)
} else if (identical(ep_role(cfg$dataset), "admissions") && file.exists(keys_path)) {
  file.remove(keys_path)
  log_info("Module 10: old episode key file removed (this run is not in episode mode): %s", keys_path)
}
rm(ep_result, adm_keys, episode_dataset)

# -- Checkpoint: save first-stage cleaned data (optional) ---------------------
if (isTRUE(cfg$save_stage1_checkpoint)) {
  checkpoint_rds <- file.path(
    dirname(cfg$output_rds),
    sub("\\.rds$", "_stage1.rds", basename(cfg$output_rds))
  )
  assert_pii_removed(df, stage = "10_stage1_checkpoint")
  tryCatch(
    saveRDS(df, checkpoint_rds),
    error = function(e) log_warn("Could not save stage-1 checkpoint: %s", e$message)
  )
  log_info("First-stage cleaning complete. Checkpoint saved: %s", checkpoint_rds)
} else {
  log_info("Stage-1 checkpoint skipped (SAVE_STAGE1_CHECKPOINT = FALSE).")
}
log_info("Module 10 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
