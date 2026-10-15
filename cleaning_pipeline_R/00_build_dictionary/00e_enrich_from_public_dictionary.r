# =============================================================================
# NEOTREE CLEANING PIPELINE -- PRE-PIPELINE SETUP SCRIPT  (documentation step)
# Module 00e: Enrich Data Dictionary from the Public Data Dictionary
# =============================================================================
#
# PURPOSE:
#   Adds documentation columns to the Variables sheet of each dictionary
#   workbook by cross-referencing the public data dictionary.  The ValueMaps
#   sheet and every column used by the cleaning pipeline are left untouched.
#
#   Each output is built from the base dictionary.  The four columns written by
#   00c_enrich_dictionary_from_scripts.r are carried over from an existing
#   dictionary_*_enriched.xlsx only when that file is not older than the base
#   dictionary and lists the same variables in the same order.  Otherwise they
#   are left out and a message says so.
#
# METHOD:
#   Each dictionary variable (question_key / harmonised_variable_name) is matched
#   case-insensitively against a single index built from all public-dictionary
#   sheets, keyed by current variable name and by old variable name.  The first
#   entry registered for a key wins.  Columns written:
#
#     public_meaning       -- plain-language "Variable meaning"
#     public_data_type     -- data type as documented in the public dictionary
#     public_dependency    -- skip-logic / dependency described in words
#     public_range         -- documented plausible range (reference only)
#     old_variable_name    -- old variable name, when it differs from the current one
#     timeline_of_change   -- "Timeline of change" text from the public dictionary
#     public_reference     -- source reference cited in the public dictionary
#     public_dict_matched  -- TRUE if a public-dictionary entry was found
#
# INPUTS:
#   og_dictionaries/Public_data_dictionary_2024.xlsx
#   dictionaries/dictionary_*.xlsx
#   dictionaries/dictionary_*_enriched.xlsx, for the 00c columns only, when it
#   exists and OVERWRITE_IN_PLACE is FALSE.
#
# OUTPUTS:
#   dictionaries/dictionary_*_enriched.xlsx (OVERWRITE_IN_PLACE = FALSE), or the
#   base dictionary_*.xlsx files overwritten in place (OVERWRITE_IN_PLACE = TRUE).
#
# USAGE:
#   Run after 00_build_dictionary.r and 00c_enrich_dictionary_from_scripts.r.
#   # From the pipeline root (cleaning_pipeline_R/):
#   source("00_build_dictionary/00e_enrich_from_public_dictionary.r")
#   # or:
#   Rscript 00_build_dictionary/00e_enrich_from_public_dictionary.r
#   Uses base R, readxl and openxlsx; does not load the cleaning pipeline.
# =============================================================================

# -----------------------------------------------------------------------------
# Run-from-anywhere: anchor to the pipeline root (this file lives in
# 00_build_dictionary/, so root is one level up).
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
setwd(normalizePath(file.path(.nt_get_script_dir(), ".."), mustWork = FALSE))

# -- USER CONFIG ---------------------------------------------------------------
# TRUE  => overwrite the base dictionary_*.xlsx files in place.
# FALSE => write to dictionary_*_enriched.xlsx, built from the base dictionary
#          plus the 00c columns of a current enriched copy.
OVERWRITE_IN_PLACE <- FALSE

DICT_DIR   <- "dictionaries"
PUBLIC_DICT <- "og_dictionaries/Public_data_dictionary_2024.xlsx"
PUBLIC_SHEETS <- c("Admission", "Zim_Discharge", "Malawi_Discharge",
                   "Malawi PHC_Admission", "Malawi PHC_Discharge",
                   "Maternal outcome", "NeoLab")
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(readxl)   # read the messy public-dictionary layout
  library(openxlsx) # loadWorkbook(), read.xlsx(), writeData(), saveWorkbook()
})

NEW_COLS <- c("public_meaning", "public_data_type", "public_dependency",
              "public_range", "old_variable_name", "timeline_of_change",
              "public_reference", "public_dict_matched")

