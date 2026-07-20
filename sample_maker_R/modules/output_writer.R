################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/output_writer.R
# PURPOSE: Write all output datasets and text reports to disk.
#          Outputs are placed in a structured subdirectory that mirrors the
#          country / source / cleaning selection from config.R.
#
# OUTPUT FILES
#   {prefix}_joined_admissions_discharges_{label}.csv        -- direct uid+facility matches
#   {prefix}_unmatched_admissions_{label}.csv                -- admissions with no discharge found
#   {prefix}_unmatched_discharges_{label}.csv                -- discharges with no matching admission
#   {prefix}_master_joined_{label}.csv                       -- all admissions (matched + unmatched)
#   {prefix}_master_joined_extended_{label}.csv              -- master + probabilistic matches
#   {prefix}_master_joined_{label}_na_coded.csv              -- na_coded variant (if enabled)
#   {prefix}_master_joined_extended_{label}_na_coded.csv     -- na_coded variant (if enabled)
#   {prefix}_prob_match_assignments_{label}.csv              -- accepted one-to-one prob pairs
#   {prefix}_prob_match_candidates_{label}.csv               -- all candidates above threshold
#   {prefix}_matching_statistics_{label}.txt                 -- direct-join statistics report
#   {prefix}_prob_matching_report_{label}.txt                -- probabilistic matching report
#   {prefix}_duplicates_log.csv                              -- only if duplicates were found
#
# NA-CODED OUTPUT
#   When ps$adm_na_coded and ps$dis_na_coded are not NULL (i.e. CONFIG$output_na_coded
#   is TRUE and the source *_cleaned_na_coded.csv files were found), two additional
#   master CSV files are written with NA represented as sentinel codes (-7/-9 etc.)
#   as in the cleaning pipeline.  All join/match logic runs only on the standard
#   blank-NA data; na_coded variants are built by vectorised row lookup.
#
# STATISTICS REPORT SECTIONS  (matching_statistics.txt)
#   [1] Run metadata     [2] Input files     [3] Admission filter
#   [4] Deduplication    [5] Matching summary  [6] Neotree outcomes
#   [7] Unmatched breakdown   [8] Master dataset summary   [9] Output files
#
# PROBABILISTIC MATCHING REPORT SECTIONS  (prob_matching_report.txt)
#   [1] Run metadata     [2] Variable selection     [3] Candidate search
#   [4] One-to-one assignments   [5] Per-variable statistics
#   [6] Master_joined_extended summary   [7] Top assignments   [8] Output files
#
# FUNCTIONS EXPORTED
#   write_outputs(cfg, pipeline_state)  -> named list of output file paths
################################################################################

