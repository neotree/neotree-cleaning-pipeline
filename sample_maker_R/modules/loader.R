################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/loader.R
# PURPOSE: Load admissions and discharges CSV files and perform basic structural
#          validation (required columns present, non-empty, etc.).
#
# REQUIRED COLUMNS
#   Admissions : uid, facility, datetimeadmission
#   Discharges : uid, facility
#
# EXPORTED FUNCTIONS
#   load_data(admissions_path, discharges_path)
#     -> list(admissions, discharges, n_adm_raw, n_dis_raw)
#
#   load_na_coded_data(admissions_path, discharges_path)
#     -> list(adm_na_coded, dis_na_coded)
#        Derives na_coded file paths by replacing "_cleaned.csv" with
#        "_cleaned_na_coded.csv".  Returns NULL for each component if the
#        corresponding file does not exist (no error).
################################################################################

REQUIRED_ADM_COLS <- c("uid", "facility", "datetimeadmission")
REQUIRED_DIS_COLS <- c("uid", "facility")

# ------------------------------------------------------------------------------
# load_data()
# Reads both CSV files; returns a named list with admissions and discharges
# data frames plus raw row counts for reporting.
# ------------------------------------------------------------------------------
load_data <- function(admissions_path, discharges_path) {

  cat("[loader] Loading admissions...\n")
  admissions <- .read_csv_safe(admissions_path, "admissions")
  .validate_columns(admissions, REQUIRED_ADM_COLS, "admissions")
  cat(sprintf(
    "[loader]   %d records, %d columns loaded from: %s\n",
    nrow(admissions), ncol(admissions), basename(admissions_path)
  ))

  cat("[loader] Loading discharges...\n")
  discharges <- .read_csv_safe(discharges_path, "discharges")
  .validate_columns(discharges, REQUIRED_DIS_COLS, "discharges")
  cat(sprintf(
    "[loader]   %d records, %d columns loaded from: %s\n\n",
    nrow(discharges), ncol(discharges), basename(discharges_path)
  ))

  list(
    admissions     = admissions,
    discharges     = discharges,
    n_adm_raw      = nrow(admissions),
    n_dis_raw      = nrow(discharges)
  )
}

# ------------------------------------------------------------------------------
# load_na_coded_data()
# Locates and loads the *_cleaned_na_coded.csv counterparts of the standard
# admissions and discharges files.  Returns NULL for each component silently
# if the file is absent so the pipeline degrades gracefully.
# ------------------------------------------------------------------------------
load_na_coded_data <- function(admissions_path, discharges_path) {

  .load_one_nc <- function(std_path, label) {
    nc_path <- sub("_cleaned\\.csv$", "_cleaned_na_coded.csv", std_path,
                   ignore.case = TRUE)
    if (!file.exists(nc_path)) {
      cat(sprintf("[loader]   na_coded %s not found -- skipped (%s)\n",
                  label, basename(nc_path)))
      return(NULL)
    }
    df <- tryCatch(
      read.csv(nc_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) {
        cat(sprintf("[loader]   WARNING: could not read na_coded %s: %s\n",
                    label, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(df))
      cat(sprintf("[loader]   na_coded %-12s: %d rows  (%s)\n",
                  label, nrow(df), basename(nc_path)))
    df
  }

  cat("[loader] Loading na_coded source files...\n")
  adm_nc <- .load_one_nc(admissions_path, "admissions")
  dis_nc <- .load_one_nc(discharges_path, "discharges")
  cat("\n")

  list(adm_na_coded = adm_nc, dis_na_coded = dis_nc)
}

# ------------------------------------------------------------------------------
# Internal helpers (not exported -- prefix with dot)
# ------------------------------------------------------------------------------

.read_csv_safe <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf(
      "[loader] %s file not found:\n  %s",
      label, normalizePath(path, mustWork = FALSE)
    ))
  }
  df <- tryCatch(
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) stop(sprintf(
      "[loader] Failed to read %s file '%s':\n  %s",
      label, basename(path), conditionMessage(e)
    ))
  )
  if (nrow(df) == 0) {
    stop(sprintf("[loader] %s file is empty: %s", label, basename(path)))
  }
  df
}

.validate_columns <- function(df, required, label) {
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "[loader] Required column(s) missing from %s file: %s\n  Available columns (first 30): %s",
      label,
      paste(missing_cols, collapse = ", "),
      paste(head(names(df), 30), collapse = ", ")
    ))
  }
}
