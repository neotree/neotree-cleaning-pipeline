#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Researcher Data Package Generator
# FILE:    run_subsample_user_dict.R
# PURPOSE: For each subsample CSV produced by run_subsample_maker.R, combines:
#            (a) the Neotree user data dictionary  (variable descriptions, types,
#                value codes, NA codes, availability across datasets)
#            (b) a statistical data profile        (n present, missing rate, and
#                descriptive statistics for each variable)
#          into a single Excel workbook per run.
#
#          The workbook is designed to accompany a shared data package, giving
#          recipients both the variable reference they need to interpret the data
#          and a quick-look data quality summary.
#
# OUTPUTS
#   {prefix}_data_package_{label}.xlsx
#       One workbook per run, containing one sheet per dataset type found:
#         About        -- study metadata, run date, subsample information
#         Admissions   -- combined dict + profile for admissions subsample
#         Discharges   -- combined dict + profile for discharges subsample
#         Neolab       -- combined dict + profile for neolab subsample
#         Maternal     -- combined dict + profile for maternal subsample
#         NA Codes     -- legend of standard Neotree missing-value codes
#
# REQUIREMENTS
#   openxlsx package  (install.packages("openxlsx"))
#
# USAGE
#   From RStudio:
#     Set DICT_CONFIG in the block below, then click Source.
#   From terminal:
#     Rscript run_subsample_user_dict.R
#     Rscript run_subsample_user_dict.R my_study_config.R
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-05)
################################################################################

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Researcher Data Package Generator\n")
cat("================================================================\n\n")

# ==============================================================================
# CONFIGURATION
# Edit this block, then Source / Rscript.
# To supply an external config file: source("my_config.R") before sourcing this
# script, or pass the config path as a command-line argument.
# ==============================================================================

if (!exists("DICT_CONFIG")) {

DICT_CONFIG <- list(

  # --------------------------------------------------------------------------
  # STUDY METADATA  (appears on the About sheet)
  # --------------------------------------------------------------------------
  study_name = "Neotree Data Package",

  # --------------------------------------------------------------------------
  # COUNTRY
  # "zim" for Zimbabwe, "mwi" for Malawi.
  # NULL = auto-detect from the subsample file prefix (ZIM_ → zim, MWI_ → mwi).
  # --------------------------------------------------------------------------
  country = NULL,

  # --------------------------------------------------------------------------
  # SUBSAMPLE CSV SOURCE  (choose one of the two modes below)
  #
  # AUTO MODE: set subsample_dir to the directory containing subsample CSVs.
  #   All files matching *_subsample_*.csv in that directory are discovered.
  #   Leave subsample_files as an empty list.
  #
  #   Example:
  #     subsample_dir   = "outputs/zim_db"
  #     subsample_files = list()
  #
  # MANUAL MODE: provide a named list mapping dataset type to file path.
  #   Leave subsample_dir as NULL.
  #
  #   Example:
  #     subsample_dir   = NULL
  #     subsample_files = list(
  #       admissions = "outputs/zim_db/ZIM_db_subsample_admissions_20240101_to_20260228.csv",
  #       neolab     = "outputs/zim_db/ZIM_db_subsample_neolab_20240101_to_20260228.csv"
  #     )
  # --------------------------------------------------------------------------
  subsample_dir   = NULL,
  subsample_files = list(),

  # --------------------------------------------------------------------------
  # USER DICTIONARY FOLDER
  # Relative (from this script's directory) or absolute path.
  # Must contain:  neotree_user_dict_zim.xlsx
  #                neotree_user_dict_mwi.xlsx
  # --------------------------------------------------------------------------
  user_dict_dir = "user_dictionaries",

  # --------------------------------------------------------------------------
  # OUTPUT DIRECTORY
  # NULL -> written to the same directory as the subsample CSV(s).
  #         If using auto-discovery, written to subsample_dir.
  # --------------------------------------------------------------------------
  output_dir = NULL,

  # --------------------------------------------------------------------------
  # NUMERIC DETECTION  (same defaults as run_data_profiler.R)
  # A column is treated as numeric when:
  #   >= numeric_threshold of non-missing values are coercible to number, AND
  #   the number of distinct values is <= max_numeric_distinct.
  # --------------------------------------------------------------------------
  numeric_threshold    = 0.90,
  max_numeric_distinct = 500

)

} # end if (!exists("DICT_CONFIG"))

# ==============================================================================
# COMMAND-LINE CONFIG OVERRIDE
# ==============================================================================

local({
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && nchar(trimws(args[1])) > 0) {
    cfg_path <- trimws(args[1])
    if (!file.exists(cfg_path)) {
      script_args <- commandArgs(trailingOnly = FALSE)
      script_flag <- grep("--file=", script_args, value = TRUE)
      if (length(script_flag) > 0) {
        script_dir <- dirname(normalizePath(sub("--file=", "", script_flag), mustWork = FALSE))
        cfg_path2  <- file.path(script_dir, cfg_path)
        if (file.exists(cfg_path2)) cfg_path <- cfg_path2
      }
    }
    if (!file.exists(cfg_path)) {
      stop(sprintf("Config file not found: %s", args[1]))
    }
    rm(list = "DICT_CONFIG", envir = globalenv())
    source(cfg_path, local = FALSE)
    cat(sprintf("Config loaded from: %s\n\n", cfg_path))
  }
})

cfg <- DICT_CONFIG

# ==============================================================================
# RESOLVE SCRIPT DIRECTORY
# ==============================================================================

.script_dir <- tryCatch({
  script_args <- commandArgs(trailingOnly = FALSE)
  script_flag <- grep("--file=", script_args, value = TRUE)
  if (length(script_flag) > 0) {
    dirname(normalizePath(sub("--file=", "", script_flag), mustWork = FALSE))
  } else {
    normalizePath(".")
  }
}, error = function(e) normalizePath("."))

.resolve_path <- function(p) {
  if (is.null(p) || !nchar(trimws(p))) return(NULL)
  if (grepl("^(/|~|[A-Za-z]:)", p)) return(normalizePath(p, mustWork = FALSE))
  normalizePath(file.path(.script_dir, p), mustWork = FALSE)
}

# ==============================================================================
# CHECK OPENXLSX
# ==============================================================================

