#!/usr/bin/env Rscript

################################################################################
# Neotree Sample Maker -- Anonymizer  (standalone script)
# FILE:    run_anonymizer.R
# PURPOSE: Remove or replace identifying variables from any pipeline output CSV
#          (master_joined, master_joined_extended, subsample files, etc.),
#          producing de-identified datasets safe for sharing or archiving.
#
# USAGE
#   From RStudio: open and click "Source"
#   From the terminal:
#     Rscript run_anonymizer.R
#
# CONFIGURATION
#   Edit the two sections marked below:
#     SECTION A -- which files to anonymize
#     SECTION B -- which variables to remove (beyond the built-in defaults)
#
# OUTPUTS  (written to output_dir, or same folder as input files)
#   {original_filename}_anon.csv   (one per input file)
#   anonymization_report.txt
#
# Author:  David de Lorenzo, UCL GOS ICH
# Version: 1.0  (2026-04)
################################################################################

cat("\n")
cat("================================================================\n")
cat("  Neotree Sample Maker -- Anonymizer\n")
cat("================================================================\n\n")

# ==============================================================================
# SECTION A -- INPUT FILES AND OUTPUT SETTINGS   <- edit this section
# ==============================================================================
#
# List every file you want to anonymize.  You can mix master files, subsample
# files, or any other pipeline CSV.  Each entry becomes one _anon.csv output.
# Use relative paths (resolved from this script's directory) or absolute paths.
#
ANONYMIZER_CONFIG <- list(

  input_files = c(
    "outputs/zim_master/from_metabase/R_cleaned/ZIM_mb_r_master_joined_to_20260228.csv",
    "outputs/zim_master/from_metabase/R_cleaned/ZIM_mb_r_master_joined_extended_to_20260228.csv"
  ),

  # Output directory.
  # NULL  -> each _anon.csv goes to the same folder as its source file.
  # Or specify a single folder for all outputs: "outputs/zim_master/anonymized"
  output_dir = NULL,

  # Add a sequential anonymous row ID column (anon_id: 1, 2, 3, ...) to the
  # output.  Useful for referencing specific records in analysis without any
  # patient-linkable identifier.
  add_anon_id = TRUE,

  # Convert exact datetime columns to year-month strings (e.g. "2024-03").
  # FALSE (default) -- datetimeadmission and datetimedischarge are kept as-is.
  # TRUE            -- both are replaced by adm_yearmonth and dis_yearmonth.
  # Use TRUE when sharing data externally; FALSE when exact dates are needed
  # for internal analyses (e.g. length-of-stay calculations).
  convert_datetimes = FALSE,

# ==============================================================================
# SECTION B -- VARIABLES TO REMOVE   <- add or remove entries as needed
# ==============================================================================
#
# The module always removes a built-in set of direct identifiers:
#   uid, uniquekey, match_key, adm_date_parsed
# and converts exact datetimes to year-month:
#   datetimeadmission  ->  adm_yearmonth   (e.g. "2024-03")
#   datetimedischarge  ->  dis_yearmonth
#
# Use additional_remove to remove any further columns from YOUR data that
# are not in the built-in list above.  Common candidates are listed below --
# uncomment any you want to remove, or add your own column names.
#
  additional_remove = c(

    # --- Administrative / data-entry columns --------------------------------
    # "deviceid",          # tablet or device identifier
    # "hcwid",             # healthcare worker identifier
    # "submissionid",      # form submission ID
    # "instanceid",        # ODK/KoboToolbox instance identifier

    # --- Mother identifiers -------------------------------------------------
    # "motherid",
    # "mothername",
    # "motherphone",

    # --- Any other columns you wish to exclude ------------------------------
    # "columnname"

    NULL   # <- keep this NULL as the last entry so the list is always valid
  )

)

# ==============================================================================
# SCRIPT EXECUTION  -- do not edit below this line
# ==============================================================================

# Resolve script directory
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

cat(sprintf("Script directory : %s\n\n", script_dir))

# Load module
mod_path <- file.path(script_dir, "modules", "anonymizer.R")
if (!file.exists(mod_path)) {
  stop(sprintf("Module not found: modules/anonymizer.R\n  Expected at: %s", mod_path))
}
source(mod_path)
cat("Module loaded: modules/anonymizer.R\n\n")

