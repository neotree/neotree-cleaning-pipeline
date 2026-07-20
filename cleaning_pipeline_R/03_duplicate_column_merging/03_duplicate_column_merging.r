# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 03: Duplicate Column Merging
# =============================================================================
# PURPOSE:
#   Some columns appear multiple times in the data frame with the same variable
#   name (artefact of the Metabase export or data pipeline).  This module
#   retains the copy with the most non-missing values and fills its NAs from
#   the other duplicate(s), then drops the secondary copies.
#
# INPUTS:
#   df  - data.frame after Module 02
#
# OUTPUTS:
#   df  - data.frame with one column per unique name, maximising non-null data
#
# REPORT:
#   reports/03_duplicate_column_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("03_duplicate_column_merging/03_duplicate_column_merging.r")
# =============================================================================

source("00_setup/00_setup.r")

#' Merge Duplicate Columns
#'
#' @param df              A data.frame potentially containing duplicate column names.
#' @param report_filepath Optional path for a text report.
#' @return                A data.frame with one column per unique name.
merge_duplicate_columns <- function(df, report_filepath = NULL) {

  col_names   <- names(df)
  unique_cols <- unique(col_names)
  n_dups      <- length(col_names) - length(unique_cols)
  merge_log   <- character(0)

  if (n_dups == 0) {
    log_info("merge_duplicate_columns: no duplicate columns found.")
    if (!is.null(report_filepath) && nzchar(report_filepath)) {
      writeLines(c(
        "Module 03 - Duplicate Column Merging Report",
        "============================================",
        sprintf("Run timestamp    : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country          : %s", toupper(cfg$country)),
        sprintf("Dataset          : %s", cfg$dataset),
        "",
        "No duplicate columns found."
      ), report_filepath)
    }
    return(df)
  }

  log_info("merge_duplicate_columns: %d duplicate column(s) detected.", n_dups)

  merged_list <- vector("list", length(unique_cols))
  names(merged_list) <- unique_cols

  for (col in unique_cols) {
    positions <- which(col_names == col)

    if (length(positions) == 1) {
      merged_list[[col]] <- df[[positions]]
    } else {
      series_list   <- lapply(positions, function(i) df[[i]])
      non_na_counts <- vapply(series_list, function(s) sum(!is.na(s)), integer(1))
      best_idx      <- which.max(non_na_counts)
      primary       <- series_list[[best_idx]]

      for (i in seq_along(series_list)) {
        if (i != best_idx) {
          na_mask           <- is.na(primary)
          primary[na_mask]  <- series_list[[i]][na_mask]
        }
      }

      merged_list[[col]] <- primary
      merge_log <- c(merge_log,
        sprintf("  %-45s : %d copies merged (best had %d non-null)",
                col, length(positions), max(non_na_counts)))
      log_info("  Merged %d copies of '%s'; retained column with %d non-null values.",
               length(positions), col, max(non_na_counts))
    }
  }

  result_df           <- as.data.frame(merged_list, stringsAsFactors = FALSE, check.names = FALSE)
  rownames(result_df) <- rownames(df)

  log_info("merge_duplicate_columns complete: %d cols -> %d cols.",
           ncol(df), ncol(result_df))

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 03 - Duplicate Column Merging Report",
        "============================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        "",
        sprintf("Columns before merging      : %d", ncol(df)),
        sprintf("Duplicate column instances  : %d", n_dups),
        sprintf("Columns after merging       : %d", ncol(result_df)),
        ""
      )
      if (length(merge_log) > 0) {
        lines <- c(lines,
                   "=== Merged Column Groups ===",
                   merge_log)
      }
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 03 report: %s", e$message))
  }

  return(result_df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "03_duplicate_column_report.txt") else NULL

df <- merge_duplicate_columns(df, report_filepath = report_path)
log_info("Module 03 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