if (!requireNamespace("openxlsx", quietly = TRUE)) {
  stop(
    "Package 'openxlsx' is required but not installed.\n",
    "Install it with:  install.packages(\"openxlsx\")\n"
  )
}
library(openxlsx)

# ==============================================================================
# HELPERS: DATA PROFILER
# (Logic extracted from run_data_profiler.R, wrapped as a function.)
# ==============================================================================

.mode_val <- function(x) {
  x <- x[!is.na(x) & nchar(as.character(x)) > 0]
  if (length(x) == 0) return(NA_character_)
  tab <- sort(table(x), decreasing = TRUE)
  names(tab)[1]
}

profile_dataframe <- function(df,
                               numeric_threshold    = 0.90,
                               max_numeric_distinct = 500) {
  n_rows <- nrow(df)
  profile_rows <- lapply(names(df), function(col_name) {
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
      ((n_present == 0) || (n_numeric / n_present >= numeric_threshold))
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
      row$n_true  <- n_true_val
      row$n_false <- n_false_val
      row$pct_true <- if (n_present > 0) round(100 * n_true_val / n_present, 1) else NA_real_
      row$sample_values <- samp_raw; row$n_distinct <- n_distinct
      row$min <- NA_real_; row$max <- NA_real_; row$mean <- NA_real_
      row$median <- NA_real_; row$sd <- NA_real_; row$mode_value <- NA_character_
      row$top1_value <- NA_character_; row$top1_n <- NA_integer_
      row$top2_value <- NA_character_; row$top2_n <- NA_integer_
      row$top3_value <- NA_character_; row$top3_n <- NA_integer_
    } else if (is_numeric) {
      num_vals <- num_coerce[!is.na(num_coerce)]
      row$min   <- if (length(num_vals) > 0) round(min(num_vals),    4) else NA_real_
      row$max   <- if (length(num_vals) > 0) round(max(num_vals),    4) else NA_real_
      row$mean  <- if (length(num_vals) > 0) round(mean(num_vals),   4) else NA_real_
      row$median <- if (length(num_vals) > 0) round(median(num_vals), 4) else NA_real_
      row$sd    <- if (length(num_vals) > 1) round(sd(num_vals),     4) else NA_real_
      row$mode_value <- .mode_val(as.character(present_vals))
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
  prof <- do.call(rbind, profile_rows)
  col_order <- c(
    "variable", "type", "n_total", "n_present", "n_missing", "pct_missing",
    "min", "max", "mean", "median", "sd", "mode_value", "n_distinct", "sample_values",
    "n_true", "n_false", "pct_true",
    "top1_value", "top1_n", "top2_value", "top2_n", "top3_value", "top3_n"
  )
  prof[, col_order]
}

# ==============================================================================
# HELPERS: STATISTICS STRING BUILDER
# Converts a profile row into a compact human-readable string for the Excel.
# ==============================================================================

build_stats_string <- function(row) {
  if (is.na(row$type)) return("")
  if (row$type == "numeric") {
    parts <- character(0)
    if (!is.na(row$min) && !is.na(row$max)) {
      mn_s <- if (row$min == floor(row$min)) as.character(as.integer(row$min)) else sprintf("%.2f", row$min)
      mx_s <- if (row$max == floor(row$max)) as.character(as.integer(row$max)) else sprintf("%.2f", row$max)
      parts <- c(parts, sprintf("Range: %s–%s", mn_s, mx_s))
    }
    if (!is.na(row$mean))   parts <- c(parts, sprintf("Mean: %.1f", row$mean))
    if (!is.na(row$median)) parts <- c(parts, sprintf("Median: %.1f", row$median))
    if (length(parts) == 0) return("")
    paste(parts, collapse = "  |  ")
  } else if (row$type == "boolean") {
    parts <- character(0)
    if (!is.na(row$n_true))  parts <- c(parts, sprintf("TRUE: %s", format(row$n_true, big.mark = ",")))
    if (!is.na(row$n_false)) parts <- c(parts, sprintf("FALSE: %s", format(row$n_false, big.mark = ",")))
    if (!is.na(row$pct_true)) parts[length(parts)] <- sprintf(
      "%s  (%.1f%% TRUE)", paste(parts, collapse = "  |  "), row$pct_true
    )
    if (length(parts) == 0) return("") else return(parts[length(parts)])
  } else {
    # categorical
    pairs <- character(0)
    for (i in 1:3) {
      v <- row[[paste0("top", i, "_value")]]
      n <- row[[paste0("top", i, "_n")]]
      if (!is.na(v) && !is.na(n)) pairs <- c(pairs, sprintf("%s: %s", v, format(n, big.mark = ",")))
    }
    if (length(pairs) == 0) return("")
    nd <- if (!is.na(row$n_distinct)) row$n_distinct else 0
    extra <- nd - length(pairs)
    suffix <- if (extra > 0) sprintf("  [+%d more]", extra) else ""
    paste0(paste(pairs, collapse = "  |  "), suffix)
  }
}

# ==============================================================================
# HELPERS: USER DICTIONARY READER
# Reads one sheet from the user dictionary Excel file.
# Returns a data.frame with columns:
#   is_section    -- TRUE for section-header rows
#   Description, VariableName, Type, ValuesCodes, NACodes, AvailableAlsoIn
# ==============================================================================

DICT_COLS <- c("Description", "Variable Name", "Type", "Values / Codes",
               "NA Codes", "Available also in")

read_user_dict_sheet <- function(wb_path, sheet_name) {
  # Check sheet exists
  available <- tryCatch(getSheetNames(wb_path), error = function(e) character(0))
  if (!sheet_name %in% available) {
    return(NULL)
  }
  raw <- tryCatch(
    read.xlsx(wb_path, sheet = sheet_name, colNames = TRUE,
              na.strings = c("", "NA"), skipEmptyRows = FALSE),
    error = function(e) {
      cat(sprintf("    [WARN] Could not read sheet '%s': %s\n", sheet_name, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(raw) || nrow(raw) == 0) return(NULL)

  # Rename columns to canonical names
  # The dict columns from 00d_build_user_dictionary.r:
  #   "Description", "Variable Name", "Type", "Values / Codes",
  #   "NA Codes", "Available also in"
  # openxlsx may replace spaces with dots in names when reading
  fix_colname <- function(nm) {
    gsub("\\.", " ", nm)
  }
  names(raw) <- fix_colname(names(raw))

  # Handle column name variants
  col_map <- list(
    VariableName   = c("Variable Name", "Variable.Name", "VariableName"),
    Description    = c("Description"),
    Type           = c("Type"),
    ValuesCodes    = c("Values / Codes", "Values...Codes", "Values/Codes", "ValuesCodes"),
    NACodes        = c("NA Codes", "NA.Codes", "NACodes"),
    AvailableAlsoIn = c("Available also in", "Available.also.in", "AvailableAlsoIn")
  )
  find_col <- function(candidates) {
    for (cand in candidates) if (cand %in% names(raw)) return(cand)
    NULL
  }
  varname_col      <- find_col(col_map$VariableName)
  desc_col         <- find_col(col_map$Description)
  type_col         <- find_col(col_map$Type)
  values_col       <- find_col(col_map$ValuesCodes)
  nacodes_col      <- find_col(col_map$NACodes)
  availablein_col  <- find_col(col_map$AvailableAlsoIn)

  safe_col <- function(df, cname) {
    if (is.null(cname) || !cname %in% names(df)) rep(NA_character_, nrow(df))
    else as.character(df[[cname]])
  }

  out <- data.frame(
    is_section    = FALSE,
    Description   = safe_col(raw, desc_col),
    VariableName  = safe_col(raw, varname_col),
    Type          = safe_col(raw, type_col),
    ValuesCodes   = safe_col(raw, values_col),
    NACodes       = safe_col(raw, nacodes_col),
    AvailableAlsoIn = safe_col(raw, availablein_col),
    stringsAsFactors = FALSE
  )

  # Section rows: VariableName is NA/empty, Description is non-empty
  is_sec <- (is.na(out$VariableName) | nchar(trimws(out$VariableName)) == 0) &
            (!is.na(out$Description)  & nchar(trimws(out$Description))  > 0)
  out$is_section <- is_sec

  # Remove completely empty rows (both Description and VariableName empty)
  is_empty <- (is.na(out$Description) | nchar(trimws(out$Description)) == 0) &
              (is.na(out$VariableName) | nchar(trimws(out$VariableName)) == 0)
  out <- out[!is_empty, , drop = FALSE]
  rownames(out) <- NULL
  out
}

# ==============================================================================
# KNOWN PIPELINE / SYSTEM VARIABLES
# Variables generated by the sample maker pipeline that may appear in subsamples
# but are not in the user dictionary (which covers Neotree app variables only).
# ==============================================================================

PIPELINE_VAR_DESCRIPTIONS <- list(
  uid                    = "Unique patient identifier assigned by the Neotree application",
  uniquekey              = "Unique record key combining uid and session information",
  facility               = "Facility code where the patient was registered",
  match_key              = "The key used to link this admission to its discharge record",
  match_type             = "How the admission-discharge link was made: 'exact' (uid matched), 'probabilistic' (fuzzy match on demographics), or 'unmatched' (no discharge found)",
  prob_match_similarity  = "Probabilistic match confidence score (0–100); present only for probabilistic matches. A score of 100 means all demographic fields agreed exactly.",
  adm_date_parsed        = "Admission date extracted and standardised from datetimeadmission (Date format: YYYY-MM-DD)",
  datetimeadmission      = "Date and time of admission as recorded in the Neotree app (datetime string)"
)

# ==============================================================================
# HELPERS: BUILD COMBINED SHEET DATA
# Merges dict rows with profile statistics.
# Returns a list of rows ready for writeData(), each marked as:
#   row_type = "section" | "variable" | "unmatched_section" | "unmatched_variable"
# ==============================================================================

build_combined_sheet <- function(df_data, dict_sheet, profile,
                                 type_label) {
  # dict_sheet: output of read_user_dict_sheet (may be NULL)
  # profile:    output of profile_dataframe
  # df_data:    the raw subsample data.frame (for column order)

  data_cols <- names(df_data)

  # Build two profile lookups keyed by lower-case variable name:
  #   prof_lkp         -- exact case-insensitive match
  #   prof_lkp_stripped -- underscores removed from both sides, for matching
  #                        dictionary snake_case names (e.g. "birth_weight")
  #                        against cleaned-CSV concatenated names ("birthweight")
  prof_lkp <- setNames(
    lapply(seq_len(nrow(profile)), function(i) profile[i, ]),
    tolower(profile$variable)
  )
  prof_lkp_stripped <- setNames(
    lapply(seq_len(nrow(profile)), function(i) profile[i, ]),
    gsub("_", "", tolower(profile$variable))
  )

  # ---- Part 1: dictionary-ordered variables ----------------------------------
  # matched_csv_lower: actual CSV column names that have been matched, used to
  # exclude them from the "unmatched" section in Part 2.
  matched_csv_lower <- character(0)
  combined_rows <- list()

  if (!is.null(dict_sheet) && nrow(dict_sheet) > 0) {
    for (i in seq_len(nrow(dict_sheet))) {
      dr <- dict_sheet[i, ]
      if (dr$is_section) {
        combined_rows[[length(combined_rows) + 1]] <- list(
          row_type       = "section",
          Description    = dr$Description,
          VariableName   = "",
          Type           = "",
          ValuesCodes    = "",
          nPresent       = "",
          MissingPct     = "",
          Statistics     = "",
          NACodes        = ""
        )
      } else {
        varname <- trimws(dr$VariableName)
        if (is.na(varname) || nchar(varname) == 0) next

        # Look up profile row: try exact case-insensitive match first, then
        # fall back to underscore-stripped match (handles dict snake_case vs
        # CSV concatenated-lowercase naming convention mismatch).
        prof_row <- prof_lkp[[tolower(varname)]]
        if (is.null(prof_row))
          prof_row <- prof_lkp_stripped[[gsub("_", "", tolower(varname))]]

        n_present_str  <- ""
        missing_pct_str <- ""
        stats_str      <- ""

        if (!is.null(prof_row)) {
          # Record the actual CSV column name (from the profile) so Part 2
          # correctly excludes this column from the "unmatched" section.
          matched_csv_lower <- c(matched_csv_lower, tolower(prof_row$variable))
          n_present_str   <- format(prof_row$n_present,  big.mark = ",", trim = TRUE)
          missing_pct_str <- if (!is.na(prof_row$pct_missing))
            sprintf("%.1f%%", prof_row$pct_missing) else ""
          stats_str <- build_stats_string(prof_row)
        }

        combined_rows[[length(combined_rows) + 1]] <- list(
          row_type       = "variable",
          Description    = ifelse(is.na(dr$Description), "", dr$Description),
          VariableName   = varname,
          Type           = ifelse(is.na(dr$Type), "", dr$Type),
          ValuesCodes    = ifelse(is.na(dr$ValuesCodes), "", dr$ValuesCodes),
          nPresent       = n_present_str,
          MissingPct     = missing_pct_str,
          Statistics     = stats_str,
          NACodes        = ifelse(is.na(dr$NACodes), "", dr$NACodes)
        )
      }
    }
  }

  # ---- Part 2: unmatched variables (in data but not in dictionary) ----------
  all_data_lower   <- tolower(data_cols)
  unmatched_lower  <- setdiff(all_data_lower, matched_csv_lower)
  unmatched_cols   <- data_cols[all_data_lower %in% unmatched_lower]

  # Split unmatched into known pipeline variables vs truly unknown
  pipeline_lower <- tolower(names(PIPELINE_VAR_DESCRIPTIONS))
  pipeline_unmatched <- unmatched_cols[tolower(unmatched_cols) %in% pipeline_lower]
  unknown_unmatched  <- unmatched_cols[!tolower(unmatched_cols) %in% pipeline_lower]

  # Add pipeline section
  if (length(pipeline_unmatched) > 0) {
    combined_rows[[length(combined_rows) + 1]] <- list(
      row_type = "section",
      Description = "Pipeline / System Variables",
      VariableName = "", Type = "", ValuesCodes = "",
      nPresent = "", MissingPct = "", Statistics = "", NACodes = ""
    )
    for (vn in pipeline_unmatched) {
      prof_row <- prof_lkp[[tolower(vn)]]
      desc_str <- PIPELINE_VAR_DESCRIPTIONS[[tolower(vn)]]
      if (is.null(desc_str)) desc_str <- ""
      n_present_str <- ""; missing_pct_str <- ""; stats_str <- ""
      if (!is.null(prof_row)) {
        n_present_str   <- format(prof_row$n_present, big.mark = ",", trim = TRUE)
        missing_pct_str <- if (!is.na(prof_row$pct_missing)) sprintf("%.1f%%", prof_row$pct_missing) else ""
        stats_str <- build_stats_string(prof_row)
      }
      combined_rows[[length(combined_rows) + 1]] <- list(
        row_type = "pipeline_variable",
        Description = desc_str,
        VariableName = vn, Type = "", ValuesCodes = "",
        nPresent = n_present_str, MissingPct = missing_pct_str,
        Statistics = stats_str, NACodes = ""
      )
    }
  }

  # Add unknown section
  if (length(unknown_unmatched) > 0) {
    combined_rows[[length(combined_rows) + 1]] <- list(
      row_type = "section",
      Description = "Additional Variables (not in current dictionary version)",
      VariableName = "", Type = "", ValuesCodes = "",
      nPresent = "", MissingPct = "", Statistics = "", NACodes = ""
    )
    for (vn in unknown_unmatched) {
      prof_row <- prof_lkp[[tolower(vn)]]
      n_present_str <- ""; missing_pct_str <- ""; stats_str <- ""
      if (!is.null(prof_row)) {
        n_present_str   <- format(prof_row$n_present, big.mark = ",", trim = TRUE)
        missing_pct_str <- if (!is.na(prof_row$pct_missing)) sprintf("%.1f%%", prof_row$pct_missing) else ""
        stats_str <- build_stats_string(prof_row)
      }
      combined_rows[[length(combined_rows) + 1]] <- list(
        row_type = "unknown_variable",
        Description = "", VariableName = vn, Type = "", ValuesCodes = "",
        nPresent = n_present_str, MissingPct = missing_pct_str,
        Statistics = stats_str, NACodes = ""
      )
    }
  }

  combined_rows
}

# ==============================================================================
# HELPERS: SUBSAMPLE FILE DISCOVERY
# ==============================================================================

# Detect dataset type from filename.
# Pattern: *_subsample_{type}_*.csv
# Returns one of: "admissions", "discharges", "neolab", "maternal",
#                 "master", or NA.
# Master-mode variants (_extended, _matched_only) are all mapped to "master";
# when multiple exist the auto-discovery loop keeps the first (alphabetically
# the plain *_subsample_master_* file, which is the most complete).
detect_type_from_filename <- function(fname) {
  base <- tolower(tools::file_path_sans_ext(basename(fname)))
  types <- c("admissions", "discharges", "neolab", "maternal")
  for (tp in types) {
    pat <- paste0("_subsample_", tp, "_|_subsample_", tp, "$")
    if (grepl(pat, base)) return(tp)
  }
  # Master-mode subsamples: only the plain variant (_subsample_master_ followed
  # by a date / non-keyword character) maps to "master".  The _extended,
  # _matched_only, and _extended_matched_only variants are silently skipped
  # (return NA) so they do not trigger "Multiple files for type 'master'" warnings.
  if (grepl("_subsample_master_(extended|matched_only)", base)) return(NA_character_)
  if (grepl("_subsample_master", base)) return("master")
  NA_character_
}

# Detect country from filename prefix (ZIM_ or MWI_).
detect_country_from_filename <- function(fname) {
  base <- toupper(basename(fname))
  if (grepl("^ZIM_", base)) return("zim")
  if (grepl("^MWI_", base)) return("mwi")
  NA_character_
}

# Map dataset type + country to dictionary sheet name.
dict_sheet_name <- function(type_label, country) {
  if (type_label == "maternal") {
    if (!is.null(country) && tolower(country) == "mwi")
      return("combined_maternity_outcomes")
    return("Maternal Outcomes")
  }
  if (type_label == "master") return("Master")
  # Sheet names in the user dictionary are title-case (e.g. "Admissions")
  paste0(toupper(substring(type_label, 1, 1)), substring(type_label, 2))
}

# ==============================================================================
# HELPERS: EXCEL WRITER
# ==============================================================================

SHEET_COL_HEADERS <- c(
  "Description", "Variable Name", "Type", "Values / Codes",
  "n present", "Missing %", "Statistics", "NA Codes"
)
SHEET_N_COLS <- length(SHEET_COL_HEADERS)

# Column widths (approximate)
SHEET_COL_WIDTHS <- c(40, 28, 14, 40, 10, 10, 38, 14)

# Styles
.sty_header <- function() createStyle(
  fontName = "Calibri", fontSize = 11, fontColour = "white",
  fgFill = "#2F5496", halign = "left", valign = "center",
  textDecoration = "bold", wrapText = FALSE, border = NULL
)
.sty_section <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#1F3864",
  fgFill = "#D9E1F2", halign = "left", valign = "center",
  textDecoration = "bold", wrapText = FALSE
)
.sty_variable <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#000000",
  halign = "left", valign = "top", wrapText = TRUE
)
.sty_pipeline_var <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#595959",
  halign = "left", valign = "top", wrapText = TRUE,
  fgFill = "#F2F2F2"
)
.sty_unknown_var <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#767676",
  halign = "left", valign = "top", wrapText = TRUE,
  fgFill = "#F9F9F9"
)
.sty_stat_num <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#1F5C2E",
  halign = "left", valign = "top", wrapText = FALSE
)
.sty_stat_cat <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#17375E",
  halign = "left", valign = "top", wrapText = FALSE
)
.sty_missing_hi <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#C00000",
  halign = "center", valign = "top"
)
.sty_missing_lo <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#767676",
  halign = "center", valign = "top"
)
.sty_about_key <- function() createStyle(
  fontName = "Calibri", fontSize = 11, textDecoration = "bold",
  halign = "right", valign = "center"
)
.sty_about_val <- function() createStyle(
  fontName = "Calibri", fontSize = 11, halign = "left", valign = "center"
)
.sty_about_title <- function() createStyle(
  fontName = "Calibri", fontSize = 14, textDecoration = "bold",
  fontColour = "#2F5496", halign = "left", valign = "center"
)

