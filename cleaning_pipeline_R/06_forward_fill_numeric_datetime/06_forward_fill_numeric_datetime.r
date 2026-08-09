# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 06: Forward Fill Numeric and Datetime Values
# =============================================================================
# PURPOSE:
#   For numeric and datetime variables, the .label column sometimes retains
#   the recorded value while the paired .value column is empty.  This is the
#   same data pipeline artefact as in Module 05, but specifically for
#   continuous/temporal data rather than categorical placeholders.
#
#   Strategy:
#     1. For each (.value, .label) pair, where .value is NA and .label is
#        non-null, attempt to coerce the label to numeric.
#     2. If numeric coercion succeeds, fill .value with the numeric result.
#     3. For remaining NA .values, attempt datetime coercion; if successful,
#        fill .value with the datetime string.
#     4. Drop the .label column after filling (it is now redundant).
#
# INPUTS:
#   df              - data.frame after Module 05
#   report_filepath - (optional) path for a fill report
#
# OUTPUTS:
#   df  - data.frame with numeric/datetime values recovered and .label columns
#         removed
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("06_forward_fill_numeric_datetime/06_forward_fill_numeric_datetime.r")
#   df <- forward_fill_numeric_datetime(df)
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Forward Fill Numeric and Datetime Values from .label into .value
#'
#' @param df              A data.frame.
#' @param report_filepath Optional path for a text report.
#' @return                Data.frame with filled values and .label columns dropped.
forward_fill_numeric_datetime <- function(df, report_filepath = NULL) {

  col_names <- names(df)
  fill_log  <- list()   # column -> count of fills

  # Build pairs: value_col -> label_col
  pairs <- list()
  for (vc in col_names[grepl("\\.value$", col_names)]) {
    lc <- sub("\\.value$", ".label", vc)
    if (lc %in% col_names) pairs[[vc]] <- lc
  }
  for (vc in col_names[grepl("\\.valuedischarge$", col_names)]) {
    lc <- sub("\\.valuedischarge$", ".labeldischarge", vc)
    if (lc %in% col_names) pairs[[vc]] <- lc
  }

  cols_to_drop <- character(0)

  for (vc in names(pairs)) {
    lc   <- pairs[[vc]]
    mask <- is.na(df[[vc]]) & !is.na(df[[lc]])

    if (!any(mask)) {
      cols_to_drop <- c(cols_to_drop, lc)
      next
    }

    label_vals <- as.character(df[[lc]][mask])
    n_filled   <- 0L

    # --- Attempt numeric fill ---
    numeric_vals <- suppressWarnings(as.numeric(label_vals))
    num_ok       <- !is.na(numeric_vals)
    if (any(num_ok)) {
      target_rows <- which(mask)[num_ok]
      df[[vc]][target_rows] <- as.character(numeric_vals[num_ok])
      n_filled <- n_filled + sum(num_ok)
    }

    # --- Attempt datetime fill for remaining NAs ---
    mask2 <- is.na(df[[vc]]) & !is.na(df[[lc]])
    if (any(mask2)) {
      label_vals2 <- as.character(df[[lc]][mask2])
      dt_vals     <- suppressWarnings(lubridate::parse_date_time(
        label_vals2,
        orders = c("ymd HMS", "ymd HM", "ymd", "dmy HMS", "dmy", "mdy")
      ))
      dt_ok <- !is.na(dt_vals)
      if (any(dt_ok)) {
        target_rows2 <- which(mask2)[dt_ok]
        df[[vc]][target_rows2] <- as.character(dt_vals[dt_ok])
        n_filled <- n_filled + sum(dt_ok)
      }
    }

    fill_log[[vc]] <- n_filled
    cols_to_drop   <- c(cols_to_drop, lc)

    if (n_filled > 0) {
      log_info(
        "  forward_fill_numeric_datetime: filled %d values in '%s' from '%s'.",
        n_filled, vc, lc
      )
    }
  }

  # Drop label columns
  cols_to_drop <- intersect(unique(cols_to_drop), names(df))
  if (length(cols_to_drop) > 0) {
    df <- df[, !names(df) %in% cols_to_drop, drop = FALSE]
    log_info(
      "  Dropped %d .label/.labeldischarge column(s).", length(cols_to_drop)
    )
  }

  total_fills <- sum(unlist(fill_log))
  log_info(
    "forward_fill_numeric_datetime: %d total values recovered.", total_fills
  )

  # Optional report
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      active <- fill_log[vapply(fill_log, function(x) x > 0, logical(1))]
      lines  <- c("Forward Fill - Numeric / Datetime Report",
                  "=========================================",
                  sprintf("Total columns with fills : %d", length(active)),
                  sprintf("Total values filled      : %d", total_fills),
                  "", "Details:")
      for (col in names(active)) {
        lines <- c(lines, sprintf("  %s : %d values filled", col, active[[col]]))
      }
      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write forward-fill report: %s", e$message)
    })
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "06_forward_fill_numeric_datetime_report.txt") else NULL

df <- forward_fill_numeric_datetime(df, report_filepath = report_path)
log_info("Module 06 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
