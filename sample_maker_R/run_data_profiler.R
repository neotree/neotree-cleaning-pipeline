#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Data Profiler  (utility script)
# FILE:    run_data_profiler.R
# PURPOSE: Profile any pipeline CSV file and write a variable summary with
#          data types and descriptive statistics.  Use this to identify
#          variable names and value ranges before configuring
#          sub_exclusion_filters in config_subsample_maker.R.
#
# OUTPUTS (written next to the input file, or to profile_output_dir):
#   {prefix}_variable_profile_{label}.csv
#       One row per column.  Columns:
#         variable         -- column name
#         type             -- "numeric", "boolean", or "categorical"
#         n_total          -- total rows in file
#         n_present        -- rows where value is not NA / empty
#         n_missing        -- rows where value is NA or empty
#         pct_missing      -- missing %
#       For numeric columns (additional fields):
#         min, max, mean, median, mode_value (most frequent value),
#         sd, n_distinct, sample_values
#       For boolean columns (additional fields):
#         n_true, n_false, pct_true, sample_values
#       For categorical columns (additional fields):
#         n_distinct       -- number of unique non-missing values
#         sample_values    -- up to 3 most common values, pipe-separated
#         top1_value / top1_n   -- most frequent value and its count
#         top2_value / top2_n
#         top3_value / top3_n
#
#   {prefix}_variable_profile_{label}.txt
#       Human-readable summary for quick review.
#
# USAGE
#   From RStudio: set PROFILER_CONFIG below, then Source.
#   From terminal:
#     Rscript run_data_profiler.R
#   Or pass the input file as a command-line argument:
#     Rscript run_data_profiler.R path/to/master_joined.csv
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-04)
################################################################################

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Data Profiler\n")
cat("================================================================\n\n")

# ==============================================================================
# CONFIGURATION  -- edit this section
# ==============================================================================

PROFILER_CONFIG <- list(
  # Path to the CSV file to profile.
  # Any pipeline output works: master_joined, master_joined_extended,
  # subsample_master, joined_admissions_discharges, etc.
  input_file = "outputs/zim_master/from_database/R_cleaned/ZIM_db_r_unmatched_discharges_to_20260303.csv",

  # Output directory.  NULL -> same directory as input_file.
  output_dir = NULL,

  # Numeric detection: a column is treated as numeric if the proportion of
  # rows that can be coerced to a number (excluding NA/empty) is >= this
  # threshold.  Default 0.90 handles columns with occasional text codes.
  numeric_threshold = 0.90,

  # Maximum number of distinct values before a column is always treated as
  # categorical regardless of numeric_threshold.  Prevents treating integer
  # ID columns as numeric for statistical purposes.
  max_numeric_distinct = 500
)

# ==============================================================================
# COMMAND-LINE OVERRIDE
# ==============================================================================

local({
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && nchar(trimws(args[1])) > 0) {
    p <- trimws(args[1])
    if (!file.exists(p)) {
      p2 <- file.path(
        dirname(normalizePath(commandArgs(trailingOnly = FALSE)[
          grep("--file=", commandArgs(trailingOnly = FALSE))
        ], mustWork = FALSE)),
        args[1]
      )
      if (file.exists(p2)) p <- p2
    }
    if (!file.exists(p)) stop(sprintf("Input file not found: %s", args[1]))
    PROFILER_CONFIG$input_file <<- p
    cat(sprintf("Input file (from command line): %s\n\n", p))
  }
})

# ==============================================================================
# RESOLVE PATHS
# ==============================================================================

input_path <- PROFILER_CONFIG$input_file
if (!file.exists(input_path)) {
  stop(sprintf("Input file not found:\n  %s", input_path))
}

out_dir <- if (!is.null(PROFILER_CONFIG$output_dir)) {
  PROFILER_CONFIG$output_dir
} else {
  dirname(normalizePath(input_path))
}
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