if (!file.exists(PUBLIC_DICT))
  stop(sprintf("Public dictionary not found: %s", PUBLIC_DICT))

# -----------------------------------------------------------------------------
# 1. Parse the public dictionary into per-variable records.
#    Layout (1-indexed cols): 3=Variable name, 4=Variable meaning, 5=option
#    label, 6=option code, 7=Data type, 8=Dependency, 9=Range, 10=Old variable
#    name, 11=Timeline of change, 13=Reference.  A variable "starts" on a row
#    with a non-empty col 3; option rows below it have an empty col 3.
# -----------------------------------------------------------------------------
parse_public_sheet <- function(sheet) {
  d <- suppressMessages(read_excel(PUBLIC_DICT, sheet = sheet, col_names = FALSE))
  d <- as.data.frame(lapply(d, as.character), stringsAsFactors = FALSE)
  nc <- ncol(d)
  gc <- function(r, i) if (i <= nc) { v <- d[r, i]; if (is.na(v)) "" else trimws(v) } else ""
  recs <- list(); cur <- NULL
  for (r in seq_len(nrow(d))) {
    vname <- gc(r, 3)
    if (nzchar(vname)) {
      if (!is.null(cur)) recs[[length(recs) + 1L]] <- cur
      cur <- list(
        var = vname, meaning = gc(r, 4), dtype = gc(r, 7),
        dependency = gc(r, 8), range = gc(r, 9), old = gc(r, 10),
        timeline = gc(r, 11), reference = gc(r, 13)
      )
    }
  }
  if (!is.null(cur)) recs[[length(recs) + 1L]] <- cur
  recs
}

pub_recs <- unlist(
  lapply(PUBLIC_SHEETS, function(s)
    tryCatch(parse_public_sheet(s), error = function(e) list())),
  recursive = FALSE)

# Global index: lowercased current name AND old name -> record (first wins).
pub_index <- new.env(parent = emptyenv())
add_key <- function(k, rec) {
  k <- tolower(trimws(k))
  if (nzchar(k) && is.null(pub_index[[k]])) assign(k, rec, envir = pub_index)
}
for (rec in pub_recs) { add_key(rec$var, rec); if (nzchar(rec$old)) add_key(rec$old, rec) }
message(sprintf("[00e] Public dictionary parsed: %d variable entries, %d unique keys.",
                length(pub_recs), length(ls(pub_index))))

lookup <- function(...) {
  for (k in c(...)) {
    if (is.na(k) || !nzchar(trimws(k))) next
    hit <- pub_index[[tolower(trimws(k))]]
    if (!is.null(hit)) return(hit)
  }
  NULL
}

# -----------------------------------------------------------------------------
# 2. Enrich each dictionary workbook.
# -----------------------------------------------------------------------------

# Columns written by 00c_enrich_dictionary_from_scripts.r.
SCRIPT_COLS <- c("display_label", "optional", "skip_condition", "valuemap_check")

# Returns the 00c columns of an enriched workbook as a data frame, or NULL when
# the workbook is older than the base dictionary, lists different variables, or
# holds none of those columns.
read_script_cols <- function(enr_path, base_path, base_vars) {
  drop_msg <- function(why)
    message(sprintf("[00e] %s: %s -- 00c columns not carried over.", basename(enr_path), why))
  if (file.mtime(enr_path) < file.mtime(base_path)) {
    drop_msg("older than the base dictionary")
    return(NULL)
  }
  enr <- tryCatch(read.xlsx(enr_path, sheet = "Variables", skipEmptyCols = FALSE),
                  error = function(e) NULL)
  if (is.null(enr) || !"question_key" %in% names(enr) || !"question_key" %in% names(base_vars) ||
      !identical(as.character(enr$question_key), as.character(base_vars$question_key))) {
    drop_msg("variables differ from the base dictionary")
    return(NULL)
  }
  keep <- intersect(SCRIPT_COLS, names(enr))
  if (length(keep) == 0L) return(NULL)
  enr[, keep, drop = FALSE]
}
base_files <- list.files(DICT_DIR, pattern = "^dictionary_.*\\.xlsx$", full.names = TRUE)
base_files <- base_files[!grepl("_enriched\\.xlsx$", base_files)]
if (length(base_files) == 0L) stop(sprintf("No dictionary files found in %s/", DICT_DIR))

