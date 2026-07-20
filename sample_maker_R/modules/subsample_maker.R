################################################################################
# Neotree Sample Maker -- Module 02: Subsample Maker
# FILE:    modules/subsample_maker.R
# PURPOSE: Create analysis-ready subsamples from master_joined and
#          master_joined_extended by (1) filtering on admission date and/or
#          facility, (2) optionally excluding records by variable values, and
#          (3) optionally selecting a subset of columns.
#
# DESIGN NOTES
#
#   Input datasets
#     master_joined          -- all selected admissions; discharge data where
#                              a direct uid+facility match was found; NA elsewhere
#     master_joined_extended -- same as master_joined but with probabilistically
#                              matched discharge data filling some of the NAs
#
#   Why filter on ADMISSION date, not discharge date
#     The subsample date window selects babies by when they were admitted.
#     Discharges can (and should) fall outside the window -- e.g. a baby admitted
#     on the last day of the window may be discharged weeks later.  All discharge
#     data already joined to each admission is retained in full.
#
#   Date filter behaviour
#     SIMPLE mode  : one date range applied to all (or a subset of) facilities.
#     ADVANCED mode: per-facility date ranges (mirrors the main-pipeline logic).
#     Both modes filter on datetimeadmission.
#     Records with unparseable/missing datetimeadmission are EXCLUDED and logged.
#
#   Exclusion filters (sub_exclusion_filters)
#     Each entry is a list(variable, operator, value) that identifies rows to
#     REMOVE.  Applied after the date/facility filter and before column selection.
#     Operators: "<", "<=", ">", ">=", "==", "!=", "in", "not_in".
#     Numeric coercion is applied automatically when the value is numeric.
#     Rows where the filter variable is NA are kept (not excluded).
#     Applied to both master_joined and master_joined_extended.
#     When any filters are set, "_excl" is appended to the output label.
#
#   Column selection
#     When sub_variables is set to a character vector, only those columns are
#     kept -- plus a mandatory set of administrative/pipeline columns that are
#     always retained regardless:
#       uid, facility, uniquekey, datetimeadmission, match_key,
#       match_type, prob_match_similarity
#     Columns that don't exist in the dataset (e.g. wrong name supplied) are
#     reported as a warning; the rest are still applied.
#     Column names must match exactly as they appear in the master file.
#
# FUNCTIONS EXPORTED
#   run_subsample_maker(master_joined, master_joined_extended, cfg)
#     -> list(
#         subsample_joined,          subsample_joined_extended,
#         subsample_joined_matched_only,
#         subsample_joined_extended_matched_only,
#         meta_joined,               meta_extended,
#         excl_joined,               excl_extended,
#         sub_filter_desc,           sub_label,
#         col_info
#       )
#
#   write_subsample_outputs(sub_result, cfg, prefix, out_dir, na_coded = NULL)
#     Writes four CSV subsamples + text report.  When na_coded is a named list
#     (joined, extended, joined_matched, extended_matched), four additional
#     *_na_coded.csv files are written alongside the standard outputs.
#     Returns a named list of all output file paths.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.2  (2026-05)
################################################################################

# Columns always kept regardless of sub_variables setting
SUBSAMPLE_ALWAYS_KEEP <- c(
  "uid", "facility", "uniquekey", "datetimeadmission",
  "match_key", "adm_date_parsed",
  "match_type", "prob_match_similarity"
)

