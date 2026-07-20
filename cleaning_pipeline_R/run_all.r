# =============================================================================
# NEOTREE CLEANING PIPELINE -- Batch Runner
# =============================================================================
# PURPOSE:
#   Scans the input/ folder, auto-detects every CSV file whose name matches
#   the standard Neotree naming convention, derives all pipeline parameters
#   from the filename, and runs the full cleaning pipeline for each file.
#
# FILE NAMING CONVENTION:
#   {country}_{source}_{dataset}_{date}.csv
#
#   country  : mwi  (Malawi)  |  zim  (Zimbabwe)
#   source   : db   (direct PostgreSQL export)  |  mb  (Metabase export)
#   dataset  : admissions | discharges | maternal_outcomes | phc_admissions |
#              phc_discharges | combined_maternity_outcomes | neolab |
#              baseline | infections | twenty_8_day_follow_up | ...
#   date     : YYYYMMDD  (database)  |  YYYY-MM-DD  (metabase)
#
# EXAMPLES:
#   mwi_db_admissions_20260501.csv
#   zim_mb_maternal_outcomes_2026-05-01.csv
#   zim_db_twenty_8_day_follow_up_20260501.csv
#
# USAGE:
#   Rscript run_all.r
#   # or interactively in RStudio:
#   source("run_all.r")
#
# CONFIGURATION:
#   To process only a subset of files, set RUN_ALL_FILTER below.
#   To skip specific files, add filename stems to RUN_ALL_SKIP.
#   Everything else is auto-derived.
# =============================================================================

# =============================================================================
# OPTIONAL FILTERS  -  Edit if you only want to process a subset of files
# =============================================================================

# -----------------------------------------------------------------------------
# Run-from-anywhere: anchor the working directory to the pipeline root (this
# file's own folder) so every relative path below resolves regardless of where
# the script was launched (Rscript, source(), RStudio "Source", R console).
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

# Regex applied to the full filename (basename, no path). Leave as NULL to
# process every matching file.
# Example: "^zim_" to process Zimbabwe files only
#          "admissions|discharges" to process only those two dataset types
RUN_ALL_FILTER <- NULL

# Character vector of exact filenames (basename) to skip.
# Example: c("mwi_mb_combined_maternity_outcomes_2026-05-01.csv")
RUN_ALL_SKIP <- character(0)

# =============================================================================
# INTERNAL SETUP
# =============================================================================

INPUT_DIR  <- "input"
OUTPUT_DIR <- "output"

# Known valid datasets (must match VALID_DATASETS in 00_setup.r)
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
#   data_source  : "database" or "metabase"
#   dataset      : one of KNOWN_DATASETS
#   csv_filepath : relative path (e.g. "input/zim_db_admissions_20260501.csv")
# Returns NULL if the filename does not match the expected pattern.

parse_input_filename <- function(fname) {
  bname <- basename(fname)

  # Pattern: {country}_{source}_{dataset}_{date}.csv
  # Date is: 8 digits (YYYYMMDD), 12 digits (YYYYMMDDHHMM from PostgreSQL script),
  # or YYYY-MM-DD (Metabase export).
  pattern <- "^(mwi|zim)_(db|mb)_(.+)_(\\d{12}|\\d{8}|\\d{4}-\\d{2}-\\d{2})\\.csv$"
  m <- regmatches(bname, regexec(pattern, bname, ignore.case = TRUE))[[1]]

  if (length(m) == 0) return(NULL) # does not match

  country_raw <- tolower(m[2])
  source_raw  <- tolower(m[3])
  dataset_raw <- tolower(m[4])

  country     <- switch(country_raw, mwi = "MWI", zim = "ZIM", NULL)
  data_source <- switch(source_raw,  db  = "database", mb = "metabase", NULL)

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
  # Data frames passed between modules
  "df_raw", "df_raw_deidentified", "df_std",
  "df_shifted", "df_merged", "df_dict", "df_filled",
  "df_num_filled", "df_dropped", "df_auto", "df_typed",
  "df_deduped", "df_num", "df_bool", "df_cat", "df_dt",
  "df_clean", "df_harmonised", "df_na_coded",
  # Timing
  "pipeline_start",
  # helpers defined in 00_setup.r
  "cols_of_type"
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
  run_ok <- tryCatch({
    source("run_pipeline.r")
    TRUE
  }, error = function(e) {
    cat(sprintf("\n  [ERROR] Pipeline failed for %s:\n  %s\n\n",
                p$csv_filepath, conditionMessage(e)))
    FALSE
  })

  results <- c(results, list(list(
    file    = p$csv_filepath,
    country = p$country,
    dataset = p$dataset,
    source  = p$data_source,
    ok      = run_ok
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

if (n_fail > 0) {
  cat("Failed files:\n")
  for (r in results[!sapply(results, `[[`, "ok")]) {
    cat(sprintf("  [FAIL] %s  (%s x %s x %s)\n",
                r$file, r$country, r$source, r$dataset))
  }
  cat("\n")
}

if (n_ok > 0) {
  cat("Succeeded:\n")
  for (r in results[sapply(results, `[[`, "ok")]) {
    cat(sprintf("  [OK]   %s  (%s x %s x %s)\n",
                r$file, r$country, r$source, r$dataset))
  }
  cat("\n")
}