# Validate and resolve input file paths
input_files <- ANONYMIZER_CONFIG$input_files
if (is.null(input_files) || length(input_files) == 0) {
  stop("ANONYMIZER_CONFIG$input_files is empty. Add at least one file path.")
}

resolved_files <- character(length(input_files))
for (i in seq_along(input_files)) {
  path <- input_files[i]
  if (!file.exists(path)) {
    alt <- file.path(script_dir, path)
    if (file.exists(alt)) {
      resolved_files[i] <- alt
    } else {
      stop(sprintf("Input file not found:\n  %s\n  Also tried: %s", path, alt))
    }
  } else {
    resolved_files[i] <- path
  }
}

# ==============================================================================
# STEP 1 -- Load, anonymize, and collect results
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 1 -- Loading and anonymizing files\n")
cat("----------------------------------------------------------------\n\n")

results_list <- list()

for (i in seq_along(resolved_files)) {
  path  <- resolved_files[i]
  stem  <- tools::file_path_sans_ext(basename(path))

  cat(sprintf("[load] Reading %s...\n", basename(path)))
  df <- tryCatch(
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) stop(sprintf("[load] Failed to read '%s':\n  %s",
                                     basename(path), conditionMessage(e)))
  )
  cat(sprintf("[load]   %d rows x %d columns\n", nrow(df), ncol(df)))

  result <- anonymize_dataset(df, ANONYMIZER_CONFIG)
  results_list[[stem]] <- result

  cat(sprintf("[anonymizer] Columns removed : %s\n",
              paste(result$removed, collapse = ", ")))
  cat(sprintf("[anonymizer] Dates converted : %s\n",
              if (length(result$converted) > 0)
                paste(result$converted, collapse = "; ")
              else "(none)"))
  if (length(result$added) > 0)
    cat(sprintf("[anonymizer] Columns added   : %s\n", paste(result$added, collapse = ", ")))
  cat(sprintf("[anonymizer] Result          : %d rows x %d columns\n\n",
              result$n_rows, result$n_cols_after))
}

# ==============================================================================
# STEP 2 -- Write outputs
# ==============================================================================
cat("----------------------------------------------------------------\n")
cat("STEP 2 -- Writing outputs\n")
cat("----------------------------------------------------------------\n")

# Resolve output directory
if (is.null(ANONYMIZER_CONFIG$output_dir)) {
  # Write each file to the same directory as its source
  for (i in seq_along(resolved_files)) {
    stem     <- names(results_list)[i]
    out_dir  <- dirname(resolved_files[i])
    out_path <- file.path(out_dir, paste0(stem, "_anon.csv"))
    write.csv(results_list[[stem]]$df, out_path, row.names = FALSE)
    cat(sprintf("[anonymizer] Written : %s\n", basename(out_path)))
  }
  # Report goes to the directory of the first input file
  report_dir <- dirname(resolved_files[1])
} else {
  out_dir <- ANONYMIZER_CONFIG$output_dir
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  for (stem in names(results_list)) {
    out_path <- file.path(out_dir, paste0(stem, "_anon.csv"))
    write.csv(results_list[[stem]]$df, out_path, row.names = FALSE)
    cat(sprintf("[anonymizer] Written : %s\n", basename(out_path)))
  }
  report_dir <- out_dir
}

# Write report
report_path  <- file.path(report_dir, "anonymization_report.txt")
report_lines <- .build_anon_report(results_list, ANONYMIZER_CONFIG,
  setNames(
    lapply(names(results_list), function(s) {
      d <- if (is.null(ANONYMIZER_CONFIG$output_dir)) dirname(resolved_files[which(names(results_list) == s)]) else ANONYMIZER_CONFIG$output_dir
      file.path(d, paste0(s, "_anon.csv"))
    }),
    names(results_list)
  )
)
writeLines(report_lines, report_path)
cat(sprintf("[anonymizer] Report  : %s\n\n", basename(report_path)))

# ==============================================================================
# DONE
# ==============================================================================
cat("================================================================\n")
cat("  Anonymization complete.\n")
cat(sprintf("  %d file(s) processed.\n", length(results_list)))
cat("================================================================\n\n")

invisible(results_list)
