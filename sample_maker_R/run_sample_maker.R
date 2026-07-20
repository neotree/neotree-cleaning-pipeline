#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    run_sample_maker.R
# PURPOSE: Main orchestration script.  Sources config.R and all modules, then
#          runs the full pipeline in sequence.
#
# USAGE
#   From within RStudio: open this file and click "Source"
#   From the command line:
#     Rscript run_sample_maker.R
#   With an explicit config path:
#     Rscript run_sample_maker.R /path/to/config.R
#
# PIPELINE STEPS
#   0.  Load configuration (config_sample_maker.R)
#   1.  Find input files   (modules/file_finder.R)
#   2.  Load data          (modules/loader.R)
#   3.  Parse dates        (modules/filter_data.R)
#   4.  Resolve date window (auto one-month-in-arrears or manual)
#   5.  Filter admissions by date window (modules/filter_data.R)
#   6.  Deduplicate        (modules/deduplicator.R)
#   7.  Join               (modules/joiner.R)
#   8.  Build master_joined           (modules/master_builder.R)
#   9.  Detect prob matching variables (modules/prob_matcher.R)
#   10. Probabilistic matching         (modules/prob_matcher.R)
#   11. Build master_joined_extended   (modules/master_builder.R)
#   12. Write outputs      (modules/output_writer.R)
#
# For facility/variable filtering and column selection, use run_subsample_maker.R
#
# OUTPUTS  (written to outputs/{country}/{source}/{cleaning}/)
#   {prefix}_joined_admissions_discharges_{label}.csv
#   {prefix}_unmatched_admissions_{label}.csv
#   {prefix}_unmatched_discharges_{label}.csv
#   {prefix}_matching_statistics_{label}.txt
#   {prefix}_duplicates_log.csv   (only when duplicates are found)
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-04)
################################################################################

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Module 01: Join Admissions/Discharges\n")
cat("================================================================\n\n")

# ==============================================================================
# 0.  Resolve paths and load configuration
# ==============================================================================

# Determine the directory containing this script so relative paths in config.R
# and the modules/ folder are resolved correctly regardless of working directory.
script_dir <- tryCatch({
  # Works when run via Rscript
  dirname(normalizePath(commandArgs(trailingOnly = FALSE)[
    grep("--file=", commandArgs(trailingOnly = FALSE))
  ]))
}, error = function(e) NULL)

# Fallback: use the active RStudio source file path, or finally getwd()
if (is.null(script_dir) || length(script_dir) == 0) {
  script_dir <- tryCatch(
    dirname(rstudioapi::getSourceEditorContext()$path),
    error = function(e) getwd()
  )
}

cat(sprintf("Script directory : %s\n\n", script_dir))

# Allow an explicit config path as a command-line argument
args <- commandArgs(trailingOnly = TRUE)
config_path <- if (length(args) >= 1 && nchar(args[1]) > 0) {
  args[1]
} else {
  # Look for config_sample_maker.R first; fall back to config.R for backwards compatibility
  preferred <- file.path(script_dir, "config_sample_maker.R")
  if (file.exists(preferred)) preferred else file.path(script_dir, "config.R")
}

if (!file.exists(config_path)) {
  stop(sprintf(
    "Config file not found at: %s\n  Expected 'config_sample_maker.R' alongside run_sample_maker.R, or pass a custom path as an argument.",
    config_path
  ))
}

source(config_path)
cat(sprintf("Configuration loaded from: %s\n\n", basename(config_path)))

# ==============================================================================
# 1.  Load modules
# ==============================================================================

modules_dir <- file.path(script_dir, "modules")

for (mod in c("file_finder.R", "loader.R", "filter_data.R",
              "deduplicator.R", "joiner.R",
              "prob_matcher.R", "master_builder.R",
              "output_writer.R", "data_profiler.R")) {
  mod_path <- file.path(modules_dir, mod)
  if (!file.exists(mod_path)) {
    stop(sprintf("Module not found: %s\n  Expected at: %s", mod, mod_path))
  }
  source(mod_path)
}
cat("All modules loaded.\n\n")

# ==============================================================================
# STEP 1 -- Find input files
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 1 -- Locating input files\n")
cat("----------------------------------------------------------------\n")

file_info <- find_input_files(CONFIG, script_dir = script_dir)

# ==============================================================================
# STEP 2 -- Load data
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 2 -- Loading data\n")
cat("----------------------------------------------------------------\n")

load_result <- load_data(file_info$admissions_path, file_info$discharges_path)
admissions  <- load_result$admissions
discharges  <- load_result$discharges

# ==============================================================================
# STEP 3 -- Parse admission dates
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 3 -- Parsing admission dates\n")
cat("----------------------------------------------------------------\n")

admissions <- parse_admission_dates(admissions)
cat("\n")

# ==============================================================================
# STEP 4 -- Resolve the admission date window
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 4 -- Resolving admission date window\n")
cat("----------------------------------------------------------------\n")

date_window <- resolve_date_window(admissions, CONFIG)
cat("\n")

# ==============================================================================
# STEP 5 -- Filter admissions by date window
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 5 -- Filtering admissions by date window\n")
cat("----------------------------------------------------------------\n")

filter_result <- apply_admission_filter(admissions, date_window, CONFIG)
admissions    <- filter_result$admissions

# Variable filter is not part of the master dataset pipeline.
# For sub-population filtering, use run_subsample_maker.R.
varfilt_result <- list(n_excluded_varfilt = 0L, var_filter_desc = NULL)

