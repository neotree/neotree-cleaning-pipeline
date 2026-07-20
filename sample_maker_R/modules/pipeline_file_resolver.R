################################################################################
# Neotree Sample Maker -- Shared Helper: Pipeline File Resolver
# FILE:    modules/pipeline_file_resolver.R
# PURPOSE: Resolves the path to a cleaned CSV file from the cleaning pipeline
#          output directory, given country, source, and dataset type.
#
# The cleaning pipeline outputs to this flat structure:
#
#   {output_dir}/
#     {country}_{src}_{dataset_type}_{date}/
#       {country}_{src}_{dataset_type}_{date}_cleaned.csv
#       {country}_{src}_{dataset_type}_{date}_cleaned_na_coded.csv
#       {country}_{src}_{dataset_type}_{date}_cleaned.rds
#       ... (reports, logs, etc.)
#
# This module is used by:
#   - modules/file_finder.R        (admissions + discharges for sample_maker)
#   - run_subsample_maker_maternal.R  (maternal outcomes file)
#   - run_subsample_maker_neolab.R    (neolab file)
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.2  (2026-05)
################################################################################

resolve_pipeline_file <- function(output_dir, country, source, dataset_type,
                                  use_na_coded = FALSE) {

  # ---------------------------------------------------------------------------
  # 1. Map source label to the short code used in filenames ("db" / "mb")
  # ---------------------------------------------------------------------------
  src_short <- switch(source,
    from_database = "db",
    from_metabase = "mb",
    stop(sprintf(
      "[pipeline_file_resolver] source must be 'from_database' or 'from_metabase'; got '%s'",
      source
    ))
  )

  country_lower <- tolower(country)
  prefix        <- paste0(country_lower, "_", src_short, "_", dataset_type, "_")

  # ---------------------------------------------------------------------------
  # 2. Validate the output directory
  # ---------------------------------------------------------------------------
  if (!dir.exists(output_dir)) {
    stop(sprintf(
      "[pipeline_file_resolver] Cleaning pipeline output directory not found:\n  %s",
      normalizePath(output_dir, mustWork = FALSE)
    ))
  }

  # ---------------------------------------------------------------------------
  # 3. Find subdirectories whose names start with the expected prefix
  # ---------------------------------------------------------------------------
  all_subdirs      <- list.dirs(output_dir, full.names = TRUE, recursive = FALSE)
  matching_subdirs <- all_subdirs[
    grepl(paste0("^", prefix), basename(all_subdirs), ignore.case = TRUE)
  ]

  if (length(matching_subdirs) == 0) {
    stop(sprintf(
      "[pipeline_file_resolver] No directory found matching '%s*' in:\n  %s\n  Directories present:\n    %s",
      prefix,
      normalizePath(output_dir, mustWork = FALSE),
      if (length(all_subdirs) == 0) "(none)"
      else paste(basename(all_subdirs), collapse = "\n    ")
    ))
  }

  # ---------------------------------------------------------------------------
  # 4. Find the appropriate cleaned CSV inside those subdirectories.
  #    Two file variants exist per dataset:
  #      *_cleaned.csv          -- NA represented as blank (default)
  #      *_cleaned_na_coded.csv -- NA represented as numeric sentinel (-7/-9)
  #    use_na_coded selects which variant to resolve.
  # ---------------------------------------------------------------------------
  file_pattern <- if (isTRUE(use_na_coded)) "_cleaned_na_coded\\.csv$"
                  else                       "_cleaned\\.csv$"

  candidates <- unlist(lapply(matching_subdirs, function(d) {
    list.files(d, pattern = file_pattern, full.names = TRUE)
  }))

  # When resolving the blank-NA variant, explicitly drop any _na_coded files
  # that also end in _cleaned.csv (defensive guard for unusual naming).
  if (!isTRUE(use_na_coded)) {
    candidates <- candidates[
      !grepl("_cleaned_na_coded\\.csv$", candidates, ignore.case = TRUE)
    ]
  }

  # Further restrict: CSV basename must also start with the expected prefix
  candidates <- candidates[
    grepl(paste0("^", prefix), basename(candidates), ignore.case = TRUE)
  ]

  variant_label <- if (isTRUE(use_na_coded)) "*_cleaned_na_coded.csv" else "*_cleaned.csv"
  if (length(candidates) == 0) {
    stop(sprintf(
      "[pipeline_file_resolver] No %s found in '%s*' directories in:\n  %s",
      variant_label,
      prefix,
      normalizePath(output_dir, mustWork = FALSE)
    ))
  }

  # ---------------------------------------------------------------------------
  # 5. Multiple data cuts: use the most recently modified file
  # ---------------------------------------------------------------------------
  if (length(candidates) > 1) {
    chosen <- candidates[which.max(file.mtime(candidates))]
    warning(sprintf(
      "[pipeline_file_resolver] Multiple '%s' files found -- using the most recent:\n  %s\n  Others ignored:\n  %s",
      dataset_type,
      basename(chosen),
      paste(basename(candidates[candidates != chosen]), collapse = "\n  ")
    ))
    return(chosen)
  }

  return(candidates)
}
