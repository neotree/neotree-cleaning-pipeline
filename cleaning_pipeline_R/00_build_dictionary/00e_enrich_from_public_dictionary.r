# =============================================================================
# NEOTREE CLEANING PIPELINE -- PRE-PIPELINE SETUP SCRIPT  (documentation step)
# Module 00e: Enrich Data Dictionary from the 2024 Public Data Dictionary
# =============================================================================
#
# PURPOSE:
#   Adds human-readable DOCUMENTATION columns to the Variables sheet of each
#   dictionary workbook by cross-referencing the curated
#   og_dictionaries/Public_data_dictionary_2024.xlsx.  Columns added:
#
#     public_meaning       -- plain-language "Variable meaning" (question intent)
#     public_data_type     -- data type as documented in the public dictionary
#     public_dependency    -- skip-logic / dependency described in words
#     public_range         -- documented plausible range (reference only)
#     old_variable_name    -- previous name of this variable, if it was renamed
#     timeline_of_change   -- when/why the variable name or definition changed
#     public_reference     -- source reference cited in the public dictionary
#     public_dict_matched  -- TRUE if a public-dictionary entry was found
#
#   This is DOCUMENTATION ONLY.  It never touches the ValueMaps sheet, canonical
#   codes, ranges used by the pipeline, or any cleaning behaviour.  The canonical
#   dictionaries still build solely from the downloaded web-editor data keys
#   (00_build_dictionary.r) plus VALUEMAP_PATCHES; this pass only annotates them
#   with curated descriptions so the dictionaries are more usable for analysts.
#
# PREREQUISITES:
#   Run 00_build_dictionary.r (step 1), then 00c_enrich_dictionary_from_scripts.r
#   (step 2).  This 00e pass is step 3.  When the 00c "_enriched.xlsx" copies
#   exist they are used as the input so the 00c columns are preserved; otherwise
#   the base dictionary_*.xlsx files are used.
#
# HOW TO RUN:
#   # From the pipeline root (cleaning_pipeline_R/):
#   source("00_build_dictionary/00e_enrich_from_public_dictionary.r")
#   # or:
#   Rscript 00_build_dictionary/00e_enrich_from_public_dictionary.r
#
# WHEN TO RE-RUN:
#   Re-run whenever a newer public data dictionary is dropped into
#   og_dictionaries/, or after the dictionaries are rebuilt.  Safe to re-run:
#   it only refreshes the eight documentation columns.
#
# MATCHING:
#   Each dictionary variable (question_key / harmonised_variable_name) is matched
#   case-insensitively against every public-dictionary sheet by CURRENT variable
#   name and by OLD variable name.  A global index is used because a variable's
#   documented meaning is stable across the admission/discharge/PHC/maternal/
#   neolab sheets.  The first non-empty match wins.
#
# STANDALONE:
#   No dependency on the cleaning pipeline.  Uses base R, readxl, openxlsx.
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
# FALSE => write to dictionary_*_enriched.xlsx (recommended; preserves 00c work).
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
base_files <- list.files(DICT_DIR, pattern = "^dictionary_.*\\.xlsx$", full.names = TRUE)
base_files <- base_files[!grepl("_enriched\\.xlsx$", base_files)]
if (length(base_files) == 0L) stop(sprintf("No dictionary files found in %s/", DICT_DIR))

total_matched <- 0L; total_vars <- 0L

for (bf in base_files) {
  enr_path <- sub("\\.xlsx$", "_enriched.xlsx", bf)
  # Prefer the 00c-enriched copy as the source so its columns are preserved.
  src <- if (!OVERWRITE_IN_PLACE && file.exists(enr_path)) enr_path else bf

  wb   <- loadWorkbook(src)
  if (!"Variables" %in% names(wb)) { message(sprintf("[00e] %s: no Variables sheet -- skipped.", basename(bf))); next }
  vars <- read.xlsx(wb, sheet = "Variables")
  n    <- nrow(vars)
  if (n == 0L) { message(sprintf("[00e] %s: empty Variables sheet -- skipped.", basename(bf))); next }

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

  # -- targeted column writes (same pattern as 00c): only NEW_COLS are touched --
  cur_headers <- names(read.xlsx(wb, sheet = "Variables"))
  for (col_name in NEW_COLS) {
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
