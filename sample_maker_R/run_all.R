#!/usr/bin/env Rscript

# =============================================================================
# NEOTREE SAMPLE MAKER -- Batch Runner
# FILE:    run_all.R
# =============================================================================
# PURPOSE:
#   Scans the input/ folder, auto-detects every cleaned dataset whose
#   directory name matches the standard Neotree naming convention, and runs
#   the appropriate sample-maker pipeline for each.
#
# DIRECTORY NAMING CONVENTION  (matches cleaning pipeline output):
#   {country}_{source}_{dataset}_{date}/
#     {country}_{source}_{dataset}_{date}_cleaned.csv
#
#   country  : mwi  (Malawi)  |  zim  (Zimbabwe)
#   source   : db   (PostgreSQL export)  |  mb  (Metabase export)
#   dataset  : admissions | discharges
#              (neolab, maternal, and all other types are skipped here;
#               use run_subsample_maker.R to process those datasets)
#   date     : YYYYMMDD  |  YYYY-MM-DD
#
# WHAT THIS SCRIPT DOES:
#   For each unique (country, source) group that has BOTH admissions AND
#   discharges in input/ -> runs the full join pipeline (dedup, join,
#   probabilistic matching) to build the master datasets.
#   All other dataset types (neolab, maternal, PHC, etc.) are logged and
#   skipped.  Use run_subsample_maker.R in cleaned mode to process them.
#
# USAGE:
#   From RStudio: open this file and click "Source"
#   From the terminal:
#     Rscript run_all.R
#
# CONFIGURATION:
#   Global settings (date window, probabilistic matching thresholds,
#   plausibility ranges) are read from config_sample_maker.R.
#   Edit that file to change shared parameters.
#   To process only a subset of files, set RUN_ALL_FILTER or RUN_ALL_SKIP.
#
# SOURCE:
#   Both database ("db") and metabase ("mb") files are processed.  The join
#   pipeline is source-agnostic — it processes whichever admissions+discharges
#   pairs it finds.  Source filtering belongs in the subsample maker.
#
# OUTPUTS  (written to outputs/):
#   outputs/{COUNTRY}_{SRC}/
#     {prefix}_master_joined_{label}.csv
#     {prefix}_master_joined_extended_{label}.csv
#     {prefix}_joined_admissions_discharges_{label}.csv
#     {prefix}_unmatched_admissions_{label}.csv / _discharges_{label}.csv
#     {prefix}_prob_match_assignments_{label}.csv
#     {prefix}_matching_statistics_{label}.txt
#     {prefix}_prob_matching_report_{label}.txt
#     profiles/  (variable profiles for cleaned inputs and master datasets)
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.4  (2026-05)
# =============================================================================

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Batch Runner\n")
cat("================================================================\n\n")

# =============================================================================
# OPTIONAL FILTERS  -  Edit if you only want to process a subset of directories
# =============================================================================

# Regex applied to the directory basename. Leave as NULL to process everything.
# Examples:
#   "^zim_"    -- Zimbabwe files only
#   "^mwi_db_" -- Malawi database files only
RUN_ALL_FILTER <- NULL

# Exact directory names (basenames) to skip entirely.
# Example: c("mwi_mb_combined_maternity_outcomes_2026-05-01")
RUN_ALL_SKIP <- character(0)

# =============================================================================
# DATASET ROUTING TABLE
# =============================================================================

# These form admissions+discharges pairs -> full join pipeline
JOIN_DATASETS     <- c("admissions", "discharges")

# Known datasets that the sample maker deliberately skips.
# Neolab, maternal, and all other standalone types are handled by the
# subsample maker (run_subsample_maker.R), not this script.
SKIP_DATASETS     <- c(
  "neolab",
  "maternal_outcomes", "combined_maternity_outcomes",
  "phc_admissions", "phc_discharges",
  "baseline", "infections", "twenty_8_day_follow_up",
  "dhis2_maternal_outcomes", "maternity_completeness",
  "joined_admissions_discharges"
)

# =============================================================================
# RESOLVE PATHS
# =============================================================================

script_dir <- tryCatch({
  dirname(normalizePath(commandArgs(trailingOnly = FALSE)[
    grep("--file=", commandArgs(trailingOnly = FALSE))
  ]))
}, error = function(e) NULL)

if (is.null(script_dir) || length(script_dir) == 0) {
  script_dir <- tryCatch(
    dirname(rstudioapi::getSourceEditorContext()$path),
    error = function(e) getwd()
  )
}

