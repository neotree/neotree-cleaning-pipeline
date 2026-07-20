#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Pipeline 2: Subsample Maker  (standalone script)
# FILE:    run_subsample_maker.R
# PURPOSE: Create analysis-ready subsamples from Neotree data.
#
# TWO SOURCE MODES (set source_type in config):
#
#   source_type = "master"  (default, backward compatible)
#     Reads master_joined and master_joined_extended CSV files produced by
#     run_sample_maker.R.  Produces four output CSVs mirroring Pipeline 1 naming.
#     Use for analyses requiring both admission AND discharge data.
#
#   source_type = "cleaned"
#     Reads directly from cleaned files in the input/ folder.  Each enabled
#     dataset type (admissions, discharges, neolab, maternal) is processed
#     independently and produces one CSV per type.
#     Use when sharing a multi-dataset data package, or when working with
#     cleaned files before the join pipeline has been run.
#
# USAGE
#   For a new data access request:
#     1. Copy config_subsample_master_TEMPLATE.R  (master mode)
#        AND config_subsample_cleaned_TEMPLATE.R  (cleaned mode)
#     2. Rename both for the researcher and fill in date/facility/variables.
#     3. Run:
#          Rscript run_subsample_maker.R config_subsample_StudyName_Nvars.R
#          Rscript run_subsample_maker.R config_subsample_StudyName_cleaned.R
#     4. Write both to the SAME output_dir, then run run_subsample_user_dict.R.
#
#   For ad-hoc use:
#     From RStudio: edit the SUBSAMPLE_CONFIG block below, then Source.
#     From terminal:
#       Rscript run_subsample_maker.R
#       Rscript run_subsample_maker.R config_subsample_MyStudy.R
#
#   See README_files/README_run_subsample_maker.txt and
#   config_subsample_TEMPLATE.R for the full option reference.
#   Templates: config_subsample_master_TEMPLATE.R (master mode) and
#   config_subsample_cleaned_TEMPLATE.R (cleaned mode).
#
# OUTPUTS  (master mode — five files always; four na_coded files if output_na_coded = TRUE)
#   {prefix}_subsample_master_{label}.csv
#   {prefix}_subsample_master_extended_{label}.csv
#   {prefix}_subsample_master_matched_only_{label}.csv
#   {prefix}_subsample_master_extended_matched_only_{label}.csv
#   {prefix}_subsample_report_{label}.txt
#   [optional] *_na_coded.csv paired file for each of the four CSVs above
#
# OUTPUTS  (cleaned mode, one set per enabled dataset type)
#   {prefix}_subsample_admissions_{label}.csv + _report.txt
#   {prefix}_subsample_discharges_{label}.csv + _report.txt
#   {prefix}_subsample_neolab_{label}.csv     + _report.txt
#   {prefix}_subsample_maternal_{label}.csv   + _report.txt
#   [optional] *_na_coded.csv paired file for each enabled type
#
# ALL OUTPUTS default to: subsamples/ (next to this script).
# Override with output_dir in config.
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.2  (2026-05)
################################################################################

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Pipeline 2: Subsample Maker\n")
cat("================================================================\n\n")

# ==============================================================================
# SOURCE TOGGLE
# ==============================================================================
# Default: FALSE -- only database ("db") exports are used.  Database files are
# the authoritative source for all final DHS datasets.
# Set to TRUE to allow metabase ("mb") source files.  If FALSE and the config
# specifies source = "from_metabase", the script will stop with a clear error.
INCLUDE_METABASE <- FALSE

# ==============================================================================
# USER CONFIGURATION  <- edit this section, then Source / Rscript
# ==============================================================================
#
# OVERRIDE OPTIONS (without editing this block):
#
#   From RStudio:
#     source("config_subsample_MyStudy.R")          # sets SUBSAMPLE_CONFIG
#     source("run_subsample_maker.R")               # detects it, skips default
#
#   From terminal:
#     Rscript run_subsample_maker.R config_subsample_MyStudy.R
#