# ==============================================================================
# STEP 6 -- Deduplicate
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 6 -- Deduplication\n")
cat("----------------------------------------------------------------\n")

adm_dedup  <- resolve_duplicates(admissions, "ADMISSIONS")
admissions <- adm_dedup$df

dis_dedup  <- resolve_duplicates(discharges, "DISCHARGES")
discharges <- dis_dedup$df

cat("\n")

# ==============================================================================
# STEP 7 -- Join
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 7 -- Joining admissions to discharges\n")
cat("----------------------------------------------------------------\n")

join_result <- join_data(admissions, discharges)

# ==============================================================================
# STEP 8 -- Build master_joined
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 8 -- Building master_joined\n")
cat("----------------------------------------------------------------\n")

master_joined <- build_master_joined(
  matched_pairs = join_result$matched_pairs,
  unmatched_adm = join_result$unmatched_adm
)

# ==============================================================================
# STEP 9 -- Detect probabilistic matching variables
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 9 -- Detecting probabilistic matching variables\n")
cat("----------------------------------------------------------------\n")

# Use the full (pre-filter) admissions and discharges for variable completeness
# assessment, so that completeness estimates aren't distorted by small subsets.
var_info <- detect_match_variables(
  adm_full = load_result$admissions,
  dis_full = load_result$discharges,
  cfg      = CONFIG
)

# ==============================================================================
# STEP 10 -- Find probabilistic candidates & assign one-to-one
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 10 -- Probabilistic matching (unmatched admissions -> unmatched discharges)\n")
cat("----------------------------------------------------------------\n")

prob_candidates <- find_prob_candidates(
  unmatched_adm = join_result$unmatched_adm,
  unmatched_dis = join_result$unmatched_dis,
  var_info      = var_info,
  cfg           = CONFIG
)

prob_assignments <- assign_one_to_one(prob_candidates)

# ==============================================================================
# STEP 11 -- Build master_joined_extended
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 11 -- Building master_joined_extended\n")
cat("----------------------------------------------------------------\n")

master_joined_extended <- build_master_joined_extended(
  master_joined     = master_joined,
  assignments       = prob_assignments,
  unmatched_adm_df  = join_result$unmatched_adm,
  unmatched_dis_df  = join_result$unmatched_dis
)

# ==============================================================================
# STEP 12 -- Write outputs
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 12 -- Writing outputs\n")
cat("----------------------------------------------------------------\n")

# Assemble the pipeline state object that output_writer needs
pipeline_state <- list(
  # File paths (for reporting)
  admissions_path = file_info$admissions_path,
  discharges_path = file_info$discharges_path,
  # Raw counts (before any filtering)
  n_adm_raw       = load_result$n_adm_raw,
  n_dis_raw       = load_result$n_dis_raw,
  # Full loaded data (for variable completeness reporting)
  admissions_full = load_result$admissions,
  discharges_full = load_result$discharges,
  # Intermediate results
  date_window     = date_window,
  filter_result   = filter_result,
  varfilt_result  = varfilt_result,
  adm_dedup       = adm_dedup,
  dis_dedup       = dis_dedup,
  # Direct join result
  join_result     = join_result,
  # Probabilistic matching
  var_info            = var_info,
  prob_candidates     = prob_candidates,
  prob_assignments    = prob_assignments,
  # Master datasets
  master_joined           = master_joined,
  master_joined_extended  = master_joined_extended
)

output_paths <- write_outputs(CONFIG, pipeline_state)

# ==============================================================================
# STEP 13 -- Profile cleaned inputs and master datasets
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 13 -- Profiling cleaned inputs and master datasets\n")
cat("----------------------------------------------------------------\n")

prof_dir <- file.path(dirname(output_paths$master_joined), "profiles")
if (!dir.exists(prof_dir)) dir.create(prof_dir, recursive = TRUE)

# Derive prefix and label from the master_joined filename
mj_base     <- tools::file_path_sans_ext(basename(output_paths$master_joined))
prof_prefix <- sub("_master_joined.*$", "", mj_base)
prof_label  <- sub(paste0("^", prof_prefix, "_master_joined_?"), "", mj_base)
if (!nchar(prof_label)) prof_label <- format(Sys.Date(), "%Y%m%d")

profile_and_write(
  load_result$admissions,
  file.path(prof_dir, sprintf("%s_cleaned_admissions_%s", prof_prefix, prof_label)),
  source_label = "admissions (cleaned input)"
)
profile_and_write(
  load_result$discharges,
  file.path(prof_dir, sprintf("%s_cleaned_discharges_%s", prof_prefix, prof_label)),
  source_label = "discharges (cleaned input)"
)
profile_and_write(
  master_joined,
  file.path(prof_dir, sprintf("%s_master_joined_%s", prof_prefix, prof_label)),
  source_label = "master_joined"
)
profile_and_write(
  master_joined_extended,
  file.path(prof_dir, sprintf("%s_master_joined_extended_%s", prof_prefix, prof_label)),
  source_label = "master_joined_extended"
)
cat(sprintf("[profile] Profiles written to: profiles/\n\n"))

# ==============================================================================
# DONE
# ==============================================================================
cat("================================================================\n")
cat("  Pipeline complete.\n")
cat(sprintf("  Outputs written to: %s\n",
    normalizePath(dirname(output_paths$joined), mustWork = FALSE)))
cat("================================================================\n\n")

# Return output paths invisibly (useful when sourced from another script)
invisible(output_paths)