cat(sprintf("Script directory : %s\n", script_dir))

# =============================================================================
# LOAD SHARED CONFIG
# =============================================================================

config_path <- file.path(script_dir, "config_sample_maker.R")
if (!file.exists(config_path)) {
  stop(sprintf("Config not found: %s", config_path))
}
source(config_path)

cat(sprintf("Config loaded from: %s\n\n", basename(config_path)))

# Resolve input/output dirs from config (relative paths are resolved against
# script_dir; absolute paths are used as-is)
raw_input <- CONFIG$cleaning_pipeline_output_dir
INPUT_DIR <- if (!is.null(raw_input) && nchar(raw_input) > 0 && !grepl("^(/|[A-Za-z]:)", raw_input)) {
  normalizePath(file.path(script_dir, raw_input), mustWork = FALSE)
} else {
  normalizePath(raw_input, mustWork = FALSE)
}

OUTPUT_DIR <- file.path(script_dir, "outputs")

if (!dir.exists(INPUT_DIR)) {
  stop(sprintf(
    "input/ directory not found:\n  %s\n  Check cleaning_pipeline_output_dir in config_sample_maker.R.",
    INPUT_DIR
  ))
}
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

cat(sprintf("Input directory  : %s\n", INPUT_DIR))
cat(sprintf("Output directory : %s\n\n", OUTPUT_DIR))

CONFIG$cleaning_pipeline_output_dir <- INPUT_DIR
CONFIG$output_dir                   <- OUTPUT_DIR

# =============================================================================
# LOAD ALL MODULES
# =============================================================================

modules_dir <- file.path(script_dir, "modules")

for (mod in c(
  "pipeline_file_resolver.R",
  "file_finder.R", "loader.R", "filter_data.R",
  "deduplicator.R",
  "joiner.R", "prob_matcher.R", "master_builder.R", "output_writer.R",
  "data_profiler.R"
)) {
  mod_path <- file.path(modules_dir, mod)
  if (!file.exists(mod_path)) stop(sprintf("Module not found: %s", mod_path))
  source(mod_path)
}
cat("All modules loaded.\n\n")

# =============================================================================
# HELPER: Parse an input/ subdirectory name into pipeline parameters
# =============================================================================

parse_input_subdir <- function(dname) {
  # Pattern: {country}_{src}_{dataset}_{date}
  # Date: 12 digits (YYYYMMDDHHMM), 8 digits (YYYYMMDD), or YYYY-MM-DD; case-insensitive
  pattern <- "^(mwi|zim)_(db|mb)_(.+)_(\\d{12}|\\d{8}|\\d{4}-\\d{2}-\\d{2})$"
  m <- regmatches(dname, regexec(pattern, dname, ignore.case = TRUE))[[1]]
  if (length(m) == 0) return(NULL)

  country   <- tolower(m[2])
  src_short <- tolower(m[3])
  dataset   <- tolower(m[4])

  list(
    country     = country,
    src_short   = src_short,
    dataset     = dataset,
    source_long = switch(src_short, db = "from_database", mb = "from_metabase"),
    dir_name    = dname
  )
}

# =============================================================================
# DISCOVER AND PARSE INPUT SUBDIRECTORIES
# =============================================================================

all_subdirs <- basename(list.dirs(INPUT_DIR, full.names = FALSE, recursive = FALSE))

if (length(all_subdirs) == 0) {
  stop(sprintf("No subdirectories found in input/. Nothing to do.\n  %s", INPUT_DIR))
}

# Apply user filter
if (!is.null(RUN_ALL_FILTER)) {
  all_subdirs <- all_subdirs[grepl(RUN_ALL_FILTER, all_subdirs,
                                   perl = TRUE, ignore.case = TRUE)]
}
# Apply skip list
if (length(RUN_ALL_SKIP) > 0) {
  all_subdirs <- all_subdirs[!all_subdirs %in% RUN_ALL_SKIP]
}

parsed_dirs    <- Filter(Negate(is.null), lapply(all_subdirs, parse_input_subdir))
unparsed_dirs  <- all_subdirs[sapply(all_subdirs, function(d) is.null(parse_input_subdir(d)))]

# =============================================================================
# BUILD RUN PLAN
# =============================================================================

join_runs     <- list()  # list of list(country, src_short, source_long)
skipped_known <- list()  # deliberately skipped dataset types
unknown_dirs  <- unparsed_dirs  # didn't match naming convention