write_dataset_sheet <- function(wb, sheet_name, combined_rows, n_data_rows) {
  addWorksheet(wb, sheet_name)

  # Freeze pane below header row
  freezePane(wb, sheet_name, firstRow = TRUE)

  # Set column widths
  setColWidths(wb, sheet_name, cols = seq_len(SHEET_N_COLS), widths = SHEET_COL_WIDTHS)

  # Write header row
  writeData(wb, sheet_name,
    as.data.frame(as.list(setNames(SHEET_COL_HEADERS, SHEET_COL_HEADERS))),
    startRow = 1, startCol = 1, colNames = FALSE)
  addStyle(wb, sheet_name, style = .sty_header(),
    rows = 1, cols = seq_len(SHEET_N_COLS), gridExpand = TRUE)
  setRowHeights(wb, sheet_name, rows = 1, heights = 20)

  if (length(combined_rows) == 0) return(invisible(NULL))

  # Write data rows
  for (i in seq_along(combined_rows)) {
    row_data <- combined_rows[[i]]
    excel_row <- i + 1  # row 1 is header

    if (row_data$row_type == "section") {
      # Section header: write Description spanning all columns (visually)
      writeData(wb, sheet_name,
        x = data.frame(V1 = row_data$Description, stringsAsFactors = FALSE),
        startRow = excel_row, startCol = 1, colNames = FALSE)
      # Merge all columns for section visual
      mergeCells(wb, sheet_name,
        cols = seq_len(SHEET_N_COLS), rows = excel_row)
      addStyle(wb, sheet_name, style = .sty_section(),
        rows = excel_row, cols = seq_len(SHEET_N_COLS), gridExpand = TRUE)
      setRowHeights(wb, sheet_name, rows = excel_row, heights = 18)

    } else {
      # Variable row
      row_vals <- data.frame(
        Description  = row_data$Description,
        VariableName = row_data$VariableName,
        Type         = row_data$Type,
        ValuesCodes  = row_data$ValuesCodes,
        nPresent     = row_data$nPresent,
        MissingPct   = row_data$MissingPct,
        Statistics   = row_data$Statistics,
        NACodes      = row_data$NACodes,
        stringsAsFactors = FALSE
      )
      writeData(wb, sheet_name, x = row_vals,
        startRow = excel_row, startCol = 1, colNames = FALSE)

      # Base style (depends on row type)
      base_sty <- switch(row_data$row_type,
        pipeline_variable = .sty_pipeline_var(),
        unknown_variable  = .sty_unknown_var(),
        .sty_variable()
      )
      addStyle(wb, sheet_name, style = base_sty,
        rows = excel_row, cols = seq_len(SHEET_N_COLS), gridExpand = TRUE)

      # Statistics column: colour by data type
      if (nchar(row_data$Statistics) > 0) {
        # Determine original data type from profile — infer from statistics content
        stat_sty <- if (grepl("Range:", row_data$Statistics)) .sty_stat_num()
                    else .sty_stat_cat()
        addStyle(wb, sheet_name, style = stat_sty,
          rows = excel_row, cols = 7, gridExpand = FALSE, stack = TRUE)
      }

      # Missing % column: red if > 10%
      mp <- row_data$MissingPct
      if (nchar(mp) > 0) {
        pct_val <- suppressWarnings(as.numeric(sub("%", "", mp)))
        if (!is.na(pct_val) && pct_val > 10) {
          addStyle(wb, sheet_name, style = .sty_missing_hi(),
            rows = excel_row, cols = 6, stack = TRUE)
        } else if (!is.na(pct_val)) {
          addStyle(wb, sheet_name, style = .sty_missing_lo(),
            rows = excel_row, cols = 6, stack = TRUE)
        }
      }

      setRowHeights(wb, sheet_name, rows = excel_row, heights = 30)
    }
  }
  invisible(NULL)
}