if (!exists("SUBSAMPLE_CONFIG")) {

SUBSAMPLE_CONFIG <- list(

  # --------------------------------------------------------------------------
  # SOURCE TYPE
  # "master"  -- subsample from master_joined / master_joined_extended files
  # "cleaned" -- subsample directly from cleaned files in input/
  # --------------------------------------------------------------------------
  source_type = "master",

  # --------------------------------------------------------------------------
  # MASTER SOURCE SETTINGS
  # --------------------------------------------------------------------------
  # Paths follow the run_all.R output convention:
  #   outputs/{country}_master/{source}/{PREFIX}_master_joined_{label}.csv
  master_joined_file          = "outputs/zim_master/from_database/ZIM_db_master_joined_to_YYYYMMDD.csv",
  master_joined_extended_file = "outputs/zim_master/from_database/ZIM_db_master_joined_extended_to_YYYYMMDD.csv",

  # --------------------------------------------------------------------------
  # CLEANED SOURCE SETTINGS
  # --------------------------------------------------------------------------
  cleaning_pipeline_output_dir = "input",
  country = "zim",
  source  = "from_database",

  # --------------------------------------------------------------------------
  # Output directory
  # NULL  -> "subsamples/" folder next to this script (both modes)
  # Override with an explicit path if needed (absolute or relative to script).
  # --------------------------------------------------------------------------
  output_dir = NULL,

  # --------------------------------------------------------------------------
  # GLOBAL DATE WINDOW  (all modes)
  # --------------------------------------------------------------------------
  sub_start_date = "2024-01-01",
  sub_end_date   = "2026-02-28",

  # --------------------------------------------------------------------------
  # FACILITY FILTER
  # --------------------------------------------------------------------------
  sub_facility_filter      = NULL,
  sub_use_advanced_mode    = FALSE,
  sub_facility_date_ranges = list(),

  # --------------------------------------------------------------------------
  # GLOBAL EXCLUSION FILTERS
  # --------------------------------------------------------------------------
  sub_exclusion_filters = list(),

  # --------------------------------------------------------------------------
  # GLOBAL COLUMN SELECTION
  # --------------------------------------------------------------------------
  sub_variables = NULL,

  # --------------------------------------------------------------------------
  # NA-CODED DUAL OUTPUT  (cleaned mode only)
  # FALSE -- write only the blank-NA subsample (default)
  # TRUE  -- also write a paired *_na_coded.csv using the same row filter
  # --------------------------------------------------------------------------
  output_na_coded = TRUE,

  # --------------------------------------------------------------------------
  # DATASET SETTINGS  (cleaned mode only)
  # --------------------------------------------------------------------------
  datasets = list(
    admissions = list(
      include               = TRUE,
      date_column           = "datetimeadmission",
      sub_variables         = NULL,
      sub_exclusion_filters = list()
    ),
    discharges = list(
      include               = FALSE,
      date_column           = NULL,
      sub_variables         = NULL,
      sub_exclusion_filters = list()
    ),
    neolab = list(
      include               = FALSE,
      date_column           = "datebct",
      sub_variables         = NULL,
      sub_exclusion_filters = list()
    ),
    maternal = list(
      include               = FALSE,
      date_column           = "dateadmission",
      sub_variables         = NULL,
      sub_exclusion_filters = list()
    )
  )

)

} # end if (!exists("SUBSAMPLE_CONFIG"))

# ==============================================================================
# EXTERNAL CONFIG OVERRIDE  (do not edit below this line)
# ==============================================================================

local({
  cfg_raw <- ""
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && nchar(trimws(args[1])) > 0) {
    cfg_raw <- trimws(args[1])
  } else if (exists("SUBSAMPLE_CONFIG_FILE", envir = .GlobalEnv)) {
    cfg_raw <- trimws(get("SUBSAMPLE_CONFIG_FILE", envir = .GlobalEnv))
    rm("SUBSAMPLE_CONFIG_FILE", envir = .GlobalEnv)
  }

  if (nchar(cfg_raw) == 0) return(invisible(NULL))

  cfg_path <- cfg_raw
  if (!file.exists(cfg_path)) cfg_path <- file.path(getwd(), cfg_raw)
  if (!file.exists(cfg_path)) {
    stop(sprintf(
      "External config file not found:\n  %s\n  Also tried: %s",
      cfg_raw, cfg_path
    ))
  }
  cat(sprintf("External config  : %s\n\n", normalizePath(cfg_path)))
  source(cfg_path, local = FALSE)
})

