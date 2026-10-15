# =============================================================================
# NEOTREE CLEANING PIPELINE -- Batch Runner
# =============================================================================
# PURPOSE:
#   Runs the cleaning pipeline once for every CSV file in input/ whose name
#   follows the Neotree file naming convention.
#
# METHOD:
#   Lists the CSV files in input/, applies RUN_ALL_FILTER and RUN_ALL_SKIP,
#   and parses each filename into country, data source and dataset. For each
#   parsed file it sets the pipeline parameters as globals, sources
#   run_pipeline.r inside tryCatch, records success or the error message, and
#   removes the pipeline's globals before the next file.
#
#   Accepted filename forms:
#     {country}_{dataset}_{date}.csv
#     {country}_{source}_{dataset}_{date}.csv
#
#   country  : mwi | zim
#   source   : db (database export) | mb (Metabase export). Optional. Without
#              it the data source is passed as "auto".
#   dataset  : one of KNOWN_DATASETS
#   date     : YYYY-MM-DD | YYYYMMDD | YYYYMMDDHHMM
#
#   Example names: zim_admissions_2000-01-31.csv,
#   mwi_db_phc_discharges_20000131.csv
#
#   A file whose name matches neither form, or whose dataset is not in
#   KNOWN_DATASETS, is listed as skipped.
#
# INPUTS:
#   CSV files in input/. RUN_ALL_FILTER and RUN_ALL_SKIP, set below.
#
# OUTPUTS:
#   The outputs of run_pipeline.r for each file, and a console listing of the
#   run plan, skipped files, failures with their error messages, and
#   successes.
#
# USAGE:
#   Rscript run_all.r
#   # or, interactively:
#   source("run_all.r")
# =============================================================================

# -----------------------------------------------------------------------------
# Set the working directory to this file's own folder so that the relative
# paths below resolve wherever the script is launched from (Rscript, source(),
# R console).
# -----------------------------------------------------------------------------
.nt_get_script_dir <- function() {
  args     <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0)
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  for (i in seq_len(sys.nframe())) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile) && nchar(ofile) > 0)
      return(dirname(normalizePath(ofile)))
  }
  getwd()
}
setwd(normalizePath(.nt_get_script_dir(), mustWork = FALSE))

# =============================================================================
# OPTIONAL FILTERS
# =============================================================================

# Regex applied to the full filename (basename, no path). Leave as NULL to
# process every matching file.
# Example: "^zim_" to process only files whose name starts with zim_
#          "admissions|discharges" to process only names containing either
RUN_ALL_FILTER <- NULL

# Character vector of exact filenames (basename) to skip.
# Example: c("mwi_combined_maternity_outcomes_2000-01-31.csv")
RUN_ALL_SKIP <- character(0)

# =============================================================================
# INTERNAL SETUP
# =============================================================================

INPUT_DIR  <- "input"
OUTPUT_DIR <- "output"

# Datasets the batch runner accepts (must match VALID_DATASETS in 00_setup.r)
KNOWN_DATASETS <- c(
  "admissions", "discharges", "maternal_outcomes",
  "phc_admissions", "phc_discharges",
  "combined_maternity_outcomes",
  "dhis2_maternal_outcomes",
  "maternity_completeness",
  "joined_admissions_discharges",
  "neolab",
  "baseline",
  "infections",
  "twenty_8_day_follow_up"
)

# =============================================================================
# HELPER: Parse a filename into pipeline parameters
# =============================================================================
# Returns a named list with:
#   country      : "MWI" or "ZIM"
#   data_source  : "database", "metabase", or "auto" (no source token in the
#                  name)
#   dataset      : the dataset token, lower case
#   csv_filepath : relative path (e.g. "input/zim_admissions_2000-01-31.csv")
#   unknown      : TRUE if the dataset is not in KNOWN_DATASETS
# Returns NULL if the filename does not match either pattern.

parse_input_filename <- function(fname) {
  bname <- basename(fname)

  # Date is YYYY-MM-DD, 8 digits (YYYYMMDD) or 12 digits (YYYYMMDDHHMM).
  date_re <- "(\\d{12}|\\d{8}|\\d{4}-\\d{2}-\\d{2})"

  # 1. Form with a source token: {country}_{db|mb}_{dataset}_{date}.csv
  #    Tried first, so an explicit token always wins.
  pattern_src <- paste0("^(mwi|zim)_(db|mb)_(.+)_", date_re, "\\.csv$")
  m <- regmatches(bname, regexec(pattern_src, bname, ignore.case = TRUE))[[1]]

  if (length(m) > 0) {
    country_raw <- tolower(m[2])
    source_raw  <- tolower(m[3])
    dataset_raw <- tolower(m[4])
  } else {
    # 2. Form without a source token: {country}_{dataset}_{date}.csv
    pattern_nosrc <- paste0("^(mwi|zim)_(.+)_", date_re, "\\.csv$")
    m <- regmatches(bname, regexec(pattern_nosrc, bname, ignore.case = TRUE))[[1]]
    if (length(m) == 0) return(NULL) # does not match either form
    country_raw <- tolower(m[2])
    source_raw  <- "auto"
    dataset_raw <- tolower(m[3])
  }

  country     <- switch(country_raw, mwi = "MWI", zim = "ZIM", NULL)
  data_source <- switch(source_raw,  db  = "database", mb = "metabase",
                        auto = "auto", NULL)

  if (is.null(country) || is.null(data_source)) return(NULL)

  # Validate dataset against known list
  if (!dataset_raw %in% KNOWN_DATASETS) {
    return(list(
      country      = country,
      data_source  = data_source,
      dataset      = dataset_raw,
      csv_filepath = file.path(INPUT_DIR, bname),
      unknown      = TRUE   # flag for the caller to warn and skip
    ))
  }

  list(
    country      = country,
    data_source  = data_source,
    dataset      = dataset_raw,
    csv_filepath = file.path(INPUT_DIR, bname),
    unknown      = FALSE
  )
}