write_about_sheet <- function(wb, study_name, country, run_date,
                              sheet_summaries) {
  addWorksheet(wb, "About")
  setColWidths(wb, "About", cols = 1:2, widths = c(22, 50))

  title_row <- 1
  writeData(wb, "About",
    x = data.frame(V1 = "Neotree Researcher Data Package", stringsAsFactors = FALSE),
    startRow = title_row, startCol = 1, colNames = FALSE)
  addStyle(wb, "About", style = .sty_about_title(),
    rows = title_row, cols = 1, stack = FALSE)
  mergeCells(wb, "About", cols = 1:2, rows = title_row)
  setRowHeights(wb, "About", rows = title_row, heights = 28)

  entries <- list(
    list("Study",        study_name),
    list("Country",      if (!is.null(country)) toupper(country) else ""),
    list("Generated",    run_date),
    list("", ""),
    list("Contents", "")
  )
  for (ss in sheet_summaries) {
    entries[[length(entries) + 1]] <- list(
      ss$sheet_label,
      sprintf("%s — %s rows x %s columns",
        ss$file_label,
        format(ss$n_rows, big.mark = ","),
        format(ss$n_cols, big.mark = ","))
    )
  }
  entries[[length(entries) + 1]] <- list("", "")
  entries[[length(entries) + 1]] <- list(
    "Note",
    paste0(
      "Variables with >10% missing values are highlighted in red in the Missing % column. ",
      "Statistics are computed on all rows in the subsample (after any date/facility/exclusion filters). ",
      "See the NA Codes sheet for a legend of missing-value codes used in Neotree data."
    )
  )

  for (idx in seq_along(entries)) {
    rw <- title_row + idx
    key_val <- entries[[idx]][[1]]
    data_val <- entries[[idx]][[2]]
    writeData(wb, "About",
      x = data.frame(K = key_val, V = data_val, stringsAsFactors = FALSE),
      startRow = rw, startCol = 1, colNames = FALSE)
    if (nchar(key_val) > 0) {
      addStyle(wb, "About", style = .sty_about_key(), rows = rw, cols = 1)
      addStyle(wb, "About", style = .sty_about_val(), rows = rw, cols = 2)
    }
    setRowHeights(wb, "About", rows = rw, heights = if (key_val == "Note") 50 else 18)
  }
  invisible(NULL)
}