# ==============================================================================
# run_subsample_maker()
# ==============================================================================
run_subsample_maker <- function(master_joined, master_joined_extended, cfg) {

  cat("[subsample] Starting subsample maker...\n\n")

  # ---------------------------------------------------------------------------
  # 1. Parse admission dates (re-parse from datetimeadmission for safety,
  #    in case adm_date_parsed was dropped or lost type on CSV round-trip)
  # ---------------------------------------------------------------------------
  master_joined          <- .ensure_parsed_date(master_joined,          "master_joined")
  master_joined_extended <- .ensure_parsed_date(master_joined_extended, "master_joined_extended")

  # ---------------------------------------------------------------------------
  # 2. Report date ranges in the input master datasets
  # ---------------------------------------------------------------------------
  dr_mj  <- range(master_joined$adm_date_parsed,          na.rm = TRUE)
  dr_mje <- range(master_joined_extended$adm_date_parsed,  na.rm = TRUE)

  cat(sprintf("[subsample] master_joined           : %d rows | adm dates %s - %s\n",
              nrow(master_joined),
              format(dr_mj[1], "%Y-%m-%d"), format(dr_mj[2], "%Y-%m-%d")))
  cat(sprintf("[subsample] master_joined_extended  : %d rows | adm dates %s - %s\n\n",
              nrow(master_joined_extended),
              format(dr_mje[1], "%Y-%m-%d"), format(dr_mje[2], "%Y-%m-%d")))

  # ---------------------------------------------------------------------------
  # 3. Build filter description and label
  # ---------------------------------------------------------------------------
  filter_info <- .build_sub_filter_info(cfg)

  cat(sprintf("[subsample] Subsample filter:\n"))
  for (line in filter_info$desc) cat(sprintf("  %s\n", line))
  cat("\n")

  # ---------------------------------------------------------------------------
  # 4. Apply date/facility filter to both master datasets
  # ---------------------------------------------------------------------------
  cat("[subsample] Filtering master_joined...\n")
  meta_joined  <- .apply_sub_filter(master_joined, cfg, filter_info, "master_joined")

  cat("[subsample] Filtering master_joined_extended...\n")
  meta_extended <- .apply_sub_filter(master_joined_extended, cfg, filter_info, "master_joined_extended")

  sub_joined   <- meta_joined$df
  sub_extended <- meta_extended$df

  # ---------------------------------------------------------------------------
  # 4b. Apply variable exclusion filters
  #     Applied after date/facility filter, before column selection.
  #     Rows where the filter variable is NA are kept (conservative).
  # ---------------------------------------------------------------------------
  cat("[subsample] Applying exclusion filters...\n")
  excl_joined   <- .apply_exclusion_filters(sub_joined,   cfg, "master_joined")
  excl_extended <- .apply_exclusion_filters(sub_extended, cfg, "master_joined_extended")
  sub_joined    <- excl_joined$df
  sub_extended  <- excl_extended$df

  if (excl_joined$n_total_excluded > 0 || excl_extended$n_total_excluded > 0) {
    cat(sprintf("[subsample]   master_joined excluded          : %d rows\n",
                excl_joined$n_total_excluded))
    cat(sprintf("[subsample]   master_joined_extended excluded : %d rows\n",
                excl_extended$n_total_excluded))
  } else {
    cat("[subsample]   No exclusion filters active.\n")
  }
  cat("\n")

  # ---------------------------------------------------------------------------
  # 5. Column selection
  # ---------------------------------------------------------------------------
  cat("[subsample] Applying column selection...\n")
  col_info <- .select_columns(sub_joined, sub_extended, cfg)

  sub_joined   <- col_info$df_joined
  sub_extended <- col_info$df_extended

  cat(sprintf("[subsample]   Columns kept   : %d / %d\n",
              col_info$n_kept, col_info$n_total))
  if (length(col_info$not_found) > 0) {
    cat(sprintf("[subsample]   WARNING: %d requested column(s) not found and skipped:\n", length(col_info$not_found)))
    for (c in col_info$not_found) cat(sprintf("    %s\n", c))
  }
  cat("\n")

  # ---------------------------------------------------------------------------
  # 6. Always derive matched-only datasets (mirrors Pipeline 1 naming)
  #
  #   subsample_joined_matched_only          = subsample_joined filtered to
  #     direct_match rows only.  Mirrors joined_admissions_discharges.
  #
  #   subsample_joined_extended_matched_only = subsample_joined_extended
  #     filtered to direct_match + prob_match rows.  Mirrors
  #     joined_admissions_discharges_extended.
  #
  # Both are always produced alongside the other two outputs.
  # ---------------------------------------------------------------------------
  if ("match_type" %in% names(sub_joined)) {
    sub_joined_matched <- sub_joined[
      !is.na(sub_joined$match_type) & sub_joined$match_type == "direct_match",
    ]
  } else {
    sub_joined_matched <- sub_joined
  }

  if ("match_type" %in% names(sub_extended)) {
    sub_extended_matched <- sub_extended[
      !is.na(sub_extended$match_type) & sub_extended$match_type != "unmatched",
    ]
  } else {
    sub_extended_matched <- sub_extended
  }

  # ---------------------------------------------------------------------------
  # 7. Final counts
  # ---------------------------------------------------------------------------
  cat(sprintf("[subsample] subsample_joined                         : %d rows x %d columns\n",
              nrow(sub_joined),          ncol(sub_joined)))
  cat(sprintf("[subsample] subsample_joined_extended                : %d rows x %d columns\n",
              nrow(sub_extended),        ncol(sub_extended)))
  cat(sprintf("[subsample] subsample_joined_matched_only            : %d rows x %d columns\n",
              nrow(sub_joined_matched),  ncol(sub_joined_matched)))
  cat(sprintf("[subsample] subsample_joined_extended_matched_only   : %d rows x %d columns\n\n",
              nrow(sub_extended_matched), ncol(sub_extended_matched)))

  list(
    subsample_joined                        = sub_joined,
    subsample_joined_extended               = sub_extended,
    subsample_joined_matched_only           = sub_joined_matched,
    subsample_joined_extended_matched_only  = sub_extended_matched,
    meta_joined                             = meta_joined,
    meta_extended                           = meta_extended,
    excl_joined                             = excl_joined,
    excl_extended                           = excl_extended,
    sub_filter_desc                         = filter_info$desc,
    sub_label                               = filter_info$label,
    col_info                                = col_info
  )
}

