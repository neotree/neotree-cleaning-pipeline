################################################################################
# Neotree Sample Maker -- Module: Data Profiler
# FILE:    modules/data_profiler.R
# PURPOSE: Shared profiling logic used automatically by run_sample_maker.R and
#          run_subsample_maker.R to generate a variable summary alongside every
#          output CSV.  Can also be sourced manually from run_data_profiler.R.
#
# EXPORTED FUNCTION
#   profile_and_write(df, out_path_base,
#                     numeric_threshold    = 0.90,
#                     max_numeric_distinct = 500,
#                     source_label         = NULL,
#                     quiet                = FALSE)
#
#   Arguments:
#     df               Data frame to profile.
#     out_path_base    Full file path WITHOUT extension.
#                      Two files are written:
#                        {out_path_base}_variable_profile.csv
#                        {out_path_base}_variable_profile.txt
#     numeric_threshold
#                      Proportion of non-missing values that must be coercible
#                      to a number for the column to be treated as numeric.
#                      Default: 0.90.
#     max_numeric_distinct
#                      Maximum number of distinct values for numeric detection.
#                      Columns with more distinct values are always categorical.
#                      Default: 500.
#     source_label     Optional human-readable label shown in the TXT header
#                      (e.g. "master_joined", "admissions (cleaned)").
#                      Defaults to basename(out_path_base).
#     quiet            If TRUE, suppress progress messages.  Default: FALSE.
#
#   Returns: named list(csv = path, txt = path) invisibly.
#
# NAMING CONVENTION
#   All internal helpers are prefixed .dp_ to avoid name conflicts when this
#   module is loaded alongside run_data_profiler.R in the same session.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-05)
################################################################################

# ==============================================================================
# Internal helpers
# ==============================================================================

.dp_mode_val <- function(x) {
  x <- x[!is.na(x) & nchar(as.character(x)) > 0]
  if (length(x) == 0) return(NA_character_)
  tab <- sort(table(x), decreasing = TRUE)
  names(tab)[1]
}

.dp_profile_df <- function(df, numeric_threshold = 0.90, max_numeric_distinct = 500) {
  n_rows <- nrow(df)
  rows <- lapply(names(df), function(col_name) {
    col <- df[[col_name]]
    is_missing <- is.na(col) |
      (is.character(col) & nchar(trimws(as.character(col))) == 0)
    n_missing  <- sum(is_missing)
    n_present  <- n_rows - n_missing
    pct_missing <- if (n_rows > 0) round(100 * n_missing / n_rows, 1) else NA_real_
    present_vals <- col[!is_missing]
    is_boolean   <- is.logical(col)
    num_coerce   <- suppressWarnings(as.numeric(present_vals))
    n_numeric    <- sum(!is.na(num_coerce))
    n_distinct   <- length(unique(present_vals))
    is_numeric   <- !is_boolean && (n_present > 0) &&
      (n_distinct <= max_numeric_distinct) &&
      (n_present == 0 || n_numeric / n_present >= numeric_threshold)
    col_type <- if (is_boolean) "boolean" else if (is_numeric) "numeric" else "categorical"

    row <- data.frame(
      variable = col_name, type = col_type,
      n_total = n_rows, n_present = n_present,
      n_missing = n_missing, pct_missing = pct_missing,
      stringsAsFactors = FALSE
    )
    samp_raw <- if (length(present_vals) > 0) {
      tab_raw <- sort(table(as.character(present_vals)), decreasing = TRUE)
      paste(names(tab_raw)[seq_len(min(3, length(tab_raw)))], collapse = " | ")
    } else NA_character_

    if (is_boolean) {
      n_true_val  <- sum(col == TRUE,  na.rm = TRUE)
      n_false_val <- sum(col == FALSE, na.rm = TRUE)
      row$n_true   <- n_true_val
      row$n_false  <- n_false_val
      row$pct_true <- if (n_present > 0) round(100 * n_true_val / n_present, 1) else NA_real_
      row$sample_values <- samp_raw; row$n_distinct <- n_distinct
      row$min <- NA_real_; row$max <- NA_real_; row$mean <- NA_real_
      row$median <- NA_real_; row$sd <- NA_real_; row$mode_value <- NA_character_
      row$top1_value <- NA_character_; row$top1_n <- NA_integer_
      row$top2_value <- NA_character_; row$top2_n <- NA_integer_
      row$top3_value <- NA_character_; row$top3_n <- NA_integer_
    } else if (is_numeric) {
      num_vals <- num_coerce[!is.na(num_coerce)]
      row$min    <- if (length(num_vals) > 0) round(min(num_vals),    4) else NA_real_
      row$max    <- if (length(num_vals) > 0) round(max(num_vals),    4) else NA_real_
      row$mean   <- if (length(num_vals) > 0) round(mean(num_vals),   4) else NA_real_
      row$median <- if (length(num_vals) > 0) round(median(num_vals), 4) else NA_real_
      row$sd     <- if (length(num_vals) > 1) round(sd(num_vals),     4) else NA_real_
      row$mode_value <- .dp_mode_val(as.character(present_vals))
      row$n_distinct <- n_distinct; row$sample_values <- samp_raw
      row$n_true <- NA_integer_; row$n_false <- NA_integer_; row$pct_true <- NA_real_
      row$top1_value <- NA_character_; row$top1_n <- NA_integer_
      row$top2_value <- NA_character_; row$top2_n <- NA_integer_
      row$top3_value <- NA_character_; row$top3_n <- NA_integer_
    } else {
      tab <- sort(table(present_vals), decreasing = TRUE)
      gv  <- function(r) list(
        val = if (length(tab) >= r) names(tab)[r] else NA_character_,
        n   = if (length(tab) >= r) as.integer(tab[r]) else NA_integer_
      )
      t1 <- gv(1); t2 <- gv(2); t3 <- gv(3)
      row$n_distinct <- n_distinct; row$sample_values <- samp_raw
      row$top1_value <- t1$val; row$top1_n <- t1$n
      row$top2_value <- t2$val; row$top2_n <- t2$n
      row$top3_value <- t3$val; row$top3_n <- t3$n
      row$n_true <- NA_integer_; row$n_false <- NA_integer_; row$pct_true <- NA_real_
      row$min <- NA_real_; row$max <- NA_real_; row$mean <- NA_real_
      row$median <- NA_real_; row$sd <- NA_real_; row$mode_value <- NA_character_
    }
    row
  })
  prof <- do.call(rbind, rows)
  col_order <- c(
    "variable", "type", "n_total", "n_present", "n_missing", "pct_missing",
    "min", "max", "mean", "median", "sd", "mode_value", "n_distinct", "sample_values",
    "n_true", "n_false", "pct_true",
    "top1_value", "top1_n", "top2_value", "top2_n", "top3_value", "top3_n"
  )
  prof[, col_order]
}