total_matched <- 0L; total_vars <- 0L

for (bf in base_files) {
  enr_path <- sub("\\.xlsx$", "_enriched.xlsx", bf)

  # Always start from the base dictionary.
  wb   <- loadWorkbook(bf)
  if (!"Variables" %in% names(wb)) { message(sprintf("[00e] %s: no Variables sheet -- skipped.", basename(bf))); next }
  vars <- read.xlsx(wb, sheet = "Variables")
  n    <- nrow(vars)
  if (n == 0L) { message(sprintf("[00e] %s: empty Variables sheet -- skipped.", basename(bf))); next }

  script_cols <- if (!OVERWRITE_IN_PLACE && file.exists(enr_path)) read_script_cols(enr_path, bf, vars) else NULL

  key_col  <- if ("question_key" %in% names(vars)) vars$question_key else rep(NA_character_, n)
  harm_col <- if ("harmonised_variable_name" %in% names(vars)) vars$harmonised_variable_name else rep(NA_character_, n)

  add <- data.frame(
    public_meaning = character(n), public_data_type = character(n),
    public_dependency = character(n), public_range = character(n),
    old_variable_name = character(n), timeline_of_change = character(n),
    public_reference = character(n), public_dict_matched = logical(n),
    stringsAsFactors = FALSE)

  matched <- 0L
  for (i in seq_len(n)) {
    rec <- lookup(key_col[i], harm_col[i])
    if (is.null(rec)) { add$public_dict_matched[i] <- FALSE; next }
    matched <- matched + 1L
    add$public_meaning[i]      <- rec$meaning
    add$public_data_type[i]    <- rec$dtype
    add$public_dependency[i]   <- rec$dependency
    add$public_range[i]        <- rec$range
    add$old_variable_name[i]   <- if (!identical(tolower(rec$old), tolower(rec$var))) rec$old else ""
    add$timeline_of_change[i]  <- rec$timeline
    add$public_reference[i]    <- rec$reference
    add$public_dict_matched[i] <- TRUE
  }

  # -- targeted column writes (same pattern as 00c): only the 00c columns
  #    carried over and NEW_COLS are touched --
  if (!is.null(script_cols)) add <- cbind(script_cols, add)
  cur_headers <- names(read.xlsx(wb, sheet = "Variables"))
  for (col_name in names(add)) {
    if (col_name %in% cur_headers) {
      col_idx <- which(cur_headers == col_name)[[1L]]
    } else {
      col_idx <- length(cur_headers) + 1L
      writeData(wb, sheet = "Variables", x = col_name,
                startRow = 1L, startCol = col_idx, colNames = FALSE)
      cur_headers <- c(cur_headers, col_name)
    }
    writeData(wb, sheet = "Variables",
              x = data.frame(v = add[[col_name]], stringsAsFactors = FALSE),
              startRow = 2L, startCol = col_idx, colNames = FALSE)
  }

  out_path <- if (OVERWRITE_IN_PLACE) bf else enr_path
  tryCatch(saveWorkbook(wb, out_path, overwrite = TRUE),
           error = function(e) message(sprintf("[00e]    ERROR saving %s: %s",
                                               basename(out_path), conditionMessage(e))))
  total_matched <- total_matched + matched; total_vars <- total_vars + n
  message(sprintf("[00e] %-52s %3d/%3d variables matched -> %s",
                  basename(bf), matched, n, basename(out_path)))
}

message(sprintf("\n[00e] Public-dictionary enrichment complete: %d/%d variables matched across %d dictionaries.",
                total_matched, total_vars, length(base_files)))
message("[00e] Documentation only -- ValueMaps, canonical codes and cleaning behaviour unchanged.")