# =============================================================================
# DISCOVER INPUT FILES
# =============================================================================

all_csv <- list.files(INPUT_DIR, pattern = "\\.csv$", full.names = FALSE)

if (length(all_csv) == 0) {
  stop(sprintf("No CSV files found in '%s/'. Nothing to do.", INPUT_DIR))
}

# Apply user filter
if (!is.null(RUN_ALL_FILTER)) {
  all_csv <- all_csv[grepl(RUN_ALL_FILTER, all_csv, perl = TRUE)]
}

# Apply skip list
if (length(RUN_ALL_SKIP) > 0) {
  all_csv <- all_csv[!all_csv %in% RUN_ALL_SKIP]
}

# =============================================================================
# PARSE AND PLAN
# =============================================================================

run_plan  <- list()  # files to process
skipped   <- list()  # files that couldn't be parsed or are unknown datasets

for (fname in all_csv) {
  parsed <- parse_input_filename(fname)

  if (is.null(parsed)) {
    skipped <- c(skipped, list(list(file = fname, reason = "filename does not match expected pattern")))
    next
  }
  if (isTRUE(parsed$unknown)) {
    skipped <- c(skipped, list(list(
      file   = fname,
      reason = sprintf("unrecognised dataset type '%s' (not in KNOWN_DATASETS)", parsed$dataset)
    )))
    next
  }
  run_plan <- c(run_plan, list(parsed))
}

# =============================================================================
# PRINT RUN PLAN
# =============================================================================

cat(sprintf(
  "\n=== Neotree Batch Runner ===\n  Found %d file(s) in %s/\n  Will process : %d\n  Will skip    : %d\n\n",
  length(all_csv), INPUT_DIR, length(run_plan), length(skipped)
))

if (length(skipped) > 0) {
  cat("Files being skipped:\n")
  for (s in skipped) {
    cat(sprintf("  [SKIP] %s\n         Reason: %s\n", s$file, s$reason))
  }
  cat("\n")
}

if (length(run_plan) == 0) {
  cat("Nothing to process. Exiting.\n")
  quit(status = 0)
}

cat("Run plan:\n")
for (i in seq_along(run_plan)) {
  p <- run_plan[[i]]
  cat(sprintf(
    "  [%2d/%2d] %-55s  country=%-3s  source=%-8s  dataset=%s\n",
    i, length(run_plan), p$csv_filepath,
    p$country, p$data_source, p$dataset
  ))
}
cat("\n")

# =============================================================================
# GLOBAL VARIABLES PRODUCED BY THE PIPELINE
# (used to clean up between runs)
# =============================================================================

PIPELINE_GLOBALS <- c(
  # Configuration
  "COUNTRY", "DATASET", "DATA_SOURCE", "CSV_FILEPATH",
  "DICT_FILEPATH", "OUTPUT_CSV", "OUTPUT_RDS", "REPORT_DIR",
  "OUTPUT_DIR", "NEOTREE_SCRIPTS_DIR",
  "VALID_DATASETS", "DICT_FALLBACK",
  "EXTRA_META_COLS", "TIMESTAMP_COLS", "KEY_COLS",
  # Module 02: uid repair separators + paired-file resolution
  "UID_REPAIR_SEPARATORS", "PAIRED_DATASET", "paired_info",
  # Module 01: reserved-system-column-name collision renames
  "RESERVED_COLUMN_RENAMES",
  # Output flags
  "SAVE_DEIDENTIFIED", "SAVE_STAGE1_CHECKPOINT", "SAVE_HARMONISED",
  "SAVE_NA_CODED", "SAVE_NA_REASONS_LONG", "SKIP_DEDUP_STAGE2",
  # Per-run output subdirectory helpers
  "file_stem", "RUN_OUTPUT_DIR",
  # Config object and dictionary tables
  "cfg", "dict_variables", "dict_value_maps",
  # Feature lists
  "numeric_features", "bool_features", "cat_features",
  "obj_features", "dt_features",
  "value_map_list", "range_lookup", "weight_cols",
  "pii_columns", "harmonised_name_map",
  # Data-source detection (00_setup.r)
  "ds_detected",
  # Data frames passed between modules
  "df_raw", "df_raw_deidentified", "df_std",
  "df_shifted", "df_merged", "df_dict", "df_filled",
  "df_num_filled", "df_dropped", "df_auto", "df_typed",
  "df_deduped", "df_num", "df_bool", "df_cat", "df_dt",
  "df_clean", "df_harmonised", "df_na_coded",
  # Timing
  "pipeline_start", "PIPELINE_VERSION",
  # helpers defined in 00_setup.r
  "cols_of_type",
  # PII definitions and guard (00_setup.r / 00a).  The completion marker is a
  # file, not a global, so clearing these does not bypass the guard.
  "PII_FALLBACK_PATTERNS_DEFAULT", "PII_VALUE_PATTERNS", "PII_VALUE_SCAN_EXEMPT",
  "PII_SHEET_PATTERNS", "PII_TIER2_PATTERNS", "PII_MARKER_PATH",
  "PII_FALLBACK_PATTERNS", "PII_QUASI_COL_PATTERNS", "pii_input_path", "pii_run_id"
)