.dp_build_txt <- function(profile_df, source_label, n_rows) {
  timestamp  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  sep_thick  <- strrep("=", 72)
  sep_thin   <- strrep("-", 72)

  lines <- c(
    sep_thick,
    "  Neotree Sample Maker -- Variable Profile Report",
    sep_thick, "",
    sprintf("  Generated : %s", timestamp),
    sprintf("  Source    : %s", source_label),
    sprintf("  Rows      : %d", n_rows),
    sprintf(
      "  Columns   : %d  (%d numeric, %d boolean, %d categorical)",
      nrow(profile_df),
      sum(profile_df$type == "numeric"),
      sum(profile_df$type == "boolean"),
      sum(profile_df$type == "categorical")
    ), ""
  )

  # Numeric
  num_rows <- profile_df[profile_df$type == "numeric", ]
  if (nrow(num_rows) > 0) {
    lines <- c(lines, sep_thin, "  NUMERIC VARIABLES", sep_thin, "",
      sprintf("  %-28s  %7s  %7s  %8s  %8s  %8s  %8s  %-20s",
        "Variable", "n", "miss%", "Min", "Max", "Mean", "Median", "sample_values"),
      sprintf("  %-28s  %7s  %7s  %8s  %8s  %8s  %8s  %-20s",
        strrep("-", 28), strrep("-", 7), strrep("-", 7),
        strrep("-", 8), strrep("-", 8), strrep("-", 8), strrep("-", 8), strrep("-", 20))
    )
    for (i in seq_len(nrow(num_rows))) {
      r <- num_rows[i, ]
      lines <- c(lines, sprintf(
        "  %-28s  %7d  %6.1f%%  %8s  %8s  %8s  %8s  %s",
        r$variable, r$n_present, r$pct_missing,
        if (!is.na(r$min))    format(r$min,    nsmall = 1) else "NA",
        if (!is.na(r$max))    format(r$max,    nsmall = 1) else "NA",
        if (!is.na(r$mean))   format(r$mean,   nsmall = 1) else "NA",
        if (!is.na(r$median)) format(r$median, nsmall = 1) else "NA",
        if (!is.na(r$sample_values)) r$sample_values else "NA"
      ))
    }
    lines <- c(lines, "")
  }

  # Boolean
  bool_rows <- profile_df[profile_df$type == "boolean", ]
  if (nrow(bool_rows) > 0) {
    lines <- c(lines, sep_thin, "  BOOLEAN VARIABLES", sep_thin, "",
      sprintf("  %-30s  %8s  %8s  %8s  %8s  %8s",
        "Variable", "n", "miss%", "n_true", "n_false", "pct_true"),
      sprintf("  %-30s  %8s  %8s  %8s  %8s  %8s",
        strrep("-", 30), strrep("-", 8), strrep("-", 8),
        strrep("-", 8), strrep("-", 8), strrep("-", 8))
    )
    for (i in seq_len(nrow(bool_rows))) {
      r <- bool_rows[i, ]
      lines <- c(lines, sprintf(
        "  %-30s  %8d  %7.1f%%  %8d  %8d  %7.1f%%",
        r$variable, r$n_present, r$pct_missing,
        r$n_true, r$n_false, r$pct_true
      ))
    }
    lines <- c(lines, "")
  }

  # Categorical
  cat_rows <- profile_df[profile_df$type == "categorical", ]
  if (nrow(cat_rows) > 0) {
    lines <- c(lines, sep_thin, "  CATEGORICAL VARIABLES", sep_thin, "",
      sprintf("  %-30s  %8s  %8s  %8s  %s",
        "Variable", "n", "miss%", "n_dist", "Top values  (value : count)"),
      sprintf("  %-30s  %8s  %8s  %8s  %s",
        strrep("-", 30), strrep("-", 8), strrep("-", 8),
        strrep("-", 8), strrep("-", 28))
    )
    for (i in seq_len(nrow(cat_rows))) {
      r <- cat_rows[i, ]
      top_parts <- character(0)
      for (pair in list(c(r$top1_value, r$top1_n), c(r$top2_value, r$top2_n),
                        c(r$top3_value, r$top3_n))) {
        if (!is.na(pair[1])) top_parts <- c(top_parts, sprintf("%s:%s", pair[1], pair[2]))
      }
      top_str <- if (length(top_parts) > 0) paste(top_parts, collapse = "  ") else "(no data)"
      nd_str  <- if (!is.na(r$n_distinct)) as.character(r$n_distinct) else "NA"
      lines <- c(lines, sprintf(
        "  %-30s  %8d  %7.1f%%  %8s  %s",
        r$variable, r$n_present, r$pct_missing, nd_str, top_str
      ))
    }
    lines <- c(lines, "")
  }

  # Missing summary
  miss_rows <- profile_df[!is.na(profile_df$pct_missing) & profile_df$pct_missing > 0, ]
  if (nrow(miss_rows) > 0) {
    miss_rows <- miss_rows[order(-miss_rows$pct_missing), ]
    lines <- c(lines, sep_thin,
      "  MISSING DATA  (columns with > 0% missing, sorted descending)",
      sep_thin, "",
      sprintf("  %-30s  %8s  %8s", "Variable", "n_miss", "pct_miss"),
      sprintf("  %-30s  %8s  %8s", strrep("-", 30), strrep("-", 8), strrep("-", 8))
    )
    for (i in seq_len(nrow(miss_rows))) {
      r <- miss_rows[i, ]
      lines <- c(lines, sprintf(
        "  %-30s  %8d  %7.1f%%", r$variable, r$n_missing, r$pct_missing
      ))
    }
    lines <- c(lines, "")
  }

  c(lines, sep_thick,
    sprintf("  End of variable profile -- %s", timestamp),
    sep_thick)
}

