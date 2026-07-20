################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/file_finder.R
# PURPOSE: Locates admissions and discharges CSV files, supporting two modes:
#
#   MODE A -- Cleaning pipeline output (recommended)
#     Set CONFIG$cleaning_pipeline_output_dir to the cleaning pipeline output
#     directory.  The finder searches for subdirectories matching:
#       {country}_{src}_{type}_{date}/
#         {country}_{src}_{type}_{date}_cleaned.csv
#
#   MODE B -- Legacy cleaned_files/ hierarchy
#     Leave CONFIG$cleaning_pipeline_output_dir as NULL.
#     Files must be placed under:
#       cleaned_files/
#         {country}/
#           {source}/              e.g. from_database  or  from_metabase
#             {cleaning}/          e.g. Python_cleaned  or  R_cleaned
#               {country}_{src}_{type}_{date}_cleaned.csv
#
# In both modes, when multiple files match (several data cuts present), the
# most recently modified file is used and a warning is shown.
################################################################################

find_input_files <- function(cfg, script_dir = NULL) {

  # ---------------------------------------------------------------------------
  # MODE A: read directly from cleaning pipeline output directory
  # ---------------------------------------------------------------------------
  if (!is.null(cfg$cleaning_pipeline_output_dir)) {

    pipeline_dir <- cfg$cleaning_pipeline_output_dir

    # Resolve relative path against script_dir if the path doesn't exist as-is
    if (!is.null(script_dir) && !dir.exists(pipeline_dir)) {
      pipeline_dir <- file.path(script_dir, pipeline_dir)
    }

    if (!dir.exists(pipeline_dir)) {
      stop(sprintf(
        "[file_finder] cleaning_pipeline_output_dir not found:\n  %s\n",
        normalizePath(pipeline_dir, mustWork = FALSE)
      ))
    }

    # Validate source
    if (!cfg$source %in% c("from_database", "from_metabase")) {
      stop(sprintf(
        "[file_finder] CONFIG$source must be 'from_database' or 'from_metabase'; got '%s'",
        cfg$source
      ))
    }

    country_lower <- tolower(cfg$country)
    src_short     <- switch(cfg$source,
      from_database = "db",
      from_metabase = "mb"
    )

    # Inner helper: find one file type from the pipeline output structure
    find_from_pipeline <- function(type_label) {
      prefix           <- paste0(country_lower, "_", src_short, "_", type_label, "_")
      all_subdirs      <- list.dirs(pipeline_dir, full.names = TRUE, recursive = FALSE)
      matching_subdirs <- all_subdirs[
        grepl(paste0("^", prefix), basename(all_subdirs), ignore.case = TRUE)
      ]

      if (length(matching_subdirs) == 0) {
        stop(sprintf(
          "[file_finder] No directory matching '%s*' found in:\n  %s\n  Directories present:\n    %s",
          prefix,
          normalizePath(pipeline_dir, mustWork = FALSE),
          if (length(all_subdirs) == 0) "(none)"
          else paste(basename(all_subdirs), collapse = "\n    ")
        ))
      }

      candidates <- unlist(lapply(matching_subdirs, function(d) {
        list.files(d, pattern = "_cleaned\\.csv$", full.names = TRUE)
      }))
      candidates <- candidates[
        grepl(paste0("^", prefix), basename(candidates), ignore.case = TRUE)
      ]

      if (length(candidates) == 0) {
        stop(sprintf(
          "[file_finder] No *_cleaned.csv found in '%s*' directories in:\n  %s",
          prefix,
          normalizePath(pipeline_dir, mustWork = FALSE)
        ))
      }

      if (length(candidates) > 1) {
        chosen <- candidates[which.max(file.mtime(candidates))]
        warning(sprintf(
          "[file_finder] Multiple %s files found -- using the most recent:\n  %s\n  Others ignored:\n  %s",
          type_label,
          basename(chosen),
          paste(basename(candidates[candidates != chosen]), collapse = "\n  ")
        ))
        return(chosen)
      }

      return(candidates)
    }

    adm_path <- find_from_pipeline("admissions")
    dis_path <- find_from_pipeline("discharges")

    cat(sprintf("[file_finder] Mode            : cleaning pipeline output\n"))
    cat(sprintf("[file_finder] Pipeline dir    : %s\n",
                normalizePath(pipeline_dir, mustWork = FALSE)))
    cat(sprintf("[file_finder] Admissions file : %s\n", basename(adm_path)))
    cat(sprintf("[file_finder] Discharges file : %s\n\n", basename(dis_path)))

    return(list(
      admissions_path = adm_path,
      discharges_path = dis_path,
      target_dir      = pipeline_dir
    ))
  }

  # ---------------------------------------------------------------------------
  # MODE B: legacy cleaned_files/ directory hierarchy
  # ---------------------------------------------------------------------------

  # 0. Resolve the cleaned_files root
  if (!is.null(script_dir)) {
    cf_root <- file.path(script_dir, cfg$cleaned_files_dir)
  } else {
    cf_root <- cfg$cleaned_files_dir
  }

  if (!dir.exists(cf_root)) {
    stop(sprintf(
      "[file_finder] cleaned_files directory not found:\n  %s\n",
      normalizePath(cf_root, mustWork = FALSE)
    ))
  }

  # 1. Map CONFIG values to directory path components
  country_lower <- tolower(cfg$country)  # "zim" / "mwi"

  if (!cfg$source %in% c("from_database", "from_metabase")) {
    stop(sprintf(
      "[file_finder] CONFIG$source must be 'from_database' or 'from_metabase'; got '%s'",
      cfg$source
    ))
  }

  if (!cfg$cleaning %in% c("Python_cleaned", "R_cleaned")) {
    stop(sprintf(
      "[file_finder] CONFIG$cleaning must be 'Python_cleaned' or 'R_cleaned'; got '%s'",
      cfg$cleaning
    ))
  }

  target_dir <- file.path(cf_root, country_lower, cfg$source, cfg$cleaning)

  if (!dir.exists(target_dir)) {
    stop(sprintf(
      "[file_finder] Target directory does not exist:\n  %s\n  Check that country / source / cleaning values are correct and that data files have been placed here.",
      normalizePath(target_dir, mustWork = FALSE)
    ))
  }

  # 2. Short source code used in filenames: "db" or "mb"
  src_short <- switch(cfg$source,
    from_database = "db",
    from_metabase = "mb"
  )

  # 3. Helper: find one file for a given record type
  find_file <- function(type_label) {
    # Prefix pattern: e.g. "zim_db_admissions_"
    prefix  <- paste0(country_lower, "_", src_short, "_", type_label, "_")
    all_csv <- list.files(target_dir, pattern = "\\.csv$", full.names = TRUE)

    # Keep only files whose basename starts with the expected prefix
    matches <- all_csv[grepl(
      paste0("^", prefix),
      basename(all_csv),
      ignore.case = TRUE
    )]

    if (length(matches) == 0) {
      stop(sprintf(
        "[file_finder] No %s file found in:\n  %s\n  Expected a file starting with '%s'.\n  Files present: %s",
        type_label,
        normalizePath(target_dir, mustWork = FALSE),
        prefix,
        if (length(all_csv) == 0) "(none)" else paste(basename(all_csv), collapse = "\n    ")
      ))
    }

    if (length(matches) > 1) {
      # Multiple data cuts: use the most recently modified
      mtimes  <- file.mtime(matches)
      chosen  <- matches[which.max(mtimes)]
      warning(sprintf(
        "[file_finder] Multiple %s files found -- using the most recent:\n  %s\n  Others ignored:\n  %s",
        type_label,
        basename(chosen),
        paste(basename(matches[matches != chosen]), collapse = "\n  ")
      ))
      return(chosen)
    }

    return(matches)
  }

  # 4. Locate admissions and discharges files
  adm_path <- find_file("admissions")
  dis_path <- find_file("discharges")

  cat(sprintf("[file_finder] Mode            : cleaned_files/ hierarchy\n"))
  cat(sprintf("[file_finder] Admissions file : %s\n", basename(adm_path)))
  cat(sprintf("[file_finder] Discharges file : %s\n\n", basename(dis_path)))

  list(
    admissions_path = adm_path,
    discharges_path = dis_path,
    target_dir      = target_dir
  )
}