# =============================================================================
# RUN PIPELINE FOR EACH FILE
# =============================================================================

batch_start   <- Sys.time()
results       <- list()

for (i in seq_along(run_plan)) {

  p <- run_plan[[i]]
  cat(sprintf(
    "\n%s\n[%d/%d] Processing: %s\n%s\n",
    strrep("=", 72), i, length(run_plan), p$csv_filepath, strrep("=", 72)
  ))

  # -- Set pipeline parameters (read by 00_setup.r via if(!exists()) guards) --
  COUNTRY          <<- p$country
  DATASET          <<- p$dataset
  DATA_SOURCE      <<- p$data_source
  CSV_FILEPATH     <<- p$csv_filepath
  # Reset auto-derived paths so each run gets its own output location
  DICT_FILEPATH    <<- NULL
  OUTPUT_CSV       <<- NULL
  OUTPUT_RDS       <<- NULL
  REPORT_DIR       <<- NULL
  OUTPUT_DIR       <<- "output"
  NEOTREE_SCRIPTS_DIR <<- NULL

  # -- Run the pipeline --------------------------------------------------------
  # The error message is stored as well as printed, so that the batch summary
  # can list it.
  run_err <- NA_character_
  run_ok  <- tryCatch({
    source("run_pipeline.r")
    TRUE
  }, error = function(e) {
    run_err <<- conditionMessage(e)
    cat(sprintf("\n  [ERROR] Pipeline failed for %s:\n  %s\n\n",
                p$csv_filepath, run_err))
    FALSE
  })

  # Data source to report: the global DATA_SOURCE if the run left one other
  # than "auto", otherwise the value parsed from the filename.
  source_used <- if (exists("DATA_SOURCE", envir = .GlobalEnv, inherits = FALSE) &&
                     !identical(get("DATA_SOURCE", envir = .GlobalEnv), "auto")) {
    get("DATA_SOURCE", envir = .GlobalEnv)
  } else {
    p$data_source
  }

  results <- c(results, list(list(
    file    = p$csv_filepath,
    country = p$country,
    dataset = p$dataset,
    source  = source_used,
    ok      = run_ok,
    error   = run_err
  )))

  # -- Clean up globals so the next run starts from a clean slate --------------
  rm(list = intersect(ls(envir = .GlobalEnv), PIPELINE_GLOBALS), envir = .GlobalEnv)

}

# =============================================================================
# BATCH SUMMARY
# =============================================================================

n_ok   <- sum(sapply(results, `[[`, "ok"))
n_fail <- length(results) - n_ok
elapsed <- round(as.numeric(difftime(Sys.time(), batch_start, units = "secs")), 1)

cat(sprintf(
  "\n%s\n  BATCH COMPLETE  |  %d/%d succeeded  |  %d failed  |  %.1f s total\n%s\n",
  strrep("=", 72), n_ok, length(results), n_fail, elapsed, strrep("=", 72)
))

failures <- results[!sapply(results, `[[`, "ok")]

if (length(failures) > 0) {
  cat("Failure summary:\n")
  for (r in failures) {
    cat(sprintf("  [FAIL] %s\n         Dataset: %s x %s x %s\n         Error  : %s\n",
                r$file, r$country, r$source, r$dataset,
                if (is.na(r$error)) "(no message captured)" else r$error))
  }
  cat("\n")
} else {
  cat("Failure summary: none - every file completed the full pipeline.\n\n")
}

if (n_ok > 0) {
  cat("Succeeded:\n")
  for (r in results[sapply(results, `[[`, "ok")]) {
    cat(sprintf("  [OK]   %s  (%s x %s x %s)\n",
                r$file, r$country, r$source, r$dataset))
  }
  cat("\n")
}