write_outputs <- function(cfg, ps) {

  # ---------------------------------------------------------------------------
  # 1. Resolve output directory
  # ---------------------------------------------------------------------------
  out_dir <- file.path(
    cfg$output_dir,
    paste0(tolower(cfg$country), "_master"),
    cfg$source
  )
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  # ---------------------------------------------------------------------------
  # 2. Build filename prefix and label
  # ---------------------------------------------------------------------------
  src_short <- switch(cfg$source, from_database = "db", from_metabase = "mb")

  prefix <- paste0(toupper(cfg$country), "_", src_short)
  label  <- ps$filter_result$filter_label

  if (!is.null(cfg$variable_filter_col) && !is.null(cfg$variable_filter_values)) {
    label <- paste0(label, "_",
      cfg$variable_filter_col, "_",
      paste(cfg$variable_filter_values, collapse = "_")
    )
  }

  # ---------------------------------------------------------------------------
  # 3. File paths
  # ---------------------------------------------------------------------------
  paths <- list(
    joined          = file.path(out_dir, sprintf("%s_joined_admissions_discharges_%s.csv",          prefix, label)),
    joined_extended = file.path(out_dir, sprintf("%s_joined_admissions_discharges_extended_%s.csv", prefix, label)),
    unmatched_adm   = file.path(out_dir, sprintf("%s_unmatched_admissions_%s.csv",                  prefix, label)),
    unmatched_dis   = file.path(out_dir, sprintf("%s_unmatched_discharges_%s.csv",           prefix, label)),
    master_joined   = file.path(out_dir, sprintf("%s_master_joined_%s.csv",                  prefix, label)),
    master_extended = file.path(out_dir, sprintf("%s_master_joined_extended_%s.csv",          prefix, label)),
    prob_assign     = file.path(out_dir, sprintf("%s_prob_match_assignments_%s.csv",          prefix, label)),
    prob_cands      = file.path(out_dir, sprintf("%s_prob_match_candidates_%s.csv",           prefix, label)),
    stats           = file.path(out_dir, sprintf("%s_matching_statistics_%s.txt",             prefix, label)),
    prob_report     = file.path(out_dir, sprintf("%s_prob_matching_report_%s.txt",            prefix, label)),
    dup_log         = file.path(out_dir, sprintf("%s_duplicates_log.csv",                     prefix)),
    pipeline_log    = file.path(out_dir, sprintf("%s_pipeline_log_%s.txt",                    prefix, label))
  )

  # ---------------------------------------------------------------------------
  # 4. Write CSV files
  # ---------------------------------------------------------------------------
  cat("[output] Writing CSV files...\n")

  # Derive joined_admissions_discharges_extended: matched-only rows from
  # master_joined_extended (direct_match + prob_match, no unmatched rows).
  joined_ext <- ps$master_joined_extended[
    !is.na(ps$master_joined_extended$match_type) &
    ps$master_joined_extended$match_type != "unmatched",
  ]

  write.csv(ps$join_result$matched_pairs,    paths$joined,          row.names = FALSE, na = "")
  write.csv(joined_ext,                      paths$joined_extended, row.names = FALSE, na = "")
  write.csv(ps$join_result$unmatched_adm,    paths$unmatched_adm,   row.names = FALSE, na = "")
  write.csv(ps$join_result$unmatched_dis,    paths$unmatched_dis,   row.names = FALSE, na = "")
  write.csv(ps$master_joined,                paths$master_joined,   row.names = FALSE, na = "")
  write.csv(ps$master_joined_extended,       paths$master_extended, row.names = FALSE, na = "")

  cat(sprintf("[output]   joined_admissions_discharges          : %d rows -> %s\n",
              nrow(ps$join_result$matched_pairs),  basename(paths$joined)))
  cat(sprintf("[output]   joined_admissions_discharges_extended : %d rows -> %s\n",
              nrow(joined_ext),                    basename(paths$joined_extended)))
  cat(sprintf("[output]   unmatched_admissions                  : %d rows -> %s\n",
              nrow(ps$join_result$unmatched_adm),  basename(paths$unmatched_adm)))
  cat(sprintf("[output]   unmatched_discharges                  : %d rows -> %s\n",
              nrow(ps$join_result$unmatched_dis),  basename(paths$unmatched_dis)))
  cat(sprintf("[output]   master_joined                         : %d rows -> %s\n",
              nrow(ps$master_joined),              basename(paths$master_joined)))
  cat(sprintf("[output]   master_joined_extended                : %d rows -> %s\n\n",
              nrow(ps$master_joined_extended),     basename(paths$master_extended)))

  # ---------------------------------------------------------------------------
  # 4b. Na-coded master files (optional)
  # ---------------------------------------------------------------------------
  if (!is.null(ps$adm_na_coded) && !is.null(ps$dis_na_coded)) {
    cat("[output] Writing na_coded master files...\n")

    paths$master_joined_nc  <- file.path(out_dir,
      sprintf("%s_master_joined_%s_na_coded.csv",          prefix, label))
    paths$master_extended_nc <- file.path(out_dir,
      sprintf("%s_master_joined_extended_%s_na_coded.csv", prefix, label))

    tryCatch({
      mj_nc <- .build_na_coded_master_joined(
        ps$master_joined, ps$adm_na_coded, ps$dis_na_coded
      )
      write.csv(mj_nc, paths$master_joined_nc, row.names = FALSE, na = "")
      cat(sprintf("[output]   master_joined_na_coded          : %d rows -> %s\n",
                  nrow(mj_nc), basename(paths$master_joined_nc)))

      mje_nc <- .build_na_coded_master_joined_extended(
        master_joined_na_coded = mj_nc,
        master_joined_extended = ps$master_joined_extended,
        prob_assignments       = ps$prob_assignments,
        adm_na_coded           = ps$adm_na_coded,
        dis_na_coded           = ps$dis_na_coded
      )
      write.csv(mje_nc, paths$master_extended_nc, row.names = FALSE, na = "")
      cat(sprintf("[output]   master_joined_extended_na_coded : %d rows -> %s\n\n",
                  nrow(mje_nc), basename(paths$master_extended_nc)))
    }, error = function(e) {
      cat(sprintf("[output] WARNING: na_coded output failed: %s\n\n", conditionMessage(e)))
      paths$master_joined_nc   <<- NULL
      paths$master_extended_nc <<- NULL
    })
  }

  # Probabilistic matching outputs
  if (!is.null(ps$prob_candidates) && nrow(ps$prob_candidates) > 0) {
    write.csv(ps$prob_candidates,   paths$prob_cands,  row.names = FALSE, na = "")
    cat(sprintf("[output]   prob_match_candidates        : %d rows -> %s\n",
                nrow(ps$prob_candidates), basename(paths$prob_cands)))
  }
  if (!is.null(ps$prob_assignments) && nrow(ps$prob_assignments) > 0) {
    write.csv(ps$prob_assignments,  paths$prob_assign, row.names = FALSE, na = "")
    cat(sprintf("[output]   prob_match_assignments       : %d rows -> %s\n",
                nrow(ps$prob_assignments), basename(paths$prob_assign)))
  }

  # Duplicates log
  combined_dup_log <- rbind(ps$adm_dedup$log, ps$dis_dedup$log)
  if (nrow(combined_dup_log) > 0) {
    write.csv(combined_dup_log, paths$dup_log, row.names = FALSE, na = "")
    cat(sprintf("[output]   duplicates_log               : %d rows -> %s\n",
                nrow(combined_dup_log), basename(paths$dup_log)))
  }
  cat("\n")

  # ---------------------------------------------------------------------------
  # 5. Write text reports
  # ---------------------------------------------------------------------------
  stats_report <- .build_stats_report(cfg, ps, prefix, label, paths, joined_ext)
  writeLines(stats_report, paths$stats)
  cat(sprintf("[output]   matching_statistics report    : %s\n", basename(paths$stats)))

  prob_report <- .build_prob_report(cfg, ps, prefix, label, paths, joined_ext)
  writeLines(prob_report, paths$prob_report)
  cat(sprintf("[output]   prob_matching_report          : %s\n", basename(paths$prob_report)))

  # ---------------------------------------------------------------------------
  # 6. Write consolidated pipeline log  (both reports in one file)
  # ---------------------------------------------------------------------------
  sep_thick <- paste0(strrep("=", 79))
  sep_thin  <- paste0(strrep("-", 79))
  pipeline_log <- c(
    sep_thick,
    "  NEOTREE SAMPLE MAKER -- PIPELINE LOG",
    sprintf("  Run      : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("  Country  : %s  |  Source : %s",
            cfg$country, cfg$source),
    sep_thick,
    "",
    sep_thin,
    sprintf("  [ %s ]", basename(paths$stats)),
    sep_thin,
    "",
    stats_report,
    "",
    sep_thin,
    sprintf("  [ %s ]", basename(paths$prob_report)),
    sep_thin,
    "",
    prob_report
  )
  writeLines(pipeline_log, paths$pipeline_log)
  cat(sprintf("[output]   pipeline_log                 : %s\n\n", basename(paths$pipeline_log)))

  paths
}