base_name <- tools::file_path_sans_ext(basename(input_path))
out_csv <- file.path(out_dir, paste0(base_name, "_variable_profile.csv"))
out_txt <- file.path(out_dir, paste0(base_name, "_variable_profile.txt"))

cat(sprintf("Input  : %s\n", basename(input_path)))
cat(sprintf("Output : %s\n", basename(out_csv)))
cat(sprintf("         %s\n\n", basename(out_txt)))

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading data...\n")
df <- tryCatch(
  read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE),
  error = function(e) stop(sprintf("Failed to read input file:\n  %s", conditionMessage(e)))
)
cat(sprintf("  %d rows x %d columns\n\n", nrow(df), ncol(df)))

n_rows <- nrow(df)

# ==============================================================================
# HELPER: mode (most frequent non-NA value)
# ==============================================================================
.mode_val <- function(x) {
  x <- x[!is.na(x) & nchar(as.character(x)) > 0]
  if (length(x) == 0) {
    return(NA_character_)
  }
  tab <- sort(table(x), decreasing = TRUE)
  names(tab)[1]
}

# ==============================================================================
# PROFILE EACH COLUMN
# ==============================================================================

cat("Profiling columns...\n")

profile_rows <- lapply(names(df), function(col_name) {
  col <- df[[col_name]]

  # Missing: NA or empty string
  is_missing <- is.na(col) | (is.character(col) & nchar(trimws(as.character(col))) == 0)
  n_missing <- sum(is_missing)
  n_present <- n_rows - n_missing
  pct_missing <- if (n_rows > 0) round(100 * n_missing / n_rows, 1) else NA_real_

  present_vals <- col[!is_missing]

  # Determine type
  # Boolean check must come first: R logical columns (TRUE/FALSE) would
  # otherwise pass the numeric threshold test because as.numeric(TRUE) = 1.
  is_boolean <- is.logical(col)

  num_coerce <- suppressWarnings(as.numeric(present_vals))
  n_numeric <- sum(!is.na(num_coerce))
  n_distinct <- length(unique(present_vals))

  is_numeric <- !is_boolean &&
    (n_present > 0) &&
    (n_distinct <= PROFILER_CONFIG$max_numeric_distinct) &&
    ((n_present == 0) || (n_numeric / n_present >= PROFILER_CONFIG$numeric_threshold))

  col_type <- if (is_boolean) "boolean" else if (is_numeric) "numeric" else "categorical"

  # Base row
  row <- data.frame(
    variable = col_name,
    type = col_type,
    n_total = n_rows,
    n_present = n_present,
    n_missing = n_missing,
    pct_missing = pct_missing,
    stringsAsFactors = FALSE
  )

  # sample_values: up to 3 distinct raw values as stored in the CSV.
  # For numeric columns this shows the actual stored format (e.g. "24" vs
  # "24.0" vs "24.50"), so you can see how many decimals are used.
  # For categorical columns it shows exact capitalisation and spelling.
  # Values are drawn from the most-frequent entries (top of frequency table).
  samp_raw <- if (length(present_vals) > 0) {
    tab_raw <- sort(table(as.character(present_vals)), decreasing = TRUE)
    paste(names(tab_raw)[seq_len(min(3, length(tab_raw)))], collapse = " | ")
  } else {
    NA_character_
  }

  if (is_boolean) {
    n_true_val <- sum(col == TRUE, na.rm = TRUE)
    n_false_val <- sum(col == FALSE, na.rm = TRUE)
    pct_true_val <- if (n_present > 0) round(100 * n_true_val / n_present, 1) else NA_real_
    row$n_true <- n_true_val
    row$n_false <- n_false_val
    row$pct_true <- pct_true_val
    row$sample_values <- samp_raw
    row$n_distinct <- n_distinct
    # Numeric fields blank
    row$min <- NA_real_
    row$max <- NA_real_
    row$mean <- NA_real_
    row$median <- NA_real_
    row$sd <- NA_real_
    row$mode_value <- NA_character_
    # Categorical fields blank
    row$top1_value <- NA_character_
    row$top1_n <- NA_integer_
    row$top2_value <- NA_character_
    row$top2_n <- NA_integer_
    row$top3_value <- NA_character_
    row$top3_n <- NA_integer_
  } else if (is_numeric) {
    num_vals <- num_coerce[!is.na(num_coerce)]
    mode_v <- .mode_val(as.character(present_vals))
    row$min <- if (length(num_vals) > 0) round(min(num_vals), 4) else NA_real_
    row$max <- if (length(num_vals) > 0) round(max(num_vals), 4) else NA_real_
    row$mean <- if (length(num_vals) > 0) round(mean(num_vals), 4) else NA_real_
    row$median <- if (length(num_vals) > 0) round(median(num_vals), 4) else NA_real_
    row$sd <- if (length(num_vals) > 1) round(sd(num_vals), 4) else NA_real_
    row$mode_value <- mode_v
    row$n_distinct <- n_distinct
    row$sample_values <- samp_raw
    # Boolean fields blank
    row$n_true <- NA_integer_
    row$n_false <- NA_integer_
    row$pct_true <- NA_real_
    # Categorical fields blank
    row$top1_value <- NA_character_
    row$top1_n <- NA_integer_
    row$top2_value <- NA_character_
    row$top2_n <- NA_integer_
    row$top3_value <- NA_character_
    row$top3_n <- NA_integer_
  } else {
    tab <- sort(table(present_vals), decreasing = TRUE)
    get_top <- function(rank) {
      list(
        val = if (length(tab) >= rank) names(tab)[rank] else NA_character_,
        n   = if (length(tab) >= rank) as.integer(tab[rank]) else NA_integer_
      )
    }
    t1 <- get_top(1)
    t2 <- get_top(2)
    t3 <- get_top(3)
    row$n_distinct <- n_distinct
    row$sample_values <- samp_raw
    row$top1_value <- t1$val
    row$top1_n <- t1$n
    row$top2_value <- t2$val
    row$top2_n <- t2$n
    row$top3_value <- t3$val
    row$top3_n <- t3$n
    # Boolean fields blank
    row$n_true <- NA_integer_
    row$n_false <- NA_integer_
    row$pct_true <- NA_real_
    # Numeric fields blank
    row$min <- NA_real_
    row$max <- NA_real_
    row$mean <- NA_real_
    row$median <- NA_real_
    row$sd <- NA_real_
    row$mode_value <- NA_character_
  }

  row
})