# ==============================================================================
# Internal: ensure adm_date_parsed is a POSIXct column
# ==============================================================================
.ensure_parsed_date <- function(df, label) {
  if ("adm_date_parsed" %in% names(df) &&
      inherits(df$adm_date_parsed, c("POSIXct", "POSIXt"))) {
    return(df)  # already good
  }

  # Re-parse from datetimeadmission
  if (!"datetimeadmission" %in% names(df)) {
    stop(sprintf("[subsample] Column 'datetimeadmission' not found in %s.", label))
  }
  cat(sprintf("[subsample] Re-parsing datetimeadmission in %s...\n", label))

  parsed <- as.POSIXct(df$datetimeadmission, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
  na_mask <- is.na(parsed)
  if (any(na_mask)) {
    parsed[na_mask] <- as.POSIXct(
      substr(as.character(df$datetimeadmission[na_mask]), 1, 10),
      format = "%Y-%m-%d", tz = "UTC"
    )
  }
  df$adm_date_parsed <- parsed
  df
}

# ==============================================================================
# Internal: build filter description and label string
# ==============================================================================
.build_sub_filter_info <- function(cfg) {

  if (isTRUE(cfg$sub_use_advanced_mode)) {
    ranges <- cfg$sub_facility_date_ranges
    if (length(ranges) == 0) {
      stop("[subsample] sub_use_advanced_mode is TRUE but sub_facility_date_ranges is empty.")
    }
    facs  <- sapply(ranges, `[`, 1)
    start <- min(sapply(ranges, `[`, 2))
    end   <- max(sapply(ranges, `[`, 3))
    label <- paste0(
      gsub("-", "", start), "_to_", gsub("-", "", end),
      "_", paste(facs, collapse = "_")
    )
    desc <- c(
      "Mode         : Advanced (per-facility date ranges)",
      sapply(ranges, function(r) sprintf("  %-14s %s  to  %s", r[1], r[2], r[3]))
    )
  } else {
    start <- cfg$sub_start_date
    end   <- cfg$sub_end_date
    facs  <- cfg$sub_facility_filter

    # Label
    if (!is.null(start) && !is.null(end)) {
      date_part <- paste0(gsub("-", "", start), "_to_", gsub("-", "", end))
    } else if (!is.null(end)) {
      date_part <- paste0("to_", gsub("-", "", end))
    } else if (!is.null(start)) {
      date_part <- paste0("from_", gsub("-", "", start))
    } else {
      date_part <- NULL
    }
    fac_part <- if (!is.null(facs)) paste(facs, collapse = "_") else NULL
    parts    <- c(date_part, fac_part)
    label    <- if (length(parts) > 0) paste(parts, collapse = "_") else "ALL"

    desc <- c(
      "Mode         : Simple",
      sprintf("sub_start_date : %s", ifelse(is.null(start), "(none -- no lower bound)", start)),
      sprintf("sub_end_date   : %s", ifelse(is.null(end),   "(none -- no upper bound)", end)),
      sprintf("Facilities     : %s", ifelse(is.null(facs),  "All", paste(facs, collapse = ", ")))
    )
  }

  # Append exclusion-filter tag if filters are set
  excl <- cfg$sub_exclusion_filters
  if (!is.null(excl) && length(excl) > 0) {
    label <- paste0(label, "_excl")
    excl_lines <- vapply(seq_along(excl), function(i) {
      f       <- excl[[i]]
      val_str <- if (length(f$value) > 3)
                   paste0(paste(head(f$value, 3), collapse = ", "), ", ...")
                 else paste(f$value, collapse = ", ")
      sprintf("  Excl [%d]       : %s %s %s", i, f$variable, f$operator, val_str)
    }, character(1))
    desc <- c(desc, "Exclusion filters :", excl_lines)
  } else {
    desc <- c(desc, "Exclusion filters  : None")
  }

  # Append variable-selection tag if columns are restricted
  vars <- cfg$sub_variables
  if (!is.null(vars) && length(vars) > 0) {
    label <- paste0(label, "_", length(vars), "vars")
    desc  <- c(desc, sprintf("Variables          : %d specified + mandatory set", length(vars)))
  } else {
    desc <- c(desc, "Variables          : All columns retained")
  }

  list(desc = desc, label = label)
}

# ==============================================================================
# Internal: apply date/facility filter to one data frame
# ==============================================================================
.apply_sub_filter <- function(df, cfg, filter_info, label) {

  n_total   <- nrow(df)
  n_missing_dates <- sum(is.na(df$adm_date_parsed))

  if (isTRUE(cfg$sub_use_advanced_mode)) {
    # --- ADVANCED mode ---
    chunks <- lapply(cfg$sub_facility_date_ranges, function(r) {
      if (length(r) != 3) stop(sprintf(
        "[subsample] sub_facility_date_ranges entry must have 3 elements: c('FAC','start','end')"
      ))
      fac      <- r[1]
      start_dt <- as.POSIXct(r[2], format = "%Y-%m-%d", tz = "UTC")
      end_dt   <- as.POSIXct(paste(r[3], "23:59:59"), format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
      df[
        !is.na(df$adm_date_parsed) &
        df$facility == fac &
        df$adm_date_parsed >= start_dt &
        df$adm_date_parsed <= end_dt,
      ]
    })
    filtered <- do.call(rbind, chunks)
    # Safety dedup: each admission (uid+facility) at most once
    if (nrow(filtered) > 0) {
      filtered <- filtered[
        !duplicated(paste(filtered$uid, filtered$facility)),
      ]
    }

  } else {
    # --- SIMPLE mode ---
    mask <- rep(TRUE, nrow(df))

    if (!is.null(cfg$sub_start_date)) {
      start_dt <- as.POSIXct(cfg$sub_start_date, format = "%Y-%m-%d", tz = "UTC")
      mask <- mask & !is.na(df$adm_date_parsed) & df$adm_date_parsed >= start_dt
    }
    if (!is.null(cfg$sub_end_date)) {
      end_dt <- as.POSIXct(
        paste(cfg$sub_end_date, "23:59:59"), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"
      )
      mask <- mask & !is.na(df$adm_date_parsed) & df$adm_date_parsed <= end_dt
    }
    if (!is.null(cfg$sub_facility_filter)) {
      if (!"facility" %in% names(df)) {
        stop("[subsample] Column 'facility' not found but sub_facility_filter is set.")
      }
      mask <- mask & df$facility %in% cfg$sub_facility_filter
    }
    filtered <- df[mask, ]
  }

  n_kept     <- nrow(filtered)
  n_excluded <- n_total - n_kept - n_missing_dates

  cat(sprintf("[subsample]   %s : %d / %d rows kept  (%d missing dates, %d outside window)\n",
              label, n_kept, n_total, n_missing_dates, n_excluded))

  if (n_kept == 0) {
    dr <- range(df$adm_date_parsed, na.rm = TRUE)
    stop(sprintf(
      "[subsample] No records remain after subsample filter in %s.\n  Available dates: %s to %s\n  Check sub_start_date / sub_end_date in config.R.",
      label,
      format(dr[1], "%Y-%m-%d"),
      format(dr[2], "%Y-%m-%d")
    ))
  }

  # Compute date range and match_type breakdown of the kept subset
  kept_dr   <- range(filtered$adm_date_parsed, na.rm = TRUE)
  type_tab  <- if ("match_type" %in% names(filtered)) table(filtered$match_type) else NULL

  list(
    df              = filtered,
    n_total         = n_total,
    n_kept          = n_kept,
    n_missing_dates = n_missing_dates,
    n_excluded      = n_excluded,
    date_min        = kept_dr[1],
    date_max        = kept_dr[2],
    type_tab        = type_tab
  )
}

# ==============================================================================
# Internal: apply variable exclusion filters to one data frame
#
# cfg$sub_exclusion_filters is a list of entries, each of the form:
#   list(variable = "colname", operator = "<", value = 24)
#
# Supported operators: "<", "<=", ">", ">=", "==", "!=", "in", "not_in"
# Rows where the filter variable is NA are KEPT (conservative default).
# For "<", "<=", ">", ">=": numeric coercion is applied when value is numeric.
# For "in" / "not_in": value may be a vector (character or numeric).
# Returns: list(df, excl_info, n_total_excluded)
# ==============================================================================
.apply_exclusion_filters <- function(df, cfg, label) {

  filters <- cfg$sub_exclusion_filters
  if (is.null(filters) || length(filters) == 0) {
    return(list(df = df, excl_info = list(), n_total_excluded = 0L))
  }

  excl_info <- vector("list", length(filters))

  for (i in seq_along(filters)) {
    f   <- filters[[i]]
    var <- f$variable
    op  <- f$operator
    val <- f$value

    if (!var %in% names(df)) {
      cat(sprintf("[subsample]   Excl [%d]: column '%s' not found in %s -- skipped\n",
                  i, var, label))
      excl_info[[i]] <- list(variable = var, operator = op, value = val,
                              n_excluded = 0L, skipped = TRUE,
                              reason = "column not found")
      next
    }

    col <- df[[var]]

    # Coerce to numeric when the comparison value is numeric (handles CSV
    # round-trip where numeric columns may be stored as character strings)
    if (is.numeric(val)) {
      col_cmp <- suppressWarnings(as.numeric(col))
      val_cmp <- val
    } else {
      col_cmp <- as.character(col)
      val_cmp <- as.character(val)
    }

    # Build exclusion mask: TRUE = exclude this row
    # NA in the column -> keep the row (not excluded)
    excl_mask <- switch(op,
      "<"      = !is.na(col_cmp) & col_cmp <  val_cmp,
      "<="     = !is.na(col_cmp) & col_cmp <= val_cmp,
      ">"      = !is.na(col_cmp) & col_cmp >  val_cmp,
      ">="     = !is.na(col_cmp) & col_cmp >= val_cmp,
      "=="     = !is.na(col_cmp) & col_cmp == val_cmp,
      "!="     = !is.na(col_cmp) & col_cmp != val_cmp,
      "in"     = !is.na(col_cmp) & col_cmp %in% val_cmp,
      "not_in" = !is.na(col_cmp) & !(col_cmp %in% val_cmp),
      stop(sprintf(
        "[subsample] Unknown operator '%s' in sub_exclusion_filters[[%d]].\n  Supported: <, <=, >, >=, ==, !=, in, not_in",
        op, i
      ))
    )

    n_excl <- sum(excl_mask)
    val_str <- if (length(val) > 3)
                 paste0(paste(head(val, 3), collapse = ", "), ", ...")
               else paste(val, collapse = ", ")
    cat(sprintf("[subsample]   Excl [%d]: %s %s %s  ->  %d row(s) removed from %s\n",
                i, var, op, val_str, n_excl, label))

    df <- df[!excl_mask, ]

    excl_info[[i]] <- list(variable   = var,
                            operator   = op,
                            value      = val,
                            n_excluded = n_excl,
                            skipped    = FALSE)
  }

  total <- sum(vapply(excl_info,
    function(x) if (isTRUE(x$skipped)) 0L else as.integer(x$n_excluded),
    integer(1)))

  list(df = df, excl_info = excl_info, n_total_excluded = total)
}

# ==============================================================================
# Internal: select columns from both data frames
# ==============================================================================
.select_columns <- function(df_joined, df_extended, cfg) {

  vars <- cfg$sub_variables
  all_cols <- names(df_joined)
  n_total  <- length(all_cols)

  if (is.null(vars) || length(vars) == 0) {
    # No restriction -- keep everything
    return(list(
      df_joined   = df_joined,
      df_extended = df_extended,
      n_total     = n_total,
      n_kept      = n_total,
      cols_kept   = all_cols,
      cols_mandatory = intersect(SUBSAMPLE_ALWAYS_KEEP, all_cols),
      cols_user   = character(0),
      not_found   = character(0),
      selection_mode = "all"
    ))
  }

  # Resolve each requested variable to an actual column name
  resolved   <- character(0)
  not_found  <- character(0)

  for (v in vars) {
    if (v %in% all_cols) {
      resolved <- c(resolved, v)
    } else {
      not_found <- c(not_found, v)
    }
  }

  # Mandatory columns always included (take what exists in df_joined)
  mandatory <- intersect(SUBSAMPLE_ALWAYS_KEEP, all_cols)

  # Combined unique set, in original column order
  keep_set  <- unique(c(mandatory, resolved))
  keep_cols <- all_cols[all_cols %in% keep_set]

  list(
    df_joined      = df_joined[,   keep_cols, drop = FALSE],
    df_extended    = df_extended[, intersect(keep_cols, names(df_extended)), drop = FALSE],
    n_total        = n_total,
    n_kept         = length(keep_cols),
    cols_kept      = keep_cols,
    cols_mandatory = mandatory,
    cols_user      = resolved,
    not_found      = not_found,
    selection_mode = "selected"
  )
}

# ==============================================================================
# write_subsample_outputs()
# ==============================================================================
# Writes CSVs and the full text report.  Called from run_subsample_maker.R.
#
# Parameters:
#   sub_result  -- list returned by run_subsample_maker()
#   cfg         -- the SUBSAMPLE_CONFIG list from run_subsample_maker.R
#   prefix      -- file-name prefix derived from the input file (e.g. "ZIM_db")
#   out_dir     -- output directory path (already created by caller)
#   na_coded    -- optional named list with elements joined, extended,
#                  joined_matched, extended_matched: the same rows as the
#                  standard outputs but from the *_na_coded.csv source files.
#                  When non-NULL, four additional *_na_coded.csv files are
#                  written alongside the standard outputs.
#
# Returns: named list of output file paths.
# ==============================================================================
write_subsample_outputs <- function(sub_result, cfg, prefix, out_dir,
                                    na_coded = NULL) {

  label <- sub_result$sub_label

  paths <- list(
    sub_joined            = file.path(out_dir, sprintf("%s_subsample_master_%s.csv",                          prefix, label)),
    sub_extended          = file.path(out_dir, sprintf("%s_subsample_master_extended_%s.csv",                 prefix, label)),
    sub_joined_matched    = file.path(out_dir, sprintf("%s_subsample_master_matched_only_%s.csv",             prefix, label)),
    sub_extended_matched  = file.path(out_dir, sprintf("%s_subsample_master_extended_matched_only_%s.csv",    prefix, label)),
    report                = file.path(out_dir, sprintf("%s_subsample_report_%s.txt",                          prefix, label))
  )

  # --- Blank-NA CSVs ---
  write.csv(sub_result$subsample_joined,                       paths$sub_joined,           row.names = FALSE, na = "")
  write.csv(sub_result$subsample_joined_extended,              paths$sub_extended,          row.names = FALSE, na = "")
  write.csv(sub_result$subsample_joined_matched_only,          paths$sub_joined_matched,    row.names = FALSE, na = "")
  write.csv(sub_result$subsample_joined_extended_matched_only, paths$sub_extended_matched,  row.names = FALSE, na = "")

  cat(sprintf("[output] subsample_master                          : %d rows x %d cols -> %s\n",
              nrow(sub_result$subsample_joined),
              ncol(sub_result$subsample_joined),
              basename(paths$sub_joined)))
  cat(sprintf("[output] subsample_master_extended                 : %d rows x %d cols -> %s\n",
              nrow(sub_result$subsample_joined_extended),
              ncol(sub_result$subsample_joined_extended),
              basename(paths$sub_extended)))
  cat(sprintf("[output] subsample_master_matched_only             : %d rows x %d cols -> %s\n",
              nrow(sub_result$subsample_joined_matched_only),
              ncol(sub_result$subsample_joined_matched_only),
              basename(paths$sub_joined_matched)))
  cat(sprintf("[output] subsample_master_extended_matched_only    : %d rows x %d cols -> %s\n",
              nrow(sub_result$subsample_joined_extended_matched_only),
              ncol(sub_result$subsample_joined_extended_matched_only),
              basename(paths$sub_extended_matched)))

  # --- NA-coded CSVs (optional paired output) ---
  if (!is.null(na_coded)) {
    nc_paths <- list(
      sub_joined           = sub("\\.csv$", "_na_coded.csv", paths$sub_joined),
      sub_extended         = sub("\\.csv$", "_na_coded.csv", paths$sub_extended),
      sub_joined_matched   = sub("\\.csv$", "_na_coded.csv", paths$sub_joined_matched),
      sub_extended_matched = sub("\\.csv$", "_na_coded.csv", paths$sub_extended_matched)
    )
    write.csv(na_coded$joined,           nc_paths$sub_joined,           row.names = FALSE)
    write.csv(na_coded$extended,         nc_paths$sub_extended,         row.names = FALSE)
    write.csv(na_coded$joined_matched,   nc_paths$sub_joined_matched,   row.names = FALSE)
    write.csv(na_coded$extended_matched, nc_paths$sub_extended_matched, row.names = FALSE)

    cat(sprintf("[output] subsample_master_na_coded                 : %d rows -> %s\n",
                nrow(na_coded$joined),           basename(nc_paths$sub_joined)))
    cat(sprintf("[output] subsample_master_extended_na_coded        : %d rows -> %s\n",
                nrow(na_coded$extended),         basename(nc_paths$sub_extended)))
    cat(sprintf("[output] subsample_master_matched_only_na_coded    : %d rows -> %s\n",
                nrow(na_coded$joined_matched),   basename(nc_paths$sub_joined_matched)))
    cat(sprintf("[output] subsample_master_extended_mo_na_coded     : %d rows -> %s\n",
                nrow(na_coded$extended_matched), basename(nc_paths$sub_extended_matched)))

    paths <- c(paths, nc_paths)
  }

  # --- Text report ---
  report_lines <- .build_subsample_report(sub_result, cfg, prefix, label, paths,
                                          has_na_coded = !is.null(na_coded))
  writeLines(report_lines, paths$report)
  cat(sprintf("[output] subsample_report           : %s\n\n", basename(paths$report)))

  paths
}

# ==============================================================================
# Internal: build the full subsample text report
# ==============================================================================
.build_subsample_report <- function(sr, cfg, prefix, label, paths,
                                    has_na_coded = FALSE) {

  mj  <- sr$meta_joined
  mje <- sr$meta_extended
  ej  <- sr$excl_joined
  eje <- sr$excl_extended
  ci  <- sr$col_info
  sj  <- sr$subsample_joined
  se  <- sr$subsample_joined_extended

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  sep_thick <- strrep("=", 70)
  sep_thin  <- strrep("-", 70)

  # [1] Metadata
  s1 <- c(
    sep_thick,
    "  Neotree Sample Maker -- Subsample Report",
    sep_thick, "",
    sprintf("  Generated    : %s", timestamp),
    sprintf("  File prefix  : %s", prefix),
    sprintf("  Subsample tag: %s", label), ""
  )

  # [2] Input files
  s2 <- c(
    sep_thin, "  [2]  INPUT FILES", sep_thin, "",
    sprintf("  master_joined file          : %s",
            basename(cfg$master_joined_file)),
    sprintf("  master_joined_extended file : %s",
            basename(cfg$master_joined_extended_file)),
    sprintf("  master_joined rows          : %d", mj$n_total),
    sprintf("  master_joined_extended rows : %d", mje$n_total), ""
  )

  # [3] Subsample filter
  s3 <- c(
    sep_thin, "  [3]  SUBSAMPLE FILTER  (applied to datetimeadmission)", sep_thin, "",
    paste0("  ", sr$sub_filter_desc), ""
  )

  # [4] Filter results
  fmt_tab <- function(tab, total) {
    if (is.null(tab) || length(tab) == 0) return("    (match_type column not found)")
    vapply(seq_along(tab), function(i)
      sprintf("    %-22s  %6d  %5.1f%%",
              names(tab)[i], tab[i], 100 * tab[i] / total),
      character(1))
  }

  s4 <- c(
    sep_thin, "  [4]  FILTER RESULTS", sep_thin, "",

    "  master_joined:",
    sprintf("    Input rows               : %d", mj$n_total),
    sprintf("    Missing datetimeadmission: %d", mj$n_missing_dates),
    sprintf("    Outside date window      : %d", mj$n_excluded),
    sprintf("    Rows kept in subsample   : %d  (%.1f%%)",
            mj$n_kept, 100 * mj$n_kept / mj$n_total),
    sprintf("    Admission date range     : %s  to  %s",
            format(mj$date_min, "%Y-%m-%d"), format(mj$date_max, "%Y-%m-%d")),
    "    Breakdown by match_type:",
    fmt_tab(mj$type_tab, mj$n_kept),
    "",

    "  master_joined_extended:",
    sprintf("    Input rows               : %d", mje$n_total),
    sprintf("    Missing datetimeadmission: %d", mje$n_missing_dates),
    sprintf("    Outside date window      : %d", mje$n_excluded),
    sprintf("    Rows kept in subsample   : %d  (%.1f%%)",
            mje$n_kept, 100 * mje$n_kept / mje$n_total),
    sprintf("    Admission date range     : %s  to  %s",
            format(mje$date_min, "%Y-%m-%d"), format(mje$date_max, "%Y-%m-%d")),
    "    Breakdown by match_type:",
    fmt_tab(mje$type_tab, mje$n_kept),
    ""
  )

  # [4b] Exclusion filters
  .fmt_excl_section <- function(excl, dataset_label) {
    if (is.null(excl) || length(excl$excl_info) == 0) {
      return(sprintf("  %s : No exclusion filters applied.", dataset_label))
    }
    lines <- sprintf("  %s:", dataset_label)
    for (x in excl$excl_info) {
      val_str <- if (length(x$value) > 3)
                   paste0(paste(head(x$value, 3), collapse = ", "), ", ...")
                 else paste(x$value, collapse = ", ")
      if (isTRUE(x$skipped)) {
        lines <- c(lines, sprintf("    [%s %s %s]  SKIPPED (%s)",
                                  x$variable, x$operator, val_str, x$reason))
      } else {
        lines <- c(lines, sprintf("    [%s %s %s]  ->  %d row(s) removed",
                                  x$variable, x$operator, val_str, x$n_excluded))
      }
    }
    lines <- c(lines,
      sprintf("    Total rows removed : %d", excl$n_total_excluded),
      sprintf("    Rows after excl    : %d",
              if (!is.null(excl$df)) nrow(excl$df) else NA)
    )
    lines
  }

  has_excl <- !is.null(ej) && length(ej$excl_info) > 0

  if (has_excl) {
    s4b_body <- c(
      .fmt_excl_section(ej,  "master_joined"),
      "",
      .fmt_excl_section(eje, "master_joined_extended")
    )
  } else {
    s4b_body <- "  No exclusion filters configured (sub_exclusion_filters is empty)."
  }

  s4b <- c(sep_thin, "  [4b] EXCLUSION FILTERS", sep_thin, "",
           s4b_body, "")

  # [5] Column selection
  if (ci$selection_mode == "all") {
    col_lines <- c(
      "  Mode    : All columns retained (sub_variables = NULL)",
      sprintf("  Columns : %d", ci$n_total)
    )
  } else {
    col_lines <- c(
      "  Mode       : Selected columns only",
      sprintf("  Total cols in master : %d", ci$n_total),
      sprintf("  Mandatory (always)   : %d  (%s)",
              length(ci$cols_mandatory),
              paste(ci$cols_mandatory, collapse = ", ")),
      sprintf("  User-specified kept  : %d", length(ci$cols_user)),
      sprintf("  Total kept           : %d", ci$n_kept),
      sprintf("  Dropped              : %d", ci$n_total - ci$n_kept)
    )
    if (length(ci$not_found) > 0) {
      col_lines <- c(col_lines,
        sprintf("  WARNING -- %d requested column(s) not found:", length(ci$not_found)),
        paste0("    ", ci$not_found)
      )
    }
  }

  s5 <- c(sep_thin, "  [5]  COLUMN SELECTION", sep_thin, "", col_lines, "")

  # [6] Facility breakdown of subsample_joined
  fac_lines <- .sub_fac_breakdown(sj, "subsample_joined")
  fac_ext   <- .sub_fac_breakdown(se, "subsample_joined_extended")

  s6 <- c(
    sep_thin, "  [6]  FACILITY BREAKDOWN", sep_thin, "",
    fac_lines, "", fac_ext, ""
  )

  # [6b] Matched-only outputs (always produced)
  sjm <- sr$subsample_joined_matched_only
  sem <- sr$subsample_joined_extended_matched_only

  n_sjm        <- if (!is.null(sjm)) nrow(sjm) else 0L
  n_sem        <- if (!is.null(sem)) nrow(sem) else 0L
  n_sem_direct <- if (!is.null(sem) && "match_type" %in% names(sem))
                    sum(sem$match_type == "direct_match", na.rm = TRUE) else 0L
  n_sem_prob   <- if (!is.null(sem) && "match_type" %in% names(sem))
                    sum(sem$match_type == "prob_match",   na.rm = TRUE) else 0L

  s6b <- c(
    sep_thin, "  [6b] MATCHED-ONLY OUTPUTS", sep_thin, "",
    "  Two matched-only files are derived and always produced:",
    "",
    "  subsample_joined_matched_only",
    "    Derived from subsample_joined (direct uid+facility matches only).",
    sprintf("    Rows : %d", n_sjm),
    "",
    "  subsample_joined_extended_matched_only",
    "    Derived from subsample_joined_extended (unmatched rows removed).",
    "    Contains direct_match and prob_match rows; every row has discharge data.",
    sprintf("    subsample_joined_extended rows : %d", nrow(se)),
    sprintf("    Unmatched rows removed         : %d", nrow(se) - n_sem),
    sprintf("    Rows kept                      : %d", n_sem),
    sprintf("      direct_match                 : %d  (%.1f%%)",
            n_sem_direct, if (n_sem > 0) 100 * n_sem_direct / n_sem else 0),
    sprintf("      prob_match                   : %d  (%.1f%%)",
            n_sem_prob,   if (n_sem > 0) 100 * n_sem_prob   / n_sem else 0),
    ""
  )

  # [7] Outcome distributions
  out_col <- if ("neotreeoutcome" %in% names(sj)) "neotreeoutcome" else
             if ("neotreeoutcome_dis" %in% names(sj)) "neotreeoutcome_dis" else NULL

  if (!is.null(out_col)) {
    # subsample_joined: only rows with a discharge (direct_match)
    sj_matched <- sj[!is.na(sj$match_type) & sj$match_type != "unmatched", ]
    ot_sj <- .outcome_dist(sj_matched, out_col, "subsample_joined (matched rows only)")

    se_matched <- se[!is.na(se$match_type) & se$match_type != "unmatched", ]
    ot_se <- .outcome_dist(se_matched, out_col, "subsample_joined_extended (matched rows)")

    s7 <- c(sep_thin, "  [7]  OUTCOME DISTRIBUTIONS", sep_thin, "",
            ot_sj, "", ot_se, "")
  } else {
    s7 <- c(sep_thin, "  [7]  OUTCOME DISTRIBUTIONS", sep_thin, "",
            "  (neotreeoutcome column not found in subsample -- check sub_variables)", "")
  }

  # [8] Output files
  s8_lines <- c(
    sep_thin, "  [8]  OUTPUT FILES", sep_thin, "",
    sprintf("  subsample_master                         : %s", basename(paths$sub_joined)),
    sprintf("  subsample_master_extended                : %s", basename(paths$sub_extended)),
    sprintf("  subsample_master_matched_only            : %s", basename(paths$sub_joined_matched)),
    sprintf("  subsample_master_extended_matched_only   : %s", basename(paths$sub_extended_matched))
  )
  if (isTRUE(has_na_coded)) {
    s8_lines <- c(s8_lines,
      "",
      "  NA-coded variants (sentinel values -7/-9 for NA):",
      sprintf("  subsample_master_na_coded                : %s",
              basename(sub("\\.csv$", "_na_coded.csv", paths$sub_joined))),
      sprintf("  subsample_master_extended_na_coded       : %s",
              basename(sub("\\.csv$", "_na_coded.csv", paths$sub_extended))),
      sprintf("  subsample_master_matched_only_na_coded   : %s",
              basename(sub("\\.csv$", "_na_coded.csv", paths$sub_joined_matched))),
      sprintf("  subsample_master_ext_mo_na_coded         : %s",
              basename(sub("\\.csv$", "_na_coded.csv", paths$sub_extended_matched)))
    )
  }
  s8 <- c(s8_lines,
    sprintf("  This report                              : %s", basename(paths$report)),
    ""
  )

  footer <- c(
    sep_thick,
    sprintf("  End of subsample report -- %s", timestamp),
    sep_thick
  )

  c(s1, s2, s3, s4, s4b, s5, s6, s6b, s7, s8, footer)
}

# Facility breakdown table helper for subsample report
.sub_fac_breakdown <- function(df, label) {
  if (!"facility" %in% names(df) || nrow(df) == 0) {
    return(sprintf("  %s : (empty or no facility column)", label))
  }
  fac_tab <- sort(table(df$facility), decreasing = TRUE)
  total   <- nrow(df)
  c(
    sprintf("  %s  (n = %d):", label, total),
    vapply(seq_along(fac_tab), function(i)
      sprintf("    %-22s  %6d  %5.1f%%",
              names(fac_tab)[i], fac_tab[i], 100 * fac_tab[i] / total),
      character(1))
  )
}

# Outcome distribution helper for subsample report
.outcome_dist <- function(df, col, label) {
  if (!col %in% names(df) || nrow(df) == 0) {
    return(sprintf("  %s : (no data)", label))
  }
  ot    <- sort(table(df[[col]], useNA = "ifany"), decreasing = TRUE)
  total <- nrow(df)
  c(
    sprintf("  %s  (n = %d):", label, total),
    sprintf("  %-35s  %6s  %6s", "Outcome", "N", "%"),
    sprintf("  %-35s  %6s  %6s", strrep("-", 35), strrep("-", 6), strrep("-", 6)),
    vapply(seq_along(ot), function(i) {
      lbl <- names(ot)[i]
      if (is.na(lbl)) lbl <- "(NA / missing)"
      sprintf("  %-35s  %6d  %5.1f%%", lbl, ot[i], 100 * ot[i] / total)
    }, character(1))
  )
}
