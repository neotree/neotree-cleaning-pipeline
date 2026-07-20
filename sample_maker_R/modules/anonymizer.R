################################################################################
# Neotree Sample Maker -- Anonymizer Module
# FILE:    modules/anonymizer.R
# PURPOSE: Strip direct identifiers and quasi-identifiers from any pipeline
#          output CSV (master_joined, master_joined_extended, or subsample files),
#          producing a de-identified dataset safe for sharing or archiving.
#
# WHAT IS REMOVED / REPLACED
#   Direct identifiers   -> removed entirely
#   Exact datetimes      -> replaced with year-month strings (YYYY-MM)
#   Pipeline date column -> removed (redundant after datetime conversion)
#   User-specified extras -> removed (configured in run_anonymizer.R)
#
# FUNCTIONS EXPORTED
#   anonymize_dataset(df, cfg)
#     -> returns a named list: $df, $removed, $converted, $added, $n_rows,
#       $n_cols_before, $n_cols_after
#
#   write_anonymizer_outputs(results_list, cfg, out_dir)
#     -> writes one anonymized CSV per input file plus one combined report
#     -> returns a named list of output paths
################################################################################

# ==============================================================================
# Constants -- edit these lists to add or remove variables globally
# ==============================================================================

# Direct identifiers: always removed from every output file.
# These allow a record to be linked back to a specific patient.
ANON_REMOVE_ALWAYS <- c(
  "uid",          # patient identifier
  "uniquekey",    # Neotree record key
  "match_key"     # uid + facility composite key (derived identifier)
)

# Pipeline-internal date column: always removed.
# adm_date_parsed is a POSIXct copy of datetimeadmission added by the pipeline;
# it is made redundant by the adm_yearmonth column created during anonymization.
ANON_REMOVE_PIPELINE_COLS <- c(
  "adm_date_parsed"
)

# Datetime columns to convert to year-month.
# Each entry: original column name -> new anonymized column name.
# Exact dates combined with facility are quasi-identifying; year-month
# preserves temporal analysis while removing day-level precision.
ANON_DATETIME_CONVERT <- list(
  datetimeadmission  = "adm_yearmonth",   # "2024-03-15 08:30:00" -> "2024-03"
  datetimedischarge  = "dis_yearmonth"    # "2024-03-22 14:00:00" -> "2024-03"
)

# ==============================================================================
# 1. anonymize_dataset()
# ==============================================================================