# ==============================================================================
# SCRIPT EXECUTION  -- do not edit below this line
# ==============================================================================

# Resolve script directory
script_dir <- tryCatch({
  script_args <- commandArgs(trailingOnly = FALSE)
  script_flag <- grep("--file=", script_args, value = TRUE)
  if (length(script_flag) > 0)
    dirname(normalizePath(sub("--file=", "", script_flag[1]), mustWork = FALSE))
  else
    NULL
}, error = function(e) NULL)

if (is.null(script_dir) || length(script_dir) == 0) {
  script_dir <- tryCatch(
    dirname(rstudioapi::getSourceEditorContext()$path),
    error = function(e) getwd()
  )
}
cat(sprintf("Script directory : %s\n\n", script_dir))

# Ensure source_type has a default (backward compatibility)
cfg <- SUBSAMPLE_CONFIG
if (is.null(cfg$source_type) || !nzchar(trimws(cfg$source_type))) {
  SUBSAMPLE_CONFIG$source_type <- "master"
  cfg <- SUBSAMPLE_CONFIG
}

cat(sprintf("Source type      : %s\n\n", cfg$source_type))

# Guard: block metabase source unless explicitly enabled
if (!is.null(cfg$source) && cfg$source == "from_metabase" && !INCLUDE_METABASE) {
  stop(paste(
    "Metabase source ('from_metabase') is not enabled.",
    "Set INCLUDE_METABASE <- TRUE at the top of run_subsample_maker.R to allow it.",
    "Database ('from_database') files should be used for all final DHS datasets."
  ))
}

# ==============================================================================
# BRANCH: MASTER MODE  (original behaviour, backward compatible)
# ==============================================================================