profile_df <- do.call(rbind, profile_rows)

# Reorder columns for readability
col_order <- c(
  "variable", "type", "n_total", "n_present", "n_missing", "pct_missing",
  "min", "max", "mean", "median", "sd", "mode_value", "n_distinct",
  "sample_values",
  "n_true", "n_false", "pct_true",
  "top1_value", "top1_n", "top2_value", "top2_n", "top3_value", "top3_n"
)
profile_df <- profile_df[, col_order]

cat(sprintf(
  "  Profiled %d columns  (%d numeric, %d boolean, %d categorical)\n\n",
  nrow(profile_df),
  sum(profile_df$type == "numeric"),
  sum(profile_df$type == "boolean"),
  sum(profile_df$type == "categorical")
))

# ==============================================================================
# WRITE CSV
# ==============================================================================

write.csv(profile_df, out_csv, row.names = FALSE, na = "")
cat(sprintf("[output] Variable profile CSV : %s\n", basename(out_csv)))

# ==============================================================================
# WRITE TEXT REPORT
# ==============================================================================

sep_thick <- strrep("=", 72)
sep_thin <- strrep("-", 72)
timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

report_lines <- c(
  sep_thick,
  "  Neotree Sample Maker -- Variable Profile Report",
  sep_thick, "",
  sprintf("  Generated : %s", timestamp),
  sprintf("  Source    : %s", basename(input_path)),
  sprintf("  Rows      : %d", n_rows),
  sprintf(
    "  Columns   : %d  (%d numeric, %d boolean, %d categorical)",
    nrow(profile_df),
    sum(profile_df$type == "numeric"),
    sum(profile_df$type == "boolean"),
    sum(profile_df$type == "categorical")
  ),
  "",
  "  Use this report to identify variable names and value ranges when",
  "  configuring sub_exclusion_filters in config_subsample_maker.R.",
  ""
)