# ==============================================================================
# Exported function
# ==============================================================================

profile_and_write <- function(df,
                               out_path_base,
                               numeric_threshold    = 0.90,
                               max_numeric_distinct = 500,
                               source_label         = NULL,
                               quiet                = FALSE) {
  if (is.null(source_label) || !nchar(trimws(source_label)))
    source_label <- basename(out_path_base)

  out_csv <- paste0(out_path_base, "_variable_profile.csv")
  out_txt <- paste0(out_path_base, "_variable_profile.txt")

  # Ensure parent directory exists
  out_par <- dirname(out_csv)
  if (!dir.exists(out_par)) dir.create(out_par, recursive = TRUE)

  if (!quiet) cat(sprintf("[profile] %s\n", source_label))

  prof <- .dp_profile_df(df, numeric_threshold, max_numeric_distinct)

  if (!quiet) cat(sprintf(
    "[profile]   %d cols  (%d numeric, %d boolean, %d categorical)  ->  %s\n",
    nrow(prof),
    sum(prof$type == "numeric"),
    sum(prof$type == "boolean"),
    sum(prof$type == "categorical"),
    basename(out_csv)
  ))

  write.csv(prof, out_csv, row.names = FALSE, na = "")
  writeLines(.dp_build_txt(prof, source_label, nrow(df)), out_txt)

  invisible(list(csv = out_csv, txt = out_txt))
}