# Group directories by (country, src_short) to find admissions+discharges pairs
group_keys <- unique(sapply(parsed_dirs, function(p) paste(p$country, p$src_short)))

for (gk in group_keys) {
  parts     <- strsplit(gk, " ")[[1]]
  country   <- parts[1]
  src_short <- parts[2]
  group_p   <- Filter(function(p) p$country == country && p$src_short == src_short,
                      parsed_dirs)
  datasets  <- unique(sapply(group_p, `[[`, "dataset"))

  if (all(c("admissions", "discharges") %in% datasets)) {
    join_runs <- c(join_runs, list(list(
      country     = country,
      src_short   = src_short,
      source_long = switch(src_short, db = "from_database", mb = "from_metabase")
    )))
  }
}

# Route individual datasets — only JOIN_DATASETS are processed here.
# Everything else (neolab, maternal, PHC, etc.) is handled downstream
# by the subsample maker (run_subsample_maker.R).
for (p in parsed_dirs) {
  if (p$dataset %in% JOIN_DATASETS) {
    next  # handled above as pairs
  } else if (p$dataset %in% SKIP_DATASETS) {
    skipped_known <- c(skipped_known, list(p))
  } else {
    skipped_known <- c(skipped_known, list(p))  # unrecognised but parsed
  }
}

# =============================================================================
# PRINT RUN PLAN
# =============================================================================

total_runs <- length(join_runs)

cat(sprintf(
  "=== Run plan ===\n  Join pipelines (admissions + discharges) : %d\n  Skipped (handled by subsample maker)     : %d\n  Skipped (name does not match convention) : %d\n  Total pipeline runs                      : %d\n\n",
  length(join_runs),
  length(skipped_known), length(unknown_dirs), total_runs
))

if (length(join_runs) > 0) {
  cat("Join pipeline runs:\n")
  for (jr in join_runs) {
    cat(sprintf("  [JOIN    ] %s x %s\n", toupper(jr$country), jr$source_long))
  }
  cat("\n")
}
if (length(skipped_known) > 0) {
  cat("Skipped (handled by subsample maker -- run_subsample_maker.R):\n")
  for (s in skipped_known) {
    cat(sprintf("  [SKIP    ] %s  (dataset: %s)\n", s$dir_name, s$dataset))
  }
  cat("\n")
}
if (length(unknown_dirs) > 0) {
  cat("Skipped (directory name does not match naming convention):\n")
  for (d in unknown_dirs) cat(sprintf("  [UNKNOWN ] %s\n", d))
  cat("\n")
}

if (total_runs == 0) {
  cat("Nothing to process. Exiting.\n")
  quit(status = 0)
}

# =============================================================================
# PROFILE ALL CLEANED INPUT FILES
# Runs before any pipeline processing.  Every CSV in the input/ folder gets
# a variable profile, including dataset types that the sample maker skips
# (PHC, baseline, DHIS2, etc.).  Profiles are written to:
#   input/{subdir}/profiles/{filename}_variable_profile.csv
#                           {filename}_variable_profile.txt
# =============================================================================

cat(sprintf("%s\n  Profiling all cleaned input files\n%s\n",
    strrep("-", 72), strrep("-", 72)))

all_input_csvs <- list.files(INPUT_DIR, pattern = "\\.csv$",
                              full.names = TRUE, recursive = TRUE,
                              ignore.case = TRUE)

# Exclude files already inside a profiles/ subfolder (avoids double-profiling
# the _variable_profile.csv outputs from a previous run).
all_input_csvs <- all_input_csvs[
  !grepl(paste0(.Platform$file.sep, "profiles", .Platform$file.sep),
         all_input_csvs, fixed = TRUE) &
  !grepl("_variable_profile\\.csv$", all_input_csvs, ignore.case = TRUE)
]

display_input_dir <- CONFIG$cleaning_pipeline_output_dir
if (length(all_input_csvs) == 0) {
  cat(sprintf("  No CSV files found in %s\n\n", display_input_dir))
} else {
  cat(sprintf("  Found %d CSV file(s) in %s\n\n", length(all_input_csvs), display_input_dir))
  for (csv_path in all_input_csvs) {
    tryCatch({
      df_in    <- read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
      # Profiles go in a profiles/ subfolder alongside each CSV
      prof_sub <- file.path(dirname(csv_path), "profiles")
      if (!dir.exists(prof_sub)) dir.create(prof_sub, recursive = TRUE)
      base_no_ext <- tools::file_path_sans_ext(basename(csv_path))
      suppressWarnings(profile_and_write(
        df_in,
        file.path(prof_sub, base_no_ext),
        source_label = basename(csv_path)
      ))
    }, error = function(e) {
      cat(sprintf("  [profile] WARNING (%s): %s\n", basename(csv_path), conditionMessage(e)))
    })
  }
  cat("\n")
}