# Numeric section
num_rows <- profile_df[profile_df$type == "numeric", ]
if (nrow(num_rows) > 0) {
  report_lines <- c(
    report_lines,
    sep_thin,
    "  NUMERIC VARIABLES",
    "  sample_values shows up to 3 raw values as stored in the CSV.",
    "  Use these to understand whether the variable uses decimals, because",
    "  this affects which rows a threshold catches.  For example, if gestation",
    "  is stored as whole numbers only, <= 24 excludes exactly those records.",
    "  If half-weeks exist (e.g. 24.5), <= 24 would also exclude 24.5.",
    "  In R, 24 and 24.0 are the same number, so the decimal notation in",
    "  your filter has no effect -- only the numeric value of the threshold",
    "  matters.  Check sample_values to know what precision the data uses.",
    sep_thin, "",
    sprintf(
      "  %-28s  %7s  %7s  %8s  %8s  %8s  %8s  %-20s",
      "Variable", "n", "n_miss%", "Min", "Max", "Mean", "Median", "sample_values (raw)"
    ),
    sprintf(
      "  %-28s  %7s  %7s  %8s  %8s  %8s  %8s  %-20s",
      strrep("-", 28), strrep("-", 7), strrep("-", 7),
      strrep("-", 8), strrep("-", 8), strrep("-", 8),
      strrep("-", 8), strrep("-", 20)
    )
  )
  for (i in seq_len(nrow(num_rows))) {
    r <- num_rows[i, ]
    report_lines <- c(
      report_lines,
      sprintf(
        "  %-28s  %7d  %6.1f%%  %8s  %8s  %8s  %8s  %s",
        r$variable,
        r$n_present,
        r$pct_missing,
        if (!is.na(r$min)) format(r$min, nsmall = 1) else "NA",
        if (!is.na(r$max)) format(r$max, nsmall = 1) else "NA",
        if (!is.na(r$mean)) format(r$mean, nsmall = 1) else "NA",
        if (!is.na(r$median)) format(r$median, nsmall = 1) else "NA",
        if (!is.na(r$sample_values)) r$sample_values else "NA"
      )
    )
  }
  report_lines <- c(report_lines, "")
}

# Boolean section
bool_rows <- profile_df[profile_df$type == "boolean", ]
if (nrow(bool_rows) > 0) {
  report_lines <- c(
    report_lines,
    sep_thin,
    "  BOOLEAN VARIABLES",
    "  These columns contain TRUE/FALSE values (R logical type).  Neotree stores",
    "  boolean fields as TRUE/FALSE in the CSV; read.csv converts them to R logical.",
    "  n_true and n_false count non-missing rows only.  pct_true is the percentage",
    "  of TRUE values among non-missing rows.",
    "  Boolean columns cannot be used with numeric operators (<, <=, >, >=) in",
    "  sub_exclusion_filters.  Use == TRUE or == FALSE instead.",
    sep_thin, "",
    sprintf(
      "  %-30s  %8s  %8s  %8s  %8s  %8s",
      "Variable", "n", "n_miss%", "n_true", "n_false", "pct_true"
    ),
    sprintf(
      "  %-30s  %8s  %8s  %8s  %8s  %8s",
      strrep("-", 30), strrep("-", 8), strrep("-", 8),
      strrep("-", 8), strrep("-", 8), strrep("-", 8)
    )
  )
  for (i in seq_len(nrow(bool_rows))) {
    r <- bool_rows[i, ]
    report_lines <- c(
      report_lines,
      sprintf(
        "  %-30s  %8d  %7.1f%%  %8d  %8d  %7.1f%%",
        r$variable,
        r$n_present,
        r$pct_missing,
        r$n_true,
        r$n_false,
        r$pct_true
      )
    )
  }
  report_lines <- c(report_lines, "")
}

