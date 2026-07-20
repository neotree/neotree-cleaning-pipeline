# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 05: Forward Fill Common Placeholder Values
# =============================================================================
# PURPOSE:
#   For some variables that capture entries like "None", "Normal", or "Norm",
#   the .label column retains the recorded value while the corresponding
#   .value column remains empty.  This module recovers those values by copying
#   known placeholder strings from .label into .value when .value is NA.
#
# PLACEHOLDER STRINGS:
#   "None", "Normal", "Norm", "True", "False", "Yes", "No", "Y", "N"
#   (and their case variants)
#
# INPUTS:
#   df  - data.frame after Module 04
#
# OUTPUTS:
#   df  - data.frame with placeholder values recovered into .value columns
#
# REPORT:
#   reports/05_forward_fill_placeholder_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("05_forward_fill_placeholders/05_forward_fill_placeholders.r")
# =============================================================================

source("00_setup/00_setup.r")

PLACEHOLDER_VALUES <- c(
  "None", "Normal", "Norm",
  "none", "normal", "norm",
  "NONE", "NORMAL", "NORM",
  "True", "False", "TRUE", "FALSE",
  "Yes", "No", "YES", "NO", "Y", "N"
)

#' Forward Fill Placeholder Values from .label into .value
#'
#' @param df              A data.frame.
#' @param placeholders    Character vector of valid fill candidates.
#' @param report_filepath Optional path for a text report.
#' @return                Updated data.frame with recovered placeholder values.
forward_fill_placeholders <- function(df,
                                      placeholders    = PLACEHOLDER_VALUES,
                                      report_filepath = NULL) {

  fill_count_total <- 0L
  fill_log         <- character(0)
  col_names        <- names(df)

  process_pair <- function(vc, lc) {
    if (!lc %in% col_names) return(0L)
    mask   <- is.na(df[[vc]]) & !is.na(df[[lc]]) & (df[[lc]] %in% placeholders)
    n_fill <- sum(mask)
    if (n_fill > 0) {
      df[[vc]][mask] <<- df[[lc]][mask]
      fill_log <<- c(fill_log,
        sprintf("  %-45s <- %-45s : %d value(s) recovered", vc, lc, n_fill))
      log_info("  forward_fill_placeholders: %d values in '%s' recovered from '%s'.",
               n_fill, vc, lc)
    }
    return(n_fill)
  }

  # .value / .label pairs
  for (vc in col_names[grepl("\\.value$", col_names)]) {
    lc <- sub("\\.value$", ".label", vc)
    fill_count_total <- fill_count_total + process_pair(vc, lc)
  }

  # .valuedischarge / .labeldischarge pairs
  for (vc in col_names[grepl("\\.valuedischarge$", col_names)]) {
    lc <- sub("\\.valuedischarge$", ".labeldischarge", vc)
    fill_count_total <- fill_count_total + process_pair(vc, lc)
  }

  log_info("forward_fill_placeholders: %d total placeholder values recovered.",
           fill_count_total)

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 05 - Forward Fill Placeholder Values Report",
        "===================================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        "",
        sprintf("Placeholder tokens checked  : %d", length(placeholders)),
        sprintf("Total values recovered      : %d", fill_count_total),
        ""
      )
      if (length(fill_log) > 0) {
        lines <- c(lines, "=== Per-Column Fill Summary ===", fill_log)
      } else {
        lines <- c(lines, "No placeholder values needed recovery.")
      }
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 05 report: %s", e$message))
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "05_forward_fill_placeholder_report.txt") else NULL

df <- forward_fill_placeholders(df, report_filepath = report_path)
log_info("Module 05 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