write_nacodes_sheet <- function(wb) {
  addWorksheet(wb, "NA Codes")
  setColWidths(wb, "NA Codes", cols = 1:3, widths = c(14, 62, 26))

  sty_note <- createStyle(
    fontName = "Calibri", fontSize = 10, fontColour = "#595959",
    wrapText = TRUE, valign = "top"
  )
  sty_code_num <- createStyle(
    fontName = "Calibri Mono", fontSize = 10, fontColour = "#1F3864",
    halign = "center", valign = "top", wrapText = FALSE,
    textDecoration = "bold"
  )
  sty_priority <- createStyle(
    fontName = "Calibri", fontSize = 9, fontColour = "#767676",
    halign = "center", valign = "top", wrapText = FALSE
  )

  cur_row <- 1L

  # ── Column header ──────────────────────────────────────────────────────────
  writeData(wb, "NA Codes",
    x = data.frame(Code = "NA Code", Meaning = "Meaning / Context",
                   AppliesToField = "Applies to / Notes",
                   stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, "NA Codes", style = .sty_header(),
    rows = cur_row, cols = 1:3, gridExpand = TRUE)
  setRowHeights(wb, "NA Codes", rows = cur_row, heights = 20)
  cur_row <- cur_row + 1L

  # ── Section 1: Numeric sentinel codes (na_coded data files) ────────────────
  writeData(wb, "NA Codes",
    x = data.frame(
      V1 = "Numeric codes — used in *_na_coded.csv data files",
      V2 = "", V3 = "", stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, "NA Codes", style = .sty_section(),
    rows = cur_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, "NA Codes", cols = 1:3, rows = cur_row)
  setRowHeights(wb, "NA Codes", rows = cur_row, heights = 18)
  cur_row <- cur_row + 1L

  num_codes <- data.frame(
    Code = c("-6", "-7", "-8", "-9"),
    Meaning = c(
      "REDACTED — Value existed in the raw data but was removed because it matched a PII pattern (phone number, e-mail address, NHS/hospital ID, etc.)",
      "NOT APPLICABLE — The field was never shown to the data collector. The form's skip logic determined the field was not relevant for this patient or record type (e.g. discharge fields hidden for a Brought-In-Dead admission).",
      "INVALID / REMOVED — A value was present in the raw data but was removed by the cleaning pipeline (unrecognised code, failed type coercion, out-of-range value, etc.).",
      "UNKNOWN — The raw cell was empty or contained a recognised missing-value placeholder (blank, nan, none, null, n/a, NK, UNK, NR, etc.)."
    ),
    Priority = c(
      "Priority 1 (highest)",
      "Priority 2",
      "Priority 3",
      "Priority 4 (default)"
    ),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(num_codes))) {
    writeData(wb, "NA Codes",
      x = data.frame(
        Code    = num_codes$Code[i],
        Meaning = num_codes$Meaning[i],
        Priority = num_codes$Priority[i],
        stringsAsFactors = FALSE),
      startRow = cur_row, colNames = FALSE)
    addStyle(wb, "NA Codes", style = sty_code_num,
      rows = cur_row, cols = 1)
    addStyle(wb, "NA Codes", style = .sty_variable(),
      rows = cur_row, cols = 2)
    addStyle(wb, "NA Codes", style = sty_priority,
      rows = cur_row, cols = 3)
    setRowHeights(wb, "NA Codes", rows = cur_row, heights = 42)
    cur_row <- cur_row + 1L
  }

  # Blank separator row
  cur_row <- cur_row + 1L

  # ── Section 2: Raw form string codes ──────────────────────────────────────
  writeData(wb, "NA Codes",
    x = data.frame(
      V1 = "String codes — entered by data collectors in the raw Neotree form",
      V2 = "", V3 = "", stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, "NA Codes", style = .sty_section(),
    rows = cur_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, "NA Codes", cols = 1:3, rows = cur_row)
  setRowHeights(wb, "NA Codes", rows = cur_row, heights = 18)
  cur_row <- cur_row + 1L

  str_codes <- data.frame(
    Code = c(
      "NK", "UNK", "NR", "REFUSED", "NE", "NA",
      "NOT_DONE", "PENDING", "UNKNOWN", "OTHER"
    ),
    Meaning = c(
      "Not Known — information was not available at time of entry",
      "Unknown — synonymous with NK; used in some field versions",
      "Not Recorded — field was seen but left blank",
      "Patient or carer refused to provide the information",
      "Not Examined — the examination or procedure was not performed",
      "Not Applicable — the field does not apply to this patient / record type",
      "Procedure or test was not done",
      "Result is pending (used in neolab records)",
      "General unknown — used in dropdown fields with no other option",
      "Other — a value outside the standard coded list; free-text may accompany"
    ),
    AppliesToField = c(
      "General", "General", "General", "General",
      "Clinical fields", "General", "Lab / procedure fields",
      "Lab fields", "Categorical fields", "Categorical fields"
    ),
    stringsAsFactors = FALSE
  )
  writeData(wb, "NA Codes", x = str_codes, startRow = cur_row, colNames = FALSE)
  addStyle(wb, "NA Codes", style = .sty_variable(),
    rows = cur_row:(cur_row + nrow(str_codes) - 1L), cols = 1:3, gridExpand = TRUE)
  setRowHeights(wb, "NA Codes",
    rows = cur_row:(cur_row + nrow(str_codes) - 1L), heights = 22)
  cur_row <- cur_row + nrow(str_codes)

  # ── Footer note ───────────────────────────────────────────────────────────
  note_row <- cur_row + 1L
  writeData(wb, "NA Codes",
    x = data.frame(V = paste0(
      "Note: In na_coded data files all missing values are replaced by the ",
      "numeric codes above (-6 to -9). The string codes in Section 2 appear ",
      "only in pre-cleaning / non-coded files. When filtering data, exclude ",
      "both blank cells AND the relevant numeric NA codes. ",
      "The 'NA Codes' column in each dataset sheet lists which numeric codes ",
      "apply to each variable."
    ), stringsAsFactors = FALSE),
    startRow = note_row, startCol = 1, colNames = FALSE)
  addStyle(wb, "NA Codes", style = sty_note,
    rows = note_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, "NA Codes", cols = 1:3, rows = note_row)
  setRowHeights(wb, "NA Codes", rows = note_row, heights = 60)

  invisible(NULL)
}

# ==============================================================================
# MAIN PIPELINE
# ==============================================================================

cat("Step 1/5  Resolving configuration...\n")

# --- Resolve paths ---
user_dict_dir  <- .resolve_path(cfg$user_dict_dir)
subsample_dir  <- if (!is.null(cfg$subsample_dir)) .resolve_path(cfg$subsample_dir) else NULL
output_dir_cfg <- if (!is.null(cfg$output_dir))    .resolve_path(cfg$output_dir)    else NULL

if (!is.null(user_dict_dir) && !dir.exists(user_dict_dir)) {
  stop(sprintf(
    "User dictionary folder not found:\n  %s\n",
    "Check that user_dict_dir points to the folder containing neotree_user_dict_zim.xlsx / neotree_user_dict_mwi.xlsx"
  ))
}

# --- Discover subsample files ---
file_map <- list()  # named list: type -> file path

if (length(cfg$subsample_files) > 0) {
  # MANUAL MODE
  for (nm in names(cfg$subsample_files)) {
    fp <- .resolve_path(cfg$subsample_files[[nm]])
    if (!file.exists(fp)) {
      cat(sprintf("  [WARN] Subsample file not found, skipping: %s\n", cfg$subsample_files[[nm]]))
    } else {
      file_map[[nm]] <- fp
    }
  }
  cat(sprintf("  Manual mode: %d file(s) specified.\n", length(file_map)))

} else if (!is.null(subsample_dir)) {
  # AUTO MODE
  if (!dir.exists(subsample_dir)) {
    stop(sprintf("subsample_dir not found:\n  %s", subsample_dir))
  }
  all_csv <- list.files(subsample_dir, pattern = "_subsample_.*\\.csv$",
                        full.names = TRUE, ignore.case = TRUE)
  if (length(all_csv) == 0) {
    stop(sprintf("No subsample CSV files found in:\n  %s", subsample_dir))
  }
  for (fp in all_csv) {
    tp <- detect_type_from_filename(fp)
    if (is.na(tp)) {
      cat(sprintf("  [WARN] Cannot determine type for: %s — skipped.\n", basename(fp)))
    } else {
      if (tp %in% names(file_map)) {
        cat(sprintf("  [WARN] Multiple files for type '%s'; keeping first.\n", tp))
      } else {
        file_map[[tp]] <- fp
      }
    }
  }
  cat(sprintf("  Auto mode: %d subsample CSV(s) discovered in %s\n",
              length(file_map), basename(subsample_dir)))

} else {
  stop(paste0(
    "No subsample files specified.\n",
    "Set either subsample_dir (auto-discover) or subsample_files (manual list) in DICT_CONFIG.\n"
  ))
}

if (length(file_map) == 0) {
  stop("No valid subsample files found. Nothing to process.\n")
}

# --- Detect country ---
country <- cfg$country
if (is.null(country) || !nchar(trimws(country))) {
  # Try to detect from first file
  country <- detect_country_from_filename(file_map[[1]])
  if (is.na(country)) {
    stop(paste0(
      "Cannot auto-detect country from filename: ", basename(file_map[[1]]), "\n",
      "Set country = \"zim\" or country = \"mwi\" in DICT_CONFIG.\n"
    ))
  }
  cat(sprintf("  Country auto-detected: %s\n", toupper(country)))
} else {
  country <- tolower(trimws(country))
  cat(sprintf("  Country: %s\n", toupper(country)))
}

# --- Locate user dictionary ---
dict_file <- file.path(user_dict_dir, sprintf("neotree_user_dict_%s.xlsx", country))
if (!file.exists(dict_file)) {
  cat(sprintf("  [WARN] User dictionary not found: %s\n", basename(dict_file)))
  cat("         Continuing without dictionary (profile data only).\n")
  dict_file <- NULL
} else {
  cat(sprintf("  User dictionary: %s\n", basename(dict_file)))
}

# --- Determine output directory and prefix ---
first_file <- file_map[[1]]
out_dir <- if (!is.null(output_dir_cfg)) {
  output_dir_cfg
} else if (!is.null(subsample_dir)) {
  subsample_dir
} else {
  dirname(normalizePath(first_file))
}
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# Derive prefix from first subsample filename
# Expected pattern: {PREFIX}_subsample_{type}_{label}.csv
base_no_ext <- tools::file_path_sans_ext(basename(first_file))
# Remove _subsample_{type}_{...} suffix
prefix_label <- sub("_subsample_.+$", "", base_no_ext)
# Derive a shared label from the first file (date range part)
label_part <- sub(paste0("^", prefix_label, "_subsample_[a-z]+_"), "", base_no_ext)
label_part <- if (nchar(label_part) == 0 || label_part == base_no_ext) {
  format(Sys.Date(), "%Y%m%d")
} else {
  label_part
}

out_filename <- sprintf("%s_data_package_%s.xlsx", prefix_label, label_part)
out_path <- file.path(out_dir, out_filename)

cat(sprintf("  Output file     : %s\n", out_filename))
cat(sprintf("  Output directory: %s\n\n", out_dir))

# ==============================================================================
# STEP 2/5: LOAD AND PROFILE EACH SUBSAMPLE
# ==============================================================================

cat("Step 2/5  Loading and profiling subsample CSV files...\n")

type_results <- list()  # named by type_label

for (tp in names(file_map)) {
  fp <- file_map[[tp]]
  cat(sprintf("  [%s]  %s\n", tp, basename(fp)))

  df <- tryCatch(
    read.csv(fp, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) {
      cat(sprintf("    [ERROR] Failed to load: %s\n", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(df)) next

  cat(sprintf("    Loaded: %d rows x %d columns\n", nrow(df), ncol(df)))

  prof <- profile_dataframe(df,
    numeric_threshold    = cfg$numeric_threshold,
    max_numeric_distinct = cfg$max_numeric_distinct
  )
  cat(sprintf("    Profiled: %d numeric, %d boolean, %d categorical\n",
    sum(prof$type == "numeric"),
    sum(prof$type == "boolean"),
    sum(prof$type == "categorical")
  ))

  type_results[[tp]] <- list(df = df, profile = prof, file = fp)
}

if (length(type_results) == 0) {
  stop("All subsample files failed to load. Aborting.\n")
}

# ==============================================================================
# STEP 3/5: READ USER DICTIONARY SHEETS
# ==============================================================================

cat("\nStep 3/5  Reading user dictionary...\n")

dict_sheets <- list()  # named by type_label

for (tp in names(type_results)) {
  sname <- dict_sheet_name(tp, country)
  if (!is.null(dict_file)) {
    cat(sprintf("  [%s]  reading sheet: %s\n", tp, sname))
    ds <- read_user_dict_sheet(dict_file, sname)
    if (is.null(ds)) {
      cat(sprintf("    [WARN] Sheet '%s' not found in dictionary.\n", sname))
    } else {
      n_vars <- sum(!ds$is_section)
      n_secs <- sum(ds$is_section)
      cat(sprintf("    %d variables across %d sections\n", n_vars, n_secs))
    }
    dict_sheets[[tp]] <- ds
  } else {
    dict_sheets[[tp]] <- NULL
  }
}

# ==============================================================================
# STEP 4/5: BUILD COMBINED ROWS PER SHEET
# ==============================================================================

cat("\nStep 4/5  Merging dictionary with profile data...\n")

sheet_combined <- list()   # named by tp -> list of combined rows
sheet_summaries <- list()  # for About sheet

SHEET_LABEL_MAP <- c(
  admissions = "Admissions",
  discharges = "Discharges",
  neolab     = "Neolab",
  maternal   = "Maternal",
  master     = "Master"
)

for (tp in names(type_results)) {
  res  <- type_results[[tp]]
  ds   <- dict_sheets[[tp]]
  prof <- res$profile
  df   <- res$df

  rows <- build_combined_sheet(df, ds, prof, tp)
  sheet_combined[[tp]] <- rows

  n_in_dict  <- if (!is.null(ds)) sum(!ds$is_section) else 0
  n_in_data  <- ncol(df)
  # Count matches using the same two-stage lookup used in build_combined_sheet:
  # exact case-insensitive first, then underscore-stripped fallback.
  if (!is.null(ds)) {
    dict_names_lower    <- tolower(ds$VariableName[!ds$is_section & !is.na(ds$VariableName)])
    dict_names_stripped <- gsub("_", "", dict_names_lower)
    prof_names_lower    <- tolower(prof$variable)
    prof_names_stripped <- gsub("_", "", prof_names_lower)
    n_matched <- length(union(
      intersect(prof_names_lower,    dict_names_lower),
      intersect(prof_names_stripped, dict_names_stripped)
    ))
  } else {
    n_matched <- 0L
  }
  cat(sprintf("  [%s]  %d data columns | %d in dictionary | %d matched\n",
    tp, n_in_data, n_in_dict, n_matched))

  sheet_summaries[[length(sheet_summaries) + 1]] <- list(
    sheet_label = SHEET_LABEL_MAP[[tp]],
    file_label  = basename(res$file),
    n_rows      = nrow(df),
    n_cols      = ncol(df)
  )
}

# ==============================================================================
# STEP 5/5: WRITE EXCEL WORKBOOK
# ==============================================================================

cat(sprintf("\nStep 5/5  Writing Excel workbook: %s\n", out_filename))

wb <- createWorkbook()
modifyBaseFont(wb, fontSize = 10, fontName = "Calibri")

# About sheet (first)
write_about_sheet(wb,
  study_name     = cfg$study_name,
  country        = country,
  run_date       = format(Sys.time(), "%Y-%m-%d %H:%M"),
  sheet_summaries = sheet_summaries
)
cat("  [done]  About\n")

# Dataset sheets (in a consistent order)
type_order <- c("admissions", "discharges", "master", "neolab", "maternal")
for (tp in type_order) {
  if (!tp %in% names(sheet_combined)) next
  sheet_label <- SHEET_LABEL_MAP[[tp]]
  combined    <- sheet_combined[[tp]]
  n_data_rows <- nrow(type_results[[tp]]$df)
  write_dataset_sheet(wb, sheet_label, combined, n_data_rows)
  cat(sprintf("  [done]  %s (%d rows written)\n", sheet_label, length(combined)))
}

# NA Codes sheet (last)
write_nacodes_sheet(wb)
cat("  [done]  NA Codes\n")

# Save
saveWorkbook(wb, out_path, overwrite = TRUE)

cat(sprintf("\n[output]  %s\n\n", normalizePath(out_path, mustWork = FALSE)))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("================================================================\n")
cat("  Researcher Data Package complete.\n")
cat(sprintf("  Workbook : %s\n", out_filename))
cat(sprintf("  Location : %s\n", out_dir))
cat(sprintf("  Sheets   : About  |  %s  |  NA Codes\n",
  paste(sapply(sheet_summaries, `[[`, "sheet_label"), collapse = "  |  ")
))
cat("================================================================\n\n")

invisible(list(workbook = wb, output_path = out_path))