# Categorical section
cat_rows <- profile_df[profile_df$type == "categorical", ]
if (nrow(cat_rows) > 0) {
  report_lines <- c(
    report_lines,
    sep_thin,
    "  CATEGORICAL VARIABLES",
    "  Top values are shown exactly as stored in the CSV (case-sensitive).",
    "  Copy the value string exactly when using == / in / not_in operators.",
    sep_thin, "",
    sprintf(
      "  %-30s  %8s  %8s  %8s  %s",
      "Variable", "n", "n_miss%", "n_dist", "Top values  (value : count)"
    ),
    sprintf(
      "  %-30s  %8s  %8s  %8s  %s",
      strrep("-", 30), strrep("-", 8), strrep("-", 8),
      strrep("-", 8), strrep("-", 28)
    )
  )
  for (i in seq_len(nrow(cat_rows))) {
    r <- cat_rows[i, ]
    top_parts <- character(0)
    for (pair in list(
      c(r$top1_value, r$top1_n),
      c(r$top2_value, r$top2_n),
      c(r$top3_value, r$top3_n)
    )) {
      if (!is.na(pair[1])) top_parts <- c(top_parts, sprintf("%s:%s", pair[1], pair[2]))
    }
    top_str <- if (length(top_parts) > 0) paste(top_parts, collapse = "  ") else "(no data)"
    nd_str <- if (!is.na(r$n_distinct)) as.character(r$n_distinct) else "NA"
    report_lines <- c(
      report_lines,
      sprintf(
        "  %-30s  %8d  %7.1f%%  %8s  %s",
        r$variable, r$n_present, r$pct_missing, nd_str, top_str
      )
    )
  }
  report_lines <- c(report_lines, "")
}

# Missing data summary
missing_rows <- profile_df[profile_df$pct_missing > 0, ]
if (nrow(missing_rows) > 0) {
  missing_rows <- missing_rows[order(-missing_rows$pct_missing), ]
  report_lines <- c(
    report_lines,
    sep_thin,
    "  MISSING DATA SUMMARY  (columns with > 0% missing, sorted descending)",
    sep_thin, "",
    sprintf("  %-30s  %8s  %8s", "Variable", "n_miss", "pct_miss"),
    sprintf("  %-30s  %8s  %8s", strrep("-", 30), strrep("-", 8), strrep("-", 8))
  )
  for (i in seq_len(nrow(missing_rows))) {
    r <- missing_rows[i, ]
    report_lines <- c(
      report_lines,
      sprintf("  %-30s  %8d  %7.1f%%", r$variable, r$n_missing, r$pct_missing)
    )
  }
  report_lines <- c(report_lines, "")
}

report_lines <- c(
  report_lines,
  sep_thick,
  sprintf("  End of variable profile report -- %s", timestamp),
  sep_thick
)

writeLines(report_lines, out_txt)
cat(sprintf("[output] Variable profile TXT : %s\n\n", basename(out_txt)))

# ==============================================================================
# DONE
# ==============================================================================

cat("================================================================\n")
cat("  Data profiler complete.\n")
cat(sprintf("  CSV : %s\n", normalizePath(out_csv, mustWork = FALSE)))
cat(sprintf("  TXT : %s\n", normalizePath(out_txt, mustWork = FALSE)))
cat("================================================================\n\n")

invisible(list(profile = profile_df, csv = out_csv, txt = out_txt))