# =============================================================================
# RUN JOIN PIPELINES
# =============================================================================

batch_start   <- Sys.time()
batch_results <- list()

for (jr in join_runs) {

  label <- sprintf("%s x %s (join)", toupper(jr$country), jr$source_long)
  cat(sprintf(
    "\n%s\n[JOIN] %s\n%s\n",
    strrep("=", 72), label, strrep("=", 72)
  ))

  run_ok <- tryCatch({

    # Build per-run config from shared CONFIG
    run_cfg             <- CONFIG
    run_cfg$country     <- jr$country
    run_cfg$source      <- jr$source_long
    run_cfg$cleaning_pipeline_output_dir <- INPUT_DIR

    # STEP 1 -- Find input files
    cat("STEP 1  -- Locating input files\n")
    file_info  <- find_input_files(run_cfg, script_dir = script_dir)

    # STEP 2 -- Load data
    cat("STEP 2  -- Loading data\n")
    load_result <- load_data(file_info$admissions_path, file_info$discharges_path)
    admissions  <- load_result$admissions
    discharges  <- load_result$discharges

    # STEP 2b -- Load na_coded source files (only when output_na_coded = TRUE)
    adm_na_coded <- NULL
    dis_na_coded <- NULL
    if (isTRUE(run_cfg$output_na_coded)) {
      cat("STEP 2b -- Loading na_coded source files\n")
      nc_result    <- load_na_coded_data(file_info$admissions_path,
                                         file_info$discharges_path)
      adm_na_coded <- nc_result$adm_na_coded
      dis_na_coded <- nc_result$dis_na_coded
      if (is.null(adm_na_coded) || is.null(dis_na_coded)) {
        cat("         [na_coded] One or both na_coded source files missing --",
            "na_coded master output will be skipped.\n\n")
        adm_na_coded <- NULL
        dis_na_coded <- NULL
      }
    }

    # STEP 3 -- Parse admission dates
    cat("STEP 3  -- Parsing admission dates\n")
    admissions <- parse_admission_dates(admissions)

    # STEP 4 -- Resolve date window
    cat("STEP 4  -- Resolving date window\n")
    date_window <- resolve_date_window(admissions, run_cfg)

    # STEP 5 -- Filter admissions
    cat("STEP 5  -- Filtering admissions\n")
    filter_result  <- apply_admission_filter(admissions, date_window, run_cfg)
    admissions     <- filter_result$admissions
    varfilt_result <- list(n_excluded_varfilt = 0L, var_filter_desc = NULL)

    # STEP 6 -- Deduplicate
    cat("STEP 6  -- Deduplicating\n")
    adm_dedup  <- resolve_duplicates(admissions, "ADMISSIONS")
    admissions <- adm_dedup$df
    dis_dedup  <- resolve_duplicates(discharges, "DISCHARGES")
    discharges <- dis_dedup$df

    # STEP 7 -- Join
    cat("STEP 7  -- Joining admissions to discharges\n")
    join_result <- join_data(admissions, discharges)

    # STEP 8 -- Build master_joined
    cat("STEP 8  -- Building master_joined\n")
    master_joined <- build_master_joined(
      matched_pairs = join_result$matched_pairs,
      unmatched_adm = join_result$unmatched_adm
    )

    # STEP 9 -- Detect probabilistic matching variables
    cat("STEP 9  -- Detecting probabilistic matching variables\n")
    var_info <- detect_match_variables(
      adm_full = load_result$admissions,
      dis_full = load_result$discharges,
      cfg      = run_cfg
    )

    # STEP 10 -- Probabilistic matching
    cat("STEP 10 -- Probabilistic matching\n")
    prob_candidates  <- find_prob_candidates(
      unmatched_adm = join_result$unmatched_adm,
      unmatched_dis = join_result$unmatched_dis,
      var_info      = var_info,
      cfg           = run_cfg
    )
    prob_assignments <- assign_one_to_one(prob_candidates)

    # STEP 11 -- Build master_joined_extended
    cat("STEP 11 -- Building master_joined_extended\n")
    master_joined_extended <- build_master_joined_extended(
      master_joined    = master_joined,
      assignments      = prob_assignments,
      unmatched_adm_df = join_result$unmatched_adm,
      unmatched_dis_df = join_result$unmatched_dis
    )

    # STEP 12 -- Write outputs
    cat("STEP 12 -- Writing outputs\n")
    pipeline_state <- list(
      admissions_path        = file_info$admissions_path,
      discharges_path        = file_info$discharges_path,
      n_adm_raw              = load_result$n_adm_raw,
      n_dis_raw              = load_result$n_dis_raw,
      admissions_full        = load_result$admissions,
      discharges_full        = load_result$discharges,
      date_window            = date_window,
      filter_result          = filter_result,
      varfilt_result         = varfilt_result,
      adm_dedup              = adm_dedup,
      dis_dedup              = dis_dedup,
      join_result            = join_result,
      var_info               = var_info,
      prob_candidates        = prob_candidates,
      prob_assignments       = prob_assignments,
      master_joined          = master_joined,
      master_joined_extended = master_joined_extended,
      adm_na_coded           = adm_na_coded,   # NULL unless output_na_coded = TRUE
      dis_na_coded           = dis_na_coded    # NULL unless output_na_coded = TRUE
    )
    out_paths <- write_outputs(run_cfg, pipeline_state)

    # STEP 13 -- Profile cleaned inputs and master datasets
    cat("STEP 13 -- Profiling cleaned inputs and master datasets\n")
    tryCatch({
      prof_dir <- file.path(dirname(out_paths$master_joined), "profiles")
      if (!dir.exists(prof_dir)) dir.create(prof_dir, recursive = TRUE)
      mj_base     <- tools::file_path_sans_ext(basename(out_paths$master_joined))
      prof_prefix <- sub("_master_joined.*$", "", mj_base)
      prof_label  <- sub(paste0("^", prof_prefix, "_master_joined_?"), "", mj_base)
      if (!nchar(prof_label)) prof_label <- format(Sys.Date(), "%Y%m%d")
      profile_and_write(load_result$admissions, file.path(prof_dir,
        sprintf("%s_cleaned_admissions_%s", prof_prefix, prof_label)),
        source_label = "admissions (cleaned input)")
      profile_and_write(load_result$discharges, file.path(prof_dir,
        sprintf("%s_cleaned_discharges_%s", prof_prefix, prof_label)),
        source_label = "discharges (cleaned input)")
      profile_and_write(master_joined, file.path(prof_dir,
        sprintf("%s_master_joined_%s", prof_prefix, prof_label)),
        source_label = "master_joined")
      profile_and_write(master_joined_extended, file.path(prof_dir,
        sprintf("%s_master_joined_extended_%s", prof_prefix, prof_label)),
        source_label = "master_joined_extended")
      cat(sprintf("[profile] Profiles written to: profiles/\n"))
    }, error = function(e) {
      cat(sprintf("[profile] WARNING: profiling failed: %s\n", conditionMessage(e)))
    })

    TRUE

  }, error = function(e) {
    cat(sprintf("\n  [ERROR] %s\n\n", conditionMessage(e)))
    FALSE
  })

  batch_results <- c(batch_results, list(list(label = label, ok = run_ok)))
}

# =============================================================================
# BATCH SUMMARY
# =============================================================================

n_ok    <- sum(sapply(batch_results, `[[`, "ok"))
n_fail  <- length(batch_results) - n_ok
elapsed <- round(as.numeric(difftime(Sys.time(), batch_start, units = "secs")), 1)

cat(sprintf(
  "\n%s\n  BATCH COMPLETE  |  %d/%d succeeded  |  %d failed  |  %.1f s total\n%s\n",
  strrep("=", 72), n_ok, length(batch_results), n_fail, elapsed, strrep("=", 72)
))

if (n_fail > 0) {
  cat("Failed:\n")
  for (r in batch_results[!sapply(batch_results, `[[`, "ok")]) {
    cat(sprintf("  [FAIL] %s\n", r$label))
  }
  cat("\n")
}

if (n_ok > 0) {
  cat("Succeeded:\n")
  for (r in batch_results[sapply(batch_results, `[[`, "ok")]) {
    cat(sprintf("  [OK]   %s\n", r$label))
  }
  cat("\n")
}

invisible(batch_results)