anonymize_dataset <- function(df, cfg) {

  n_cols_before <- ncol(df)
  removed       <- character(0)
  converted     <- character(0)
  added         <- character(0)

  # --- Step 1: Remove direct identifiers ------------------------------------
  cols_to_remove <- intersect(ANON_REMOVE_ALWAYS, names(df))
  if (length(cols_to_remove) > 0) {
    df      <- df[, !names(df) %in% cols_to_remove, drop = FALSE]
    removed <- c(removed, cols_to_remove)
  }

  # --- Step 2: Remove pipeline-internal columns -----------------------------
  cols_to_remove <- intersect(ANON_REMOVE_PIPELINE_COLS, names(df))
  if (length(cols_to_remove) > 0) {
    df      <- df[, !names(df) %in% cols_to_remove, drop = FALSE]
    removed <- c(removed, cols_to_remove)
  }

  # --- Step 3: Remove user-specified extra columns --------------------------
  if (!is.null(cfg$additional_remove) && length(cfg$additional_remove) > 0) {
    cols_to_remove <- intersect(cfg$additional_remove, names(df))
    not_found      <- setdiff(cfg$additional_remove, names(df))
    if (length(cols_to_remove) > 0) {
      df      <- df[, !names(df) %in% cols_to_remove, drop = FALSE]
      removed <- c(removed, cols_to_remove)
    }
    if (length(not_found) > 0) {
      warning(sprintf(
        "[anonymizer] additional_remove columns not found (ignored): %s",
        paste(not_found, collapse = ", ")
      ))
    }
  }

  # --- Step 4: Convert datetime columns to year-month (optional) ------------
  if (isTRUE(cfg$convert_datetimes)) {
    for (orig_col in names(ANON_DATETIME_CONVERT)) {
      new_col <- ANON_DATETIME_CONVERT[[orig_col]]
      if (!orig_col %in% names(df)) next

      raw <- as.character(df[[orig_col]])

      # Try full datetime parse first, fall back to date-only
      parsed <- as.POSIXct(raw, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
      na_idx <- is.na(parsed)
      if (any(na_idx)) {
        parsed[na_idx] <- as.POSIXct(
          substr(raw[na_idx], 1, 10), format = "%Y-%m-%d", tz = "UTC"
        )
      }

      ym <- rep(NA_character_, nrow(df))
      ym[!is.na(parsed)] <- format(parsed[!is.na(parsed)], "%Y-%m")

      # Insert the new year-month column immediately after the original
      pos        <- which(names(df) == orig_col)
      df_left    <- if (pos > 1) df[, 1:(pos - 1), drop = FALSE] else data.frame()
      df_right   <- df[, (pos + 1):ncol(df), drop = FALSE]
      new_col_df <- data.frame(x = ym, stringsAsFactors = FALSE)
      names(new_col_df) <- new_col
      df <- cbind(df_left, new_col_df, df_right)

      converted <- c(converted, sprintf("%s -> %s", orig_col, new_col))
      removed   <- c(removed, orig_col)
    }
  }

  # --- Step 5: Add sequential anonymous row ID (optional) -------------------
  if (isTRUE(cfg$add_anon_id)) {
    df    <- cbind(anon_id = seq_len(nrow(df)), df)
    added <- c(added, "anon_id")
  }

  list(
    df            = df,
    removed       = removed,
    converted     = converted,
    added         = added,
    n_rows        = nrow(df),
    n_cols_before = n_cols_before,
    n_cols_after  = ncol(df)
  )
}

# ==============================================================================
# 2. write_anonymizer_outputs()
# ==============================================================================

write_anonymizer_outputs <- function(results_list, cfg, out_dir) {

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  output_paths <- list()

  for (label in names(results_list)) {
    res      <- results_list[[label]]
    out_path <- file.path(out_dir, paste0(label, "_anon.csv"))
    write.csv(res$df, out_path, row.names = FALSE)
    output_paths[[label]] <- out_path
    cat(sprintf("[anonymizer] Written: %s  (%d rows x %d cols)\n",
                basename(out_path), res$n_rows, res$n_cols_after))
  }

  # Write combined report
  report_path <- file.path(out_dir, "anonymization_report.txt")
  report_lines <- .build_anon_report(results_list, cfg, output_paths)
  writeLines(report_lines, report_path)
  cat(sprintf("[anonymizer] Report : %s\n", basename(report_path)))

  output_paths$report <- report_path
  invisible(output_paths)
}

# ==============================================================================
# Internal: report builder
# ==============================================================================

.build_anon_report <- function(results_list, cfg, output_paths) {

  ts  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  sep <- strrep("=", 72)
  sec <- strrep("-", 72)

  lines <- c(
    sep,
    "  Neotree Sample Maker -- Anonymization Report",
    sep,
    "",
    "1. METADATA",
    sec,
    sprintf("  Run date/time  : %s", ts),
    sprintf("  Script         : run_anonymizer.R"),
    sprintf("  Add anon_id        : %s", ifelse(isTRUE(cfg$add_anon_id), "YES", "NO")),
    sprintf("  Convert datetimes  : %s", ifelse(isTRUE(cfg$convert_datetimes), "YES", "NO")),
    ""
  )

  # 2. Variables removed
  first_result <- results_list[[1]]
  lines <- c(lines,
    "2. VARIABLES REMOVED / CONVERTED",
    sec,
    "  Direct identifiers (always removed):",
    paste0("    ", ANON_REMOVE_ALWAYS),
    "",
    "  Pipeline-internal columns (always removed):",
    paste0("    ", ANON_REMOVE_PIPELINE_COLS),
    ""
  )
  if (isTRUE(cfg$convert_datetimes)) {
    lines <- c(lines, "  Datetime columns converted to year-month:")
    for (conv in names(ANON_DATETIME_CONVERT)) {
      lines <- c(lines, sprintf("    %-30s -> %s",
                                conv, ANON_DATETIME_CONVERT[[conv]]))
    }
  } else {
    lines <- c(lines,
      "  Datetime columns  : KEPT AS-IS (convert_datetimes = FALSE)",
      "    datetimeadmission and datetimedischarge are unchanged."
    )
  }
  if (!is.null(cfg$additional_remove) && length(cfg$additional_remove) > 0) {
    found     <- intersect(cfg$additional_remove, names(results_list[[1]]$df))
    not_found <- setdiff(cfg$additional_remove,
                         c(names(results_list[[1]]$df), first_result$removed))
    lines <- c(lines, "",
      "  User-specified additional columns removed:",
      paste0("    ", ifelse(length(found) > 0, found, "(none found)"))
    )
    if (length(not_found) > 0) {
      lines <- c(lines,
        "  User-specified columns NOT FOUND in data (ignored):",
        paste0("    ", not_found)
      )
    }
  } else {
    lines <- c(lines, "",
      "  User-specified additional columns  : (none configured)")
  }
  lines <- c(lines, "")

  # 3. Per-file summary
  lines <- c(lines,
    "3. FILES PROCESSED",
    sec
  )
  for (label in names(results_list)) {
    res <- results_list[[label]]
    lines <- c(lines,
      sprintf("  %s", label),
      sprintf("    Rows            : %d", res$n_rows),
      sprintf("    Columns before  : %d", res$n_cols_before),
      sprintf("    Columns after   : %d", res$n_cols_after),
      sprintf("    Columns removed : %d  (%s)", length(res$removed),
              paste(res$removed, collapse = ", ")),
      sprintf("    anon_id added   : %s",
              ifelse("anon_id" %in% res$added, "YES", "NO")),
      ""
    )
  }

  # 4. Output files
  lines <- c(lines,
    "4. OUTPUT FILES",
    sec
  )
  for (label in names(output_paths)) {
    path <- output_paths[[label]]
    size <- tryCatch(
      sprintf("%.1f KB", file.size(path) / 1024),
      error = function(e) "?"
    )
    lines <- c(lines, sprintf("  %-45s  %s", basename(path), size))
  }
  lines <- c(lines, "",
    sep,
    "  End of anonymization report",
    sep
  )
  lines
}