# ==============================================================================
# .build_stats_report()   -- direct-join statistics (sections 1-9)
# ==============================================================================
.build_stats_report <- function(cfg, ps, prefix, label, paths, joined_ext = NULL) {

  jr  <- ps$join_result
  fr  <- ps$filter_result
  vfr <- ps$varfilt_result
  adr <- ps$adm_dedup
  ddr <- ps$dis_dedup
  mj  <- ps$master_joined
  mje <- ps$master_joined_extended

  timestamp  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  sep_thick  <- strrep("=", 70)
  sep_thin   <- strrep("-", 70)

  # [1] Run metadata
  s1 <- c(
    sep_thick,
    "  Neotree Sample Maker -- Matching Statistics Report",
    sep_thick, "",
    sprintf("  Generated  : %s", timestamp),
    sprintf("  Country    : %s", toupper(cfg$country)),
    sprintf("  Source     : %s", cfg$source),
    sprintf("  Filter tag : %s", label), ""
  )

  # [2] Input files
  s2 <- c(
    sep_thin, "  [2]  INPUT FILES", sep_thin, "",
    sprintf("  Admissions file  : %s", basename(ps$admissions_path)),
    sprintf("  Discharges file  : %s", basename(ps$discharges_path)),
    sprintf("  Admissions (raw) : %d records", ps$n_adm_raw),
    sprintf("  Discharges (raw) : %d records", ps$n_dis_raw), ""
  )

  # [3] Admission filter
  auto_note <- if (isTRUE(ps$date_window$auto_mode))
    "  [AUTO: last date in file minus 1 calendar month]" else ""

  s3 <- c(
    sep_thin, "  [3]  ADMISSION FILTER", sep_thin, "",
    fr$filter_desc,
    if (!is.null(vfr$var_filter_desc)) vfr$var_filter_desc else "  Variable filter  : (none)",
    "",
    sprintf("  Admissions before filter       : %d", fr$n_before),
    sprintf("  Excluded by date/facility      : %d", fr$n_excluded),
    if (vfr$n_excluded_varfilt > 0)
      sprintf("  Excluded by variable filter    : %d", vfr$n_excluded_varfilt),
    sprintf("  Admissions entering join step  : %d",
            fr$n_after - vfr$n_excluded_varfilt), ""
  )

  # [4] Deduplication
  s4 <- c(
    sep_thin, "  [4]  DEDUPLICATION", sep_thin, "",
    sprintf("  Admissions -- duplicate uid+facility keys : %d  (%d row(s) removed)",
            adr$n_dup_keys, adr$n_removed),
    sprintf("  Discharges -- duplicate uid+facility keys : %d  (%d row(s) removed)",
            ddr$n_dup_keys, ddr$n_removed),
    if (adr$n_dup_keys + ddr$n_dup_keys > 0)
      sprintf("  Duplicates log : %s", basename(paths$dup_log))
    else "  No duplicates found.", ""
  )

  # [5] Matching summary
  pct_a <- function(n) sprintf("%.1f%%", 100 * n / jr$n_adm_total)
  pct_d <- function(n) sprintf("%.1f%%", 100 * n / jr$n_dis_total)

  s5 <- c(
    sep_thin, "  [5]  DIRECT MATCHING SUMMARY  (uid + facility key)", sep_thin, "",
    sprintf("  %-35s  %8s  %8s  %8s", "", "N", "% of adm", "% of dis"),
    sprintf("  %-35s  %8s  %8s  %8s",
            strrep("-", 35), strrep("-", 8), strrep("-", 8), strrep("-", 8)),
    sprintf("  %-35s  %8d  %8s  %8s",
            "Matched pairs", jr$n_matched, pct_a(jr$n_matched), pct_d(jr$n_matched)),
    sprintf("  %-35s  %8d  %8s  %8s",
            "Unmatched admissions", jr$n_unmatched_adm, pct_a(jr$n_unmatched_adm), "--"),
    sprintf("  %-35s  %8d  %8s  %8s",
            "Unmatched discharges", jr$n_unmatched_dis, "--", pct_d(jr$n_unmatched_dis)),
    sprintf("  %-35s  %8d", "Total admissions (post-filter)", jr$n_adm_total),
    sprintf("  %-35s  %8d", "Total discharges (all available)", jr$n_dis_total), ""
  )

  # [6] Neotree outcomes
  s6 <- c(
    sep_thin, "  [6]  NEOTREE OUTCOMES  (direct matched pairs only)", sep_thin, "",
    jr$outcome_summary$lines, ""
  )

  # [7] Unmatched breakdown
  fac_adm <- .fac_breakdown(jr$unmatched_adm, "Unmatched admissions by facility")
  fac_dis <- .fac_breakdown(jr$unmatched_dis, "Unmatched discharges by facility")

  s7 <- c(
    sep_thin, "  [7]  UNMATCHED RECORD BREAKDOWN", sep_thin, "",
    fac_adm, "", fac_dis, ""
  )

  # [8] Master dataset summary
  mj_tab  <- if (!is.null(mj))  table(mj$match_type)  else table(character(0))
  mje_tab <- if (!is.null(mje)) table(mje$match_type) else table(character(0))

  fmt_tab <- function(tab) {
    total <- sum(tab)
    if (total == 0) return("  (empty)")
    vapply(seq_along(tab), function(i)
      sprintf("    %-20s  %6d  %5.1f%%",
              names(tab)[i], tab[i], 100 * tab[i] / total),
      character(1))
  }

  # joined_admissions_discharges_extended counts
  n_jext_direct <- if (!is.null(joined_ext)) sum(joined_ext$match_type == "direct_match", na.rm = TRUE) else 0L
  n_jext_prob   <- if (!is.null(joined_ext)) sum(joined_ext$match_type == "prob_match",   na.rm = TRUE) else 0L
  n_jext_total  <- if (!is.null(joined_ext)) nrow(joined_ext) else 0L

  s8 <- c(
    sep_thin, "  [8]  MASTER DATASET SUMMARY", sep_thin, "",
    sprintf("  master_joined (%d rows):", nrow(mj)),
    fmt_tab(mj_tab), "",
    sprintf("  master_joined_extended (%d rows):", nrow(mje)),
    fmt_tab(mje_tab), "",
    sprintf("  joined_admissions_discharges_extended (%d rows, matched pairs only):", n_jext_total),
    sprintf("    %-20s  %6d  %5.1f%%", "direct_match",
            n_jext_direct, if (n_jext_total > 0) 100 * n_jext_direct / n_jext_total else 0),
    sprintf("    %-20s  %6d  %5.1f%%", "prob_match",
            n_jext_prob,   if (n_jext_total > 0) 100 * n_jext_prob   / n_jext_total else 0),
    ""
  )

  # [9] Output files
  listed <- c(
    sprintf("  joined_admissions_discharges          : %s", basename(paths$joined)),
    sprintf("  joined_admissions_discharges_extended : %s", basename(paths$joined_extended)),
    sprintf("  unmatched_admissions                  : %s", basename(paths$unmatched_adm)),
    sprintf("  unmatched_discharges                  : %s", basename(paths$unmatched_dis)),
    sprintf("  master_joined                         : %s", basename(paths$master_joined)),
    sprintf("  master_joined_extended                : %s", basename(paths$master_extended)),
    sprintf("  This statistics report                : %s", basename(paths$stats)),
    sprintf("  Prob matching report                  : %s", basename(paths$prob_report))
  )
  if (!is.null(ps$prob_assignments) && nrow(ps$prob_assignments) > 0)
    listed <- c(listed, sprintf("  prob_match_assignments                : %s", basename(paths$prob_assign)))
  if (!is.null(ps$prob_candidates) && nrow(ps$prob_candidates) > 0)
    listed <- c(listed, sprintf("  prob_match_candidates                 : %s", basename(paths$prob_cands)))
  if (file.exists(paths$dup_log))
    listed <- c(listed, sprintf("  duplicates_log                        : %s", basename(paths$dup_log)))
  if (!is.null(paths$master_joined_nc))
    listed <- c(listed,
      sprintf("  master_joined_na_coded                : %s  [sentinel NA]",
              basename(paths$master_joined_nc)),
      sprintf("  master_joined_extended_na_coded       : %s  [sentinel NA]",
              basename(paths$master_extended_nc)))

  s9 <- c(sep_thin, "  [9]  OUTPUT FILES", sep_thin, "", listed, "")

  footer <- c(
    sep_thick,
    sprintf("  End of report -- %s", timestamp),
    sep_thick
  )

  c(s1, s2, s3, s4, s5, s6, s7, s8, s9, footer)
}