if (cfg$source_type == "master") {

  cat("================================================================\n")
  cat("  Mode: MASTER FILES\n")
  cat("================================================================\n\n")

  # Load required modules
  for (mod_name in c("subsample_maker.R", "data_profiler.R")) {
    mod_path <- file.path(script_dir, "modules", mod_name)
    if (!file.exists(mod_path))
      stop(sprintf("Module not found: modules/%s\n  Expected at: %s", mod_name, mod_path))
    source(mod_path)
  }
  cat("Modules loaded: subsample_maker.R, data_profiler.R\n\n")

  # Validate input files
  for (fld in c("master_joined_file", "master_joined_extended_file")) {
    path <- SUBSAMPLE_CONFIG[[fld]]
    if (is.null(path) || nchar(trimws(path)) == 0)
      stop(sprintf("SUBSAMPLE_CONFIG$%s is empty. Please set it to the file path.", fld))
    if (!file.exists(path)) {
      alt <- file.path(script_dir, path)
      if (file.exists(alt)) {
        SUBSAMPLE_CONFIG[[fld]] <- alt
      } else {
        stop(sprintf("Input file not found:\n  %s\n  Also tried: %s", path, alt))
      }
    }
  }

  # Resolve output directory (relative paths resolved from script directory)
  if (is.null(SUBSAMPLE_CONFIG$output_dir) || !nzchar(trimws(SUBSAMPLE_CONFIG$output_dir))) {
    SUBSAMPLE_CONFIG$output_dir <- file.path(script_dir, "subsamples")
  } else if (!grepl("^(/|~|[A-Za-z]:)", SUBSAMPLE_CONFIG$output_dir)) {
    SUBSAMPLE_CONFIG$output_dir <- file.path(script_dir, SUBSAMPLE_CONFIG$output_dir)
  }
  if (!dir.exists(SUBSAMPLE_CONFIG$output_dir))
    dir.create(SUBSAMPLE_CONFIG$output_dir, recursive = TRUE)

  # Derive file prefix from master_joined filename
  mj_base     <- tools::file_path_sans_ext(basename(SUBSAMPLE_CONFIG$master_joined_file))
  file_prefix <- strsplit(mj_base, "_master_joined")[[1]][1]

  cat(sprintf("Input  : %s\n", basename(SUBSAMPLE_CONFIG$master_joined_file)))
  cat(sprintf("         %s\n", basename(SUBSAMPLE_CONFIG$master_joined_extended_file)))
  cat(sprintf("Prefix : %s\n", file_prefix))
  cat(sprintf("Output : %s\n\n", normalizePath(SUBSAMPLE_CONFIG$output_dir, mustWork = FALSE)))

  # STEP 1 — Load master datasets
  cat("----------------------------------------------------------------\n")
  cat("STEP 1 -- Loading master datasets\n")
  cat("----------------------------------------------------------------\n")
  master_joined <- tryCatch(
    read.csv(SUBSAMPLE_CONFIG$master_joined_file,
             stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e)
      stop(sprintf("[load] Failed to read master_joined:\n  %s", conditionMessage(e)))
  )
  cat(sprintf("[load] master_joined          : %d rows x %d columns\n",
              nrow(master_joined), ncol(master_joined)))
  master_joined_extended <- tryCatch(
    read.csv(SUBSAMPLE_CONFIG$master_joined_extended_file,
             stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e)
      stop(sprintf("[load] Failed to read master_joined_extended:\n  %s", conditionMessage(e)))
  )
  cat(sprintf("[load] master_joined_extended : %d rows x %d columns\n\n",
              nrow(master_joined_extended), ncol(master_joined_extended)))

  # Optional: load NA-coded counterparts for dual output
  # Paths are auto-derived by inserting _na_coded before .csv
  master_joined_na_coded          <- NULL
  master_joined_extended_na_coded <- NULL
  if (isTRUE(SUBSAMPLE_CONFIG$output_na_coded)) {
    .load_na_coded <- function(blank_path, label) {
      nc_path <- sub("\\.csv$", "_na_coded.csv", blank_path)
      if (!file.exists(nc_path)) {
        cat(sprintf("[load] %s na_coded file not found — dual output skipped for master mode.\n",
                    label))
        cat(sprintf("       Expected: %s\n\n", basename(nc_path)))
        return(NULL)
      }
      df <- tryCatch(
        read.csv(nc_path, stringsAsFactors = FALSE, check.names = FALSE),
        error = function(e) {
          cat(sprintf("[load] Failed to read %s na_coded file: %s\n", label, conditionMessage(e)))
          NULL
        }
      )
      if (!is.null(df))
        cat(sprintf("[load] %-35s: %d rows x %d columns\n", paste0(label, "_na_coded"),
                    nrow(df), ncol(df)))
      df
    }
    master_joined_na_coded          <- .load_na_coded(SUBSAMPLE_CONFIG$master_joined_file,
                                                       "master_joined")
    master_joined_extended_na_coded <- .load_na_coded(SUBSAMPLE_CONFIG$master_joined_extended_file,
                                                       "master_joined_extended")
    cat("\n")
  }

  # STEP 2 — Run subsample maker
  cat("----------------------------------------------------------------\n")
  cat("STEP 2 -- Running subsample maker\n")
  cat("----------------------------------------------------------------\n")
  sub_result <- run_subsample_maker(
    master_joined          = master_joined,
    master_joined_extended = master_joined_extended,
    cfg                    = SUBSAMPLE_CONFIG
  )

  # STEP 3 — Write outputs
  cat("----------------------------------------------------------------\n")
  cat("STEP 3 -- Writing outputs\n")
  cat("----------------------------------------------------------------\n")

  # Build na_coded subsets if both source files loaded successfully.
  # Filtering in run_subsample_maker uses df[mask, ] throughout, which preserves
  # original rownames, so as.integer(rownames(...)) gives the source-file row
  # positions.  The na_coded files have the same rows in the same order.
  na_coded_pair <- NULL
  if (!is.null(master_joined_na_coded) && !is.null(master_joined_extended_na_coded)) {
    .nc_rows <- function(sub_df, nc_source) {
      idx <- as.integer(rownames(sub_df))
      nc_source[idx, , drop = FALSE]
    }
    na_coded_pair <- list(
      joined           = .nc_rows(sub_result$subsample_joined,
                                  master_joined_na_coded),
      extended         = .nc_rows(sub_result$subsample_joined_extended,
                                  master_joined_extended_na_coded),
      joined_matched   = .nc_rows(sub_result$subsample_joined_matched_only,
                                  master_joined_na_coded),
      extended_matched = .nc_rows(sub_result$subsample_joined_extended_matched_only,
                                  master_joined_extended_na_coded)
    )
  }

  output_paths <- write_subsample_outputs(
    sub_result  = sub_result,
    cfg         = SUBSAMPLE_CONFIG,
    prefix      = file_prefix,
    out_dir     = SUBSAMPLE_CONFIG$output_dir,
    na_coded    = na_coded_pair
  )

  # STEP 4 — Profile subsample
  cat("----------------------------------------------------------------\n")
  cat("STEP 4 -- Profiling subsample\n")
  cat("----------------------------------------------------------------\n")
  tryCatch({
    prof_dir <- file.path(SUBSAMPLE_CONFIG$output_dir, "profiles")
    if (!dir.exists(prof_dir)) dir.create(prof_dir, recursive = TRUE)
    profile_and_write(
      sub_result$subsample_joined,
      file.path(prof_dir, sprintf("%s_subsample_master_%s", file_prefix, sub_result$sub_label)),
      source_label = "subsample_master"
    )
    cat(sprintf("[profile] Profile written to: profiles/\n\n"))
  }, error = function(e) {
    cat(sprintf("[profile] WARNING: %s\n\n", conditionMessage(e)))
  })

  cat("================================================================\n")
  cat("  Subsample complete (master mode).\n")
  cat(sprintf("  Outputs written to: %s\n",
              normalizePath(SUBSAMPLE_CONFIG$output_dir, mustWork = FALSE)))
  cat("================================================================\n\n")

  invisible(output_paths)

# ==============================================================================
# BRANCH: CLEANED MODE  (new — one CSV per enabled dataset type)
# ==============================================================================

} else if (cfg$source_type == "cleaned") {

  cat("================================================================\n")
  cat("  Mode: CLEANED FILES\n")
  cat("================================================================\n\n")

  # Load required modules
  for (mod_name in c("pipeline_file_resolver.R", "subsample_maker_cleaned.R", "data_profiler.R")) {
    mod_path <- file.path(script_dir, "modules", mod_name)
    if (!file.exists(mod_path))
      stop(sprintf("Module not found: modules/%s\n  Expected at: %s", mod_name, mod_path))
    source(mod_path)
  }
  cat("Modules loaded: pipeline_file_resolver.R, subsample_maker_cleaned.R, data_profiler.R\n\n")

  # Resolve pipeline dir
  pipeline_dir <- cfg$cleaning_pipeline_output_dir
  if (is.null(pipeline_dir) || !nzchar(trimws(pipeline_dir)))
    stop("SUBSAMPLE_CONFIG$cleaning_pipeline_output_dir must be set in cleaned mode.")
  if (!dir.exists(pipeline_dir)) {
    alt <- file.path(script_dir, pipeline_dir)
    if (dir.exists(alt)) {
      pipeline_dir <- alt
    } else {
      stop(sprintf("Cleaning pipeline folder not found:\n  %s\n  Also tried: %s",
                   pipeline_dir, alt))
    }
  }
  cat(sprintf("Pipeline folder  : %s\n", normalizePath(pipeline_dir, mustWork = FALSE)))

  country    <- tolower(trimws(cfg$country))
  src_short  <- switch(cfg$source,
    from_database = "db", from_metabase = "mb",
    stop(sprintf("Unknown source: '%s'. Use 'from_database' or 'from_metabase'.", cfg$source))
  )
  prefix <- toupper(sprintf("%s_%s", country, src_short))  # e.g. ZIM_DB -> then normalise
  prefix <- paste0(toupper(country), "_", src_short)

  # Resolve output directory (relative paths resolved from script directory)
  out_dir <- cfg$output_dir
  if (is.null(out_dir) || !nzchar(trimws(out_dir))) {
    out_dir <- file.path(script_dir, "subsamples")
  } else if (!grepl("^(/|~|[A-Za-z]:)", out_dir)) {
    out_dir <- file.path(script_dir, out_dir)
  }
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  cat(sprintf("Output directory : %s\n\n", normalizePath(out_dir, mustWork = FALSE)))

  # Dataset type -> pipeline dataset_type name (for resolver)
  # Maternal type depends on country
  maternal_ds_type <- if (country == "mwi") "combined_maternity_outcomes"
                      else "maternal_outcomes"

  # Map of config key -> list(pipeline_type, mandatory_cols)
  MANDATORY <- list(
    admissions = c("uid", "facility", "uniquekey", "datetimeadmission"),
    discharges = c("uid", "facility", "uniquekey"),
    neolab     = c("uid", "facility", "uniquekey", "nuid", "datebct"),
    maternal   = c("uid", "facility", "uniquekey", "dateadmission")
  )
  PIPELINE_TYPE <- list(
    admissions = "admissions",
    discharges = "discharges",
    neolab     = "neolab",
    maternal   = maternal_ds_type
  )

  all_outputs <- list()
  run_summary <- list()

  # Profile output subfolder (created once, used by all enabled types)
  prof_dir <- file.path(out_dir, "profiles")
  if (!dir.exists(prof_dir)) dir.create(prof_dir, recursive = TRUE)

  datasets_cfg <- cfg$datasets
  if (is.null(datasets_cfg)) datasets_cfg <- list()

  enabled_types <- names(datasets_cfg)[
    sapply(datasets_cfg, function(d) isTRUE(d$include))
  ]

  if (length(enabled_types) == 0)
    stop("No dataset types enabled. Set include = TRUE for at least one type in cfg$datasets.")

  cat(sprintf("Enabled datasets : %s\n\n", paste(enabled_types, collapse = ", ")))

  # -- Process each enabled dataset type ----------------------------------------
  for (type in enabled_types) {

    cat("----------------------------------------------------------------\n")
    cat(sprintf("  Dataset: %s\n", type))
    cat("----------------------------------------------------------------\n")

    ds_cfg      <- datasets_cfg[[type]]
    ds_type     <- PIPELINE_TYPE[[type]]
    mandatory   <- MANDATORY[[type]]
    date_col    <- ds_cfg$date_column

    # Resolve file via pipeline resolver
    resolved <- tryCatch(
      resolve_pipeline_file(
        output_dir   = pipeline_dir,
        country      = country,
        source       = cfg$source,
        dataset_type = ds_type
      ),
      error = function(e) {
        cat(sprintf("[%s] SKIPPED: %s\n\n", type, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(resolved)) {
      run_summary[[type]] <- list(status = "SKIPPED - file not found", n = NA)
      next
    }
    cat(sprintf("[%s] Input: %s\n", type, basename(resolved)))

    # For neolab: check if nuid column is actually present (it may not be)
    # defer to after loading

    # Load
    df <- tryCatch(
      read.csv(resolved, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e)
        stop(sprintf("[%s] Failed to read file:\n  %s", type, conditionMessage(e)))
    )
    cat(sprintf("[%s] Loaded: %d rows x %d columns\n", type, nrow(df), ncol(df)))

    # For neolab: drop nuid from mandatory if not in file
    if (type == "neolab") {
      mandatory <- intersect(c("uid", "facility", "uniquekey", "datebct",
                               if ("nuid" %in% names(df)) "nuid" else NULL),
                             names(df))
    } else {
      mandatory <- intersect(mandatory, names(df))
    }

    # Run filtering
    result <- tryCatch(
      run_subsample_maker_cleaned(
        df            = df,
        mandatory_cols = mandatory,
        date_col      = date_col,
        cfg_global    = cfg,
        cfg_dataset   = ds_cfg
      ),
      error = function(e) {
        cat(sprintf("[%s] ERROR: %s\n\n", type, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(result)) {
      run_summary[[type]] <- list(status = "ERROR", n = NA)
      next
    }

    # Write blank-NA output
    tryCatch({
      paths <- write_subsample_outputs_cleaned(result, prefix, type, out_dir)
      all_outputs[[type]] <- paths
      run_summary[[type]] <- list(
        status = "OK",
        n      = result$n_final,
        label  = result$label,
        file   = basename(paths[["csv"]])
      )
    }, error = function(e) {
      cat(sprintf("[%s] Write error: %s\n", type, conditionMessage(e)))
      run_summary[[type]] <- list(status = "WRITE ERROR", n = NA)
    })

    # Optional: write paired NA-coded output (same rows, sentinel values for NA)
    if (isTRUE(cfg$output_na_coded) &&
        !is.null(run_summary[[type]]$status) &&
        run_summary[[type]]$status == "OK") {

      cat(sprintf("[%s] Resolving na_coded source file...\n", type))
      na_coded_resolved <- tryCatch(
        resolve_pipeline_file(
          output_dir   = pipeline_dir,
          country      = country,
          source       = cfg$source,
          dataset_type = ds_type,
          use_na_coded = TRUE
        ),
        error = function(e) {
          cat(sprintf("[%s] na_coded file not found — skipping _na_coded output.\n",
                      type))
          NULL
        }
      )

      if (!is.null(na_coded_resolved)) {
        cat(sprintf("[%s] na_coded input: %s\n", type, basename(na_coded_resolved)))
        na_coded_df <- tryCatch(
          read.csv(na_coded_resolved, stringsAsFactors = FALSE, check.names = FALSE),
          error = function(e) {
            cat(sprintf("[%s] Failed to read na_coded file: %s\n",
                        type, conditionMessage(e)))
            NULL
          }
        )
        if (!is.null(na_coded_df)) {
          # Extract the same rows that survived filtering in the blank-NA version.
          # R preserves original row numbers through df[keep, ] calls, so
          # as.integer(rownames(result$data)) gives the surviving row positions.
          kept_idx    <- as.integer(rownames(result$data))
          na_coded_sub <- na_coded_df[kept_idx, , drop = FALSE]
          tryCatch({
            na_paths <- write_subsample_outputs_cleaned(
              result, prefix, type, out_dir,
              na_coded_data = na_coded_sub
            )
            cat(sprintf("[%s] na_coded output: %s\n",
                        type, basename(na_paths[["csv_na_coded"]])))
          }, error = function(e) {
            cat(sprintf("[%s] na_coded write error: %s\n", type, conditionMessage(e)))
          })
        }
      }
    }

    # Profile the subsample
    if (!is.null(run_summary[[type]]$status) && run_summary[[type]]$status == "OK") {
      tryCatch(
        profile_and_write(
          result$data,
          file.path(prof_dir, sprintf("%s_subsample_%s_%s", prefix, type, result$label)),
          source_label = sprintf("%s subsample", type)
        ),
        error = function(e) cat(sprintf("[profile] WARNING (%s): %s\n", type, conditionMessage(e)))
      )
    }

    cat("\n")
  }

  # -- Batch summary -----------------------------------------------------------
  cat("================================================================\n")
  cat("  Subsample complete (cleaned mode).\n")
  cat(sprintf("  Outputs written to: %s\n",
              normalizePath(out_dir, mustWork = FALSE)))
  cat("----------------------------------------------------------------\n")
  cat(sprintf("  %-15s  %-8s  %-10s  %s\n", "Dataset", "Status", "Rows", "Output file"))
  cat(sprintf("  %-15s  %-8s  %-10s  %s\n",
              "---------------", "--------", "----------", "---------------"))
  for (type in names(run_summary)) {
    s <- run_summary[[type]]
    n_str   <- if (!is.na(s$n)) format(s$n, big.mark = ",") else "-"
    f_str   <- if (!is.null(s$file)) s$file else ""
    cat(sprintf("  %-15s  %-8s  %-10s  %s\n", type, s$status, n_str, f_str))
  }
  cat("================================================================\n\n")

  invisible(all_outputs)

} else {
  stop(sprintf(
    "Unknown source_type: '%s'. Set to 'master' or 'cleaned' in SUBSAMPLE_CONFIG.",
    cfg$source_type
  ))
}
