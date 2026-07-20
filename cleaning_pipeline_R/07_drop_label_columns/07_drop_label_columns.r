# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 07: Drop Redundant Label Columns
# =============================================================================
# PURPOSE:
#   After the forward-fill steps (Modules 05 & 06), the .label and
#   .labeldischarge columns are now redundant.  Any remaining information in
#   them has either been recovered into .value columns or is genuinely
#   missing.
#
#   Additionally, where both a bare column (e.g. "age") and a suffixed column
#   (e.g. "age.value") exist for the same variable, we keep whichever has more
#   non-null data; the other is dropped.
#
#   Strategy:
#     1. Drop all columns whose name contains "label".
#     2. Group the remaining columns by prefix (part before the first ".").
#     3. For each prefix group:
#        - If both a bare column and a .value column exist, keep the one with
#          more non-null entries (bare wins on a tie).
#        - Otherwise keep .value if present, else keep the bare column, else
#          keep the first column in the group.
#     4. Return the deduplicated DataFrame.
#
# INPUTS:
#   df              - data.frame after Module 06
#   report_filepath - (optional) path for a drop report
#
# OUTPUTS:
#   df  - data.frame without redundant label columns or prefix duplicates
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("07_drop_label_columns/07_drop_label_columns.r")
#   df <- drop_unwanted_columns(df)
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Drop Redundant Label Columns and Resolve Prefix Duplicates
#'
#' @param df              A data.frame.
#' @param report_filepath Optional path for a text drop report.
#' @return                Pruned data.frame.
drop_unwanted_columns <- function(df, report_filepath = NULL) {

  # Step 1: Drop all columns containing "label"
  keep_mask <- !grepl("label", names(df), fixed = TRUE)
  df        <- df[, keep_mask, drop = FALSE]

  # Step 2: Group columns by prefix
  col_names  <- names(df)
  get_prefix <- function(col) strsplit(col, ".", fixed = TRUE)[[1]][1]
  prefixes   <- vapply(col_names, get_prefix, character(1))

  unique_prefixes <- unique(prefixes)
  decisions       <- list()  # prefix -> list(kept, dropped)

  for (pfx in unique_prefixes) {
    cols_in_group   <- col_names[prefixes == pfx]
    bare_col        <- if (pfx %in% cols_in_group) pfx else NULL
    value_col       <- if (paste0(pfx, ".value") %in% cols_in_group)
                         paste0(pfx, ".value") else NULL

    if (!is.null(bare_col) && !is.null(value_col)) {
      # Compare non-null counts
      count_bare  <- sum(!is.na(df[[bare_col]]))
      count_value <- sum(!is.na(df[[value_col]]))
      chosen      <- if (count_bare >= count_value) bare_col else value_col
    } else if (!is.null(value_col)) {
      chosen <- value_col
    } else if (!is.null(bare_col)) {
      chosen <- bare_col
    } else {
      chosen <- cols_in_group[1]
    }

    dropped <- setdiff(cols_in_group, chosen)
    decisions[[pfx]] <- list(kept = chosen, dropped = dropped)
  }

  kept_cols <- vapply(decisions, function(x) x$kept, character(1))
  # Preserve original column order
  final_cols <- col_names[col_names %in% kept_cols]
  df         <- df[, final_cols, drop = FALSE]

  n_dropped <- length(col_names) - length(final_cols)
  log_info(sprintf(
    "drop_unwanted_columns: dropped %d redundant column(s). %d remain.",
    n_dropped, ncol(df)
  ))

  # Optional report
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c("Drop Columns Report", "===================", "")
      for (pfx in names(decisions)) {
        d <- decisions[[pfx]]
        if (length(d$dropped) > 0) {
          lines <- c(lines,
                     sprintf("Prefix '%s':", pfx),
                     sprintf("  Kept    : %s", d$kept),
                     sprintf("  Dropped : %s", paste(d$dropped, collapse = ", ")),
                     "")
        }
      }
      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write drop-columns report: %s", e$message)
    })
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "07_drop_columns_report.txt") else NULL

df <- drop_unwanted_columns(df, report_filepath = report_path)
log_info("Module 07 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