# ==============================================================================
# .build_prob_report()   -- probabilistic matching report
# ==============================================================================
.build_prob_report <- function(cfg, ps, prefix, label, paths, joined_ext = NULL) {

  vi   <- ps$var_info
  pc   <- ps$prob_candidates
  pa   <- ps$prob_assignments
  mje  <- ps$master_joined_extended
  jr   <- ps$join_result

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  sep_thick <- strrep("=", 70)
  sep_thin  <- strrep("-", 70)

  no_pc <- is.null(pc) || nrow(pc) == 0
  no_pa <- is.null(pa) || nrow(pa) == 0

  # [1] Run metadata
  s1 <- c(
    sep_thick,
    "  Neotree Sample Maker -- Probabilistic Matching Report",
    sep_thick, "",
    sprintf("  Generated  : %s", timestamp),
    sprintf("  Country    : %s", toupper(cfg$country)),
    sprintf("  Source     : %s", cfg$source),
    sprintf("  Filter tag : %s", label), ""
  )

  # [2] Configuration
  s2 <- c(
    sep_thin, "  [2]  CONFIGURATION", sep_thin, "",
    sprintf("  Minimum similarity threshold  : %.0f%%",  cfg$prob_match_min_similarity),
    sprintf("  Max candidates per admission  : %d",      cfg$prob_match_max_candidates),
    sprintf("  Completeness threshold        : %.0f%%",  cfg$prob_match_completeness_threshold * 100),
    sprintf("  Cross-facility search         : %s",      ifelse(isTRUE(cfg$prob_match_cross_facility), "Yes", "No")),
    ""
  )

  # [3] Variable selection
  if (is.null(vi) || length(vi$vars) == 0) {
    s3 <- c(sep_thin, "  [3]  VARIABLE SELECTION", sep_thin, "",
            "  No variables met the completeness threshold -- probabilistic matching skipped.", "")
  } else {
    var_lines <- vapply(names(vi$vars), function(var) {
      is_num <- vi$vars[[var]]
      tol    <- vi$tolerances[[var]]
      col_a  <- vi$col_map_adm[[var]]
      col_d  <- vi$col_map_dis[[var]]
      sprintf("  %-16s  type: %-12s  tol: %-6s  adm_col: %-25s  dis_col: %s",
              var,
              ifelse(is_num, "numeric", "categorical"),
              ifelse(tol == 0, "exact", as.character(tol)),
              col_a, col_d)
    }, character(1))

    s3 <- c(sep_thin, "  [3]  VARIABLE SELECTION", sep_thin, "",
            sprintf("  %d variable(s) selected:", length(vi$vars)),
            var_lines, "")
  }

  # [4] Candidate search
  n_adm_unmatched <- jr$n_unmatched_adm
  n_dis_unmatched <- jr$n_unmatched_dis

  if (no_pc) {
    s4 <- c(sep_thin, "  [4]  CANDIDATE SEARCH", sep_thin, "",
            sprintf("  Input: %d unmatched admissions  x  %d unmatched discharges",
                    n_adm_unmatched, n_dis_unmatched),
            "  Result: no candidate pairs found above the similarity threshold.", "")
  } else {
    n_cands      <- nrow(pc)
    n_adm_w_cand <- length(unique(pc$adm_row_idx))
    pct_cov      <- 100 * n_adm_w_cand / max(n_adm_unmatched, 1)

    # Similarity distribution
    breaks <- c(60, 70, 80, 90, 100)
    sim_dist <- vapply(seq_len(length(breaks) - 1), function(i) {
      n <- sum(pc$overall_similarity >= breaks[i] & pc$overall_similarity < breaks[i + 1])
      sprintf("    %3.0f-%3.0f%%  : %d", breaks[i], breaks[i + 1] - 1, n)
    }, character(1))
    n_100 <- sum(pc$overall_similarity >= 100)

    same_fac_n <- if ("same_facility" %in% names(pc)) sum(pc$same_facility, na.rm = TRUE) else NA
    cross_fac_n <- n_cands - same_fac_n

    s4 <- c(
      sep_thin, "  [4]  CANDIDATE SEARCH", sep_thin, "",
      sprintf("  Input: %d unmatched admissions  x  %d unmatched discharges",
              n_adm_unmatched, n_dis_unmatched),
      sprintf("  Total candidate pairs found   : %d", n_cands),
      sprintf("  Admissions with >=1 candidate  : %d  (%.1f%% of unmatched admissions)",
              n_adm_w_cand, pct_cov),
      if (!is.na(same_fac_n)) sprintf(
        "  Within-facility candidates    : %d  /  Cross-facility: %d",
        same_fac_n, cross_fac_n),
      "",
      "  Similarity distribution of candidates:",
      sim_dist,
      sprintf("    100%%        : %d", n_100),
      ""
    )
  }

  # [5] One-to-one assignments
  if (no_pa) {
    s5 <- c(sep_thin, "  [5]  ONE-TO-ONE ASSIGNMENTS", sep_thin, "",
            "  No pairs accepted (no candidates above threshold, or none survived",
            "  the one-to-one constraint).", "")
  } else {
    n_assign <- nrow(pa)
    avg_sim  <- mean(pa$overall_similarity)
    med_sim  <- median(pa$overall_similarity)
    min_sim  <- min(pa$overall_similarity)
    max_sim  <- max(pa$overall_similarity)

    same_fac_assign <- if ("same_facility" %in% names(pa))
      sum(pa$same_facility, na.rm = TRUE) else NA

    tier_high <- sum(pa$overall_similarity >= 90)
    tier_mid  <- sum(pa$overall_similarity >= 70 & pa$overall_similarity < 90)
    tier_low  <- sum(pa$overall_similarity < 70)

    s5 <- c(
      sep_thin, "  [5]  ONE-TO-ONE ASSIGNMENTS", sep_thin, "",
      sprintf("  Pairs accepted                : %d", n_assign),
      if (!is.na(same_fac_assign))
        sprintf("  Within same facility          : %d  /  Cross-facility: %d",
                same_fac_assign, n_assign - same_fac_assign),
      "",
      sprintf("  Similarity -- mean: %.1f%%  median: %.1f%%  min: %.1f%%  max: %.1f%%",
              avg_sim, med_sim, min_sim, max_sim),
      sprintf("  High confidence (>=90%%)        : %d", tier_high),
      sprintf("  Medium confidence (70-89%%)    : %d", tier_mid),
      sprintf("  Lower confidence (<70%%)       : %d", tier_low),
      ""
    )
  }

  # [6] Per-variable score statistics (of accepted assignments)
  if (!no_pa && !is.null(vi) && length(vi$vars) > 0) {
    var_sim_lines <- vapply(names(vi$vars), function(var) {
      col <- paste0("sim_", var)
      if (!col %in% names(pa)) return(sprintf("  %-16s  --", var))
      vals <- pa[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(sprintf("  %-16s  (no valid scores)", var))
      sprintf("  %-16s  mean: %5.1f%%  median: %5.1f%%  missing: %d / %d",
              var, mean(vals), median(vals), sum(is.na(pa[[col]])), nrow(pa))
    }, character(1))
    s6 <- c(sep_thin, "  [6]  PER-VARIABLE SCORES  (accepted assignments)", sep_thin,
            "", var_sim_lines, "")
  } else {
    s6 <- c(sep_thin, "  [6]  PER-VARIABLE SCORES", sep_thin,
            "", "  (no accepted assignments)", "")
  }

  # [7] master_joined_extended summary
  if (!is.null(mje)) {
    mje_tab <- table(mje$match_type)
    total   <- nrow(mje)
    tab_lines <- vapply(seq_along(mje_tab), function(i)
      sprintf("    %-22s  %6d  %5.1f%%",
              names(mje_tab)[i], mje_tab[i], 100 * mje_tab[i] / total),
      character(1))

    # Outcomes in master_joined_extended
    outcome_col <- if ("neotreeoutcome" %in% names(mje)) "neotreeoutcome" else
                   if ("neotreeoutcome_dis" %in% names(mje)) "neotreeoutcome_dis" else NULL
    out_lines <- if (!is.null(outcome_col)) {
      ot    <- sort(table(mje[[outcome_col]], useNA = "ifany"), decreasing = TRUE)
      n_ot  <- sum(ot)
      c("",
        sprintf("  Outcome distribution (all rows with outcome data, n=%d):", n_ot),
        vapply(seq_along(ot), function(i) {
          lbl <- names(ot)[i]; if (is.na(lbl)) lbl <- "(NA)"
          sprintf("    %-30s  %6d  %5.1f%%", lbl, ot[i], 100 * ot[i] / n_ot)
        }, character(1))
      )
    } else character(0)

    s7 <- c(
      sep_thin, "  [7]  MASTER_JOINED_EXTENDED SUMMARY", sep_thin, "",
      sprintf("  Total rows : %d", total),
      tab_lines,
      out_lines, ""
    )
  } else {
    s7 <- character(0)
  }

  # [8] Top assignments (up to 20)
  if (!no_pa) {
    top_n   <- min(20, nrow(pa))
    top     <- pa[order(-pa$overall_similarity), ][seq_len(top_n), ]
    top_lines <- vapply(seq_len(top_n), function(i) {
      r <- top[i, ]
      sprintf("  %3d. sim: %5.1f%%  adm_uid: %-20s -> dis_uid: %-20s  fac_same: %s",
              i, r$overall_similarity,
              r$adm_uid, r$dis_uid,
              ifelse(isTRUE(r$same_facility), "yes", "no"))
    }, character(1))

    s8 <- c(
      sep_thin,
      sprintf("  [8]  TOP %d ACCEPTED ASSIGNMENTS (sorted by similarity)", top_n),
      sep_thin, "", top_lines, ""
    )
  } else {
    s8 <- c(sep_thin, "  [8]  TOP ASSIGNMENTS", sep_thin, "",
            "  (no assignments)", "")
  }

  # [9] Output files
  n_jext <- if (!is.null(joined_ext)) nrow(joined_ext) else 0L
  s9_files <- c(
    sprintf("  joined_admissions_discharges_extended : %d rows  -> %s",
            n_jext, basename(paths$joined_extended)),
    sprintf("  prob_match_assignments                : %s", basename(paths$prob_assign)),
    sprintf("  prob_match_candidates                 : %s", basename(paths$prob_cands)),
    sprintf("  master_joined_extended                : %s", basename(paths$master_extended)),
    sprintf("  This prob matching report             : %s", basename(paths$prob_report))
  )
  s9 <- c(sep_thin, "  [9]  OUTPUT FILES", sep_thin, "", s9_files, "")

  footer <- c(
    sep_thick,
    sprintf("  End of probabilistic matching report -- %s", timestamp),
    sep_thick
  )

  c(s1, s2, s3, s4, s5, s6, s7, s8, s9, footer)
}

# ==============================================================================
# NA-CODED MASTER BUILDERS
# ==============================================================================
#
# These functions reconstruct na_coded versions of master_joined and
# master_joined_extended without re-running any join or matching logic.
#
# Strategy:
#   All join/match work runs on the standard blank-NA data.  After the standard
#   master files are built, these helpers substitute data column values with
#   their na_coded counterparts (sentinel codes instead of blank NA) using a
#   vectorised uid+facility lookup.
#
#   Pipeline-generated columns (match_type, match_key, adm_date_parsed,
#   prob_match_similarity) are kept unchanged from the standard master_joined.
#
# Correctness note:
#   uid+facility uniqueness is guaranteed post-deduplication, so match() returns
#   the correct row.  Date filtering is automatically respected because only rows
#   present in master_joined are looked up; unfiltered rows are simply absent.
# ==============================================================================

.NA_CODED_PIPELINE_COLS <- c("match_type", "prob_match_similarity",
                              "match_key", "adm_date_parsed")

# Build dis_col_map: master_joined column name -> original discharge column name.
# Discharge columns that overlap with admission columns carry a "_dis" suffix in
# master_joined; unique discharge columns keep their original names.
.make_dis_col_map <- function(master_col_names, adm_col_names, dis_col_names) {
  dis_in_master <- setdiff(master_col_names, c(adm_col_names, .NA_CODED_PIPELINE_COLS))
  dis_col_map   <- character(0)
  for (col in dis_in_master) {
    if (grepl("_dis$", col)) {
      orig <- sub("_dis$", "", col)
      if (orig %in% dis_col_names) dis_col_map[col] <- orig
    } else {
      if (col %in% dis_col_names) dis_col_map[col] <- col
    }
  }
  dis_col_map
}

# ------------------------------------------------------------------------------
# .build_na_coded_master_joined()
# Handles direct_match and unmatched rows (uid+facility is the same on both
# admission and discharge sides for direct_match, so a single key lookup works).
# ------------------------------------------------------------------------------
.build_na_coded_master_joined <- function(master_joined, adm_na_coded, dis_na_coded) {

  SEP         <- "\x01"
  dis_col_map <- .make_dis_col_map(names(master_joined),
                                   names(adm_na_coded),
                                   names(dis_na_coded))

  mj_key  <- paste(master_joined$uid, master_joined$facility, sep = SEP)
  adm_key <- paste(adm_na_coded$uid,  adm_na_coded$facility,  sep = SEP)
  dis_key <- paste(dis_na_coded$uid,  dis_na_coded$facility,  sep = SEP)

  adm_idx        <- match(mj_key, adm_key)
  dis_idx        <- match(mj_key, dis_key)
  unmatched_mask <- master_joined$match_type == "unmatched"

  result <- master_joined  # start from standard: pipeline metadata cols preserved

  # Replace admission data columns
  adm_data_cols <- setdiff(intersect(names(adm_na_coded), names(master_joined)),
                           .NA_CODED_PIPELINE_COLS)
  for (col in adm_data_cols) {
    result[[col]] <- adm_na_coded[[col]][adm_idx]
  }

  # Replace discharge data columns
  for (master_col in names(dis_col_map)) {
    orig_col             <- dis_col_map[[master_col]]
    vals                 <- dis_na_coded[[orig_col]][dis_idx]
    vals[unmatched_mask] <- NA   # unmatched rows carry no discharge data
    result[[master_col]] <- vals
  }

  result
}

# ------------------------------------------------------------------------------
# .build_na_coded_master_joined_extended()
# Extends .build_na_coded_master_joined() to handle prob_match rows, where the
# discharge uid+facility differs from the admission uid+facility.  The correct
# discharge row is identified via prob_assignments$dis_uid / dis_facility.
# ------------------------------------------------------------------------------
.build_na_coded_master_joined_extended <- function(master_joined_na_coded,
                                                    master_joined_extended,
                                                    prob_assignments,
                                                    adm_na_coded, dis_na_coded) {

  # No prob assignments: extended == master_joined (structure is identical)
  if (is.null(prob_assignments) || nrow(prob_assignments) == 0) {
    result <- master_joined_na_coded
    result$prob_match_similarity <- NA_real_
    return(result)
  }

  SEP         <- "\x01"
  dis_col_map <- .make_dis_col_map(names(master_joined_extended),
                                   names(adm_na_coded),
                                   names(dis_na_coded))

  adm_key <- paste(adm_na_coded$uid, adm_na_coded$facility, sep = SEP)
  dis_key <- paste(dis_na_coded$uid, dis_na_coded$facility, sep = SEP)

  prob_adm_keys <- paste(prob_assignments$adm_uid, prob_assignments$adm_facility, sep = SEP)
  prob_dis_keys <- paste(prob_assignments$dis_uid, prob_assignments$dis_facility, sep = SEP)

  mj_na_key <- paste(master_joined_na_coded$uid,
                     master_joined_na_coded$facility, sep = SEP)

  # Rows that were prob-matched are promoted out of "unmatched"; keep the rest
  direct_rows     <- master_joined_na_coded[
    master_joined_na_coded$match_type == "direct_match", ]
  still_unmatched <- master_joined_na_coded[
    master_joined_na_coded$match_type == "unmatched" & !mj_na_key %in% prob_adm_keys, ]

  # Build each prob_match row from na_coded sources
  n_assign  <- nrow(prob_assignments)
  prob_rows <- vector("list", n_assign)

  for (k in seq_len(n_assign)) {

    adm_key_k <- prob_adm_keys[k]
    dis_key_k <- prob_dis_keys[k]
    ai        <- match(adm_key_k, adm_key)
    di        <- match(dis_key_k, dis_key)

    # Base row: the unmatched entry in master_joined_na_coded (admission already na_coded)
    base_mask <- mj_na_key == adm_key_k &
                 master_joined_na_coded$match_type == "unmatched"

    if (sum(base_mask) == 1) {
      base_row <- master_joined_na_coded[which(base_mask), , drop = FALSE]
    } else if (!is.na(ai)) {
      # Fallback: build from adm_na_coded directly
      base_row <- adm_na_coded[ai, , drop = FALSE]
      for (mc in setdiff(names(master_joined_extended), names(base_row)))
        base_row[[mc]] <- NA
      base_row <- base_row[, names(master_joined_extended), drop = FALSE]
    } else {
      next   # admission row unresolvable -- skip this assignment
    }

    # Fill discharge columns from na_coded discharges using dis_uid+dis_facility
    if (!is.na(di)) {
      dis_row <- dis_na_coded[di, , drop = FALSE]
      for (master_col in names(dis_col_map)) {
        orig_col <- dis_col_map[[master_col]]
        if (orig_col %in% names(dis_row))
          base_row[[master_col]] <- dis_row[[orig_col]]
      }
    }

    base_row$match_type            <- "prob_match"
    base_row$prob_match_similarity <- prob_assignments$overall_similarity[k]

    prob_rows[[k]] <- base_row
  }

  prob_df  <- do.call(rbind, Filter(Negate(is.null), prob_rows))
  mje_nc   <- rbind(direct_rows, prob_df, still_unmatched)
  rownames(mje_nc) <- NULL

  mje_nc
}

# ==============================================================================
# Internal helper: facility breakdown table
# ==============================================================================
.fac_breakdown <- function(df, title) {
  if (nrow(df) == 0 || !"facility" %in% names(df)) {
    return(sprintf("  %s : (none)", title))
  }
  fac_tab <- sort(table(df$facility), decreasing = TRUE)
  total   <- nrow(df)
  c(
    sprintf("  %s  (total: %d):", title, total),
    vapply(seq_along(fac_tab), function(i)
      sprintf("    %-22s  %6d  %5.1f%%",
              names(fac_tab)[i], fac_tab[i], 100 * fac_tab[i] / total),
      character(1))
  )
}
