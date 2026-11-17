# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00: Setup & Configuration
# =============================================================================
# PURPOSE:
#   Defines the settings, shared value parsers, dictionary-derived feature
#   lists and PII checks used by every other module, and collects the settings
#   in `cfg`.
#
# METHOD:
#   - Gives each user setting a default unless it already exists in the
#     calling environment.
#   - Creates the per-run output folder output/<input file stem>/ and starts
#     the run log there.
#   - Validates COUNTRY, DATASET and DATA_SOURCE, then replaces DATA_SOURCE
#     with the export style detected from the file.
#   - Resolves the dictionary path
#     (dictionaries/dictionary_{country}_{dataset}.xlsx, or the dictionary of
#     the dataset named in DICT_FALLBACK if that file is absent) and the path
#     of the paired admissions/discharges file.
#   - Reads the Variables and ValueMaps sheets of the dictionary and derives
#     the feature lists, weight columns, PII columns, harmonised name map,
#     range lookup and value map list.
#   - Compares the CSV header with the dictionary and reports the columns the
#     dictionary does not cover.
#   - Defines the PII patterns, the Module 00a completion marker and
#     assert_pii_removed().
#
# INPUTS:
#   The raw CSV (CSV_FILEPATH) and the data dictionary workbook
#   (DICT_FILEPATH).
#
# OUTPUTS:
#   Global objects:
#     cfg               - named list of pipeline parameters and feature lists
#     dict_variables    - Variables sheet of the data dictionary (tibble)
#     dict_value_maps   - ValueMaps sheet of the data dictionary (tibble)
#     parse_datetime_by_shape(), parse_numeric_by_shape(), cols_of_type(),
#     pii_value_hits(), load_pii_patterns(), write_pii_marker(),
#     assert_pii_removed()
#   Files:
#     <file_stem>.log in the run output folder
#     00c_undocumented_columns.txt, when the dictionary does not cover every
#     data column
#
# USAGE:
#   source("00_setup/00_setup.r")
# =============================================================================

# -- Libraries -----------------------------------------------------------------
suppressPackageStartupMessages({
  library(readr) # Fast CSV reading
  library(readxl) # Excel dictionary loading
  library(dplyr) # Data manipulation
  library(tidyr) # Reshaping helpers
  library(stringr) # String operations
  library(lubridate) # Datetime parsing
  library(purrr) # Functional helpers
  library(logger) # Structured logging
  library(janitor) # clean_names helper
  library(tibble) # For deframe() function
})

# =============================================================================
# USER CONFIGURATION
# =============================================================================
# A setting already defined in the calling environment (e.g. by run_all.r) is
# kept; only undefined settings receive the defaults below.
# =============================================================================

# Source country  :  "ZIM" (Zimbabwe) | "MWI" (Malawi)
if (!exists("COUNTRY"))     COUNTRY     <- "ZIM"

# Dataset type:
#   Standard        : "admissions" | "discharges" | "maternal_outcomes"
#   PHC             : "phc_admissions" | "phc_discharges"
#   Maternal sources: "combined_maternity_outcomes" | "dhis2_maternal_outcomes" |
#                     "maternity_completeness"
#   Joined          : "joined_admissions_discharges"  (uses the admissions dictionary)
#   Neolab          : "neolab"
#   Zimbabwe only   : "baseline" | "infections" | "twenty_8_day_follow_up"
if (!exists("DATASET"))     DATASET     <- "admissions"

# Data source format.  Informational: parsing does not depend on it.  Whatever
# is set here is replaced further down by the style detected from the file
# ("database", "metabase", "mixed" or "unknown"), which is what the log and
# reports show.
if (!exists("DATA_SOURCE")) DATA_SOURCE <- "auto" # informational only

# Raw CSV file.  Names follow {country}_{dataset}_{date}.csv, optionally with a
# db or mb token after the country, e.g.
#   input/zim_admissions_2000-01-31.csv
#   input/mwi_db_phc_discharges_20000131.csv
if (!exists("CSV_FILEPATH")) CSV_FILEPATH <- "input/zim_admissions_2026-01-31.csv"

# Dictionary path (auto-resolved if left as NULL)
if (!exists("DICT_FILEPATH"))       DICT_FILEPATH       <- NULL # NULL = auto: dictionaries/dictionary_{country}_{dataset}.xlsx

# Output file paths (NULL = auto-named from CSV_FILEPATH)
if (!exists("OUTPUT_CSV"))          OUTPUT_CSV          <- NULL
if (!exists("OUTPUT_RDS"))          OUTPUT_RDS          <- NULL

# Path to the neotree_scripts directory (used by Module 16: NA Reason Coding).
#   Contains zim-scripts/ and mwi-scripts/ sub-directories, each holding the
#   Neotree script metadata JSON files.
#   NULL = ../neotree_scripts relative to the folder of this setup file.
if (!exists("NEOTREE_SCRIPTS_DIR")) NEOTREE_SCRIPTS_DIR <- NULL

# Report directory
#   NULL        = reports/ inside the run output folder
#   "my_folder" = write all reports to that path
#   FALSE or "" = write no reports
if (!exists("REPORT_DIR"))          REPORT_DIR          <- NULL

# Output directory: base folder for the cleaned files, reports and run log.
if (!exists("OUTPUT_DIR"))          OUTPUT_DIR          <- "output"

# =============================================================================
# OUTPUT FILE FLAGS
# =============================================================================
# Each flag controls whether an optional output file is written.

# De-identified raw CSV written by Module 00a.
if (!exists("SAVE_DEIDENTIFIED"))      SAVE_DEIDENTIFIED      <- FALSE

# Stage-1 checkpoint RDS written by Module 10 after deduplication.
if (!exists("SAVE_STAGE1_CHECKPOINT")) SAVE_STAGE1_CHECKPOINT <- FALSE

# Skip Stage 2 (patient-level) deduplication in Module 10.
#   FALSE -- both Stage 1 and Stage 2 run.
#   TRUE  -- only Stage 1 (visit-level) runs; all records per patient are kept.
# Defaults to TRUE for "infections" and "neolab", which hold several rows per
# patient by design, and to FALSE for every other dataset.
if (!exists("SKIP_DEDUP_STAGE2")) {
  SKIP_DEDUP_STAGE2 <- DATASET %in% c("infections", "neolab")
}

# Resolve missing neolab datebct from admissions (Module 14a).
#   TRUE  -- Module 14a fills NA datebct.value entries by joining to the raw
#            admissions file on uid + facility and using datetimeadmission.
#            It adds datebct_resolved (POSIXct) and datebct_source
#            ("original" | "from_admission" | NA); datebct.value is unchanged.
#   FALSE -- Module 14a adds no columns.
# Has an effect only when DATASET == "neolab".
if (!exists("RESOLVE_NEOLAB_DATEBCT")) RESOLVE_NEOLAB_DATEBCT <- TRUE

# Separator characters treated as a mistyped hyphen in a uid (Module 02).
#   The standard Neotree uid is "XXXX-YYYY".  A uid of the form "XXXX,YYYY" or
#   "XXXX/YYYY" is repaired.  Every character in this vector is treated as a
#   substitute for the hyphen.
if (!exists("UID_REPAIR_SEPARATORS")) UID_REPAIR_SEPARATORS <- c(",", "/")

# Raw data columns whose standardised name collides with a reserved system key
# column (facility | uid | uniquekey).  Module 01 renames them immediately
# after name standardisation, so that the data field and the system column
# remain separate columns.
#   Format: dataset -> named character vector (standardised name -> new name)
if (!exists("RESERVED_COLUMN_RENAMES")) {
  RESERVED_COLUMN_RENAMES <- list(
    phc_discharges = c(
      "facility.value" = "facilityname.value",
      "facility.label" = "facilityname.label"
    )
  )
}

# Fields whose answer is stored only in the .label column while the paired
# .value column is empty, and whose label text can be read as a value.
# Module 05 fills .value from the label before the generic recovery steps run.
#   Format: country -> dataset -> named character vector (field -> parser)
#   Parsers (defined in Module 05):
#     "anc_visit_count" -- number of antenatal care visits from labels such as
#                          "3 ANC visits" and "None".  Also writes
#                          <field>_source; Module 15 derives <field>_category.
if (!exists("LABEL_VALUE_RULES")) {
  LABEL_VALUE_RULES <- list(
    MWI = list(
      admissions = c(antenatalcare = "anc_visit_count")
    )
  )
}

# Harmonised (snake_case) CSV + RDS written by Module 00b.
if (!exists("SAVE_HARMONISED"))        SAVE_HARMONISED        <- FALSE

# NA-coded CSV written by Module 16: the cleaned data with every NA cell
# replaced by its reason code (-6/-7/-8/-9).
if (!exists("SAVE_NA_CODED"))          SAVE_NA_CODED          <- TRUE

# Long-format NA reasons table written by Module 16: one row per NA cell.
if (!exists("SAVE_NA_REASONS_LONG"))   SAVE_NA_REASONS_LONG   <- FALSE

# =============================================================================
# INTERNAL SETUP
# =============================================================================

# -- Output directory ----------------------------------------------------------
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# -- Per-run output subdirectory -----------------------------------------------
# Named after the input CSV stem.  All outputs for this run -- cleaned files,
# reports and the run log -- are written here.
file_stem      <- sub("\\.csv$", "", basename(CSV_FILEPATH))
RUN_OUTPUT_DIR <- file.path(OUTPUT_DIR, file_stem)
if (!dir.exists(RUN_OUTPUT_DIR)) dir.create(RUN_OUTPUT_DIR, recursive = TRUE)

# -- Neotree scripts directory (Module 16) ------------------------------------
if (is.null(NEOTREE_SCRIPTS_DIR)) {
  NEOTREE_SCRIPTS_DIR <- file.path(
    dirname(normalizePath("00_setup/00_setup.r", mustWork = FALSE)),
    "..", "neotree_scripts"
  )
}
NEOTREE_SCRIPTS_DIR <- normalizePath(NEOTREE_SCRIPTS_DIR, mustWork = FALSE)

# -- Pipeline version ----------------------------------------------------------
# Written to the run log and to the Module 00a completion marker.
PIPELINE_VERSION <- "2.0.1"

# -- Logging -------------------------------------------------------------------
log_appender(appender_tee(file = file.path(RUN_OUTPUT_DIR, paste0(file_stem, ".log"))))
log_threshold(INFO)
# formatter_sprintf makes log_*("text %s", value) substitute sprintf-style
# placeholders.  The logger runs sprintf() on every message it is given, so the
# format string and its arguments are passed separately; a string that is
# already formatted and still contains a literal % would stop with an error.
log_formatter(formatter_sprintf)
log_info("Pipeline started (cleaning pipeline v%s).", PIPELINE_VERSION)

# -- Normalise inputs ----------------------------------------------------------
COUNTRY <- toupper(trimws(COUNTRY))
DATASET <- tolower(trimws(DATASET))
DATA_SOURCE <- tolower(trimws(DATA_SOURCE))

VALID_DATASETS <- c(
  "admissions", "discharges", "maternal_outcomes",
  "phc_admissions", "phc_discharges",
  "combined_maternity_outcomes",
  "dhis2_maternal_outcomes",      # DHIS2-linked maternal source file
  "maternity_completeness",       # maternity completeness source file
  "joined_admissions_discharges",
  "neolab",                       # blood culture / neolab dataset
  # Zimbabwe-specific datasets
  "baseline",                     # retrospective baseline admission+discharge in one form (ZIM)
  "infections",                   # longitudinal infection follow-up form (ZIM)
  "twenty_8_day_follow_up"        # 28-day post-discharge follow-up (ZIM)
)

if (!COUNTRY %in% c("ZIM", "MWI")) {
  stop(sprintf("COUNTRY must be 'ZIM' or 'MWI', got '%s'.", COUNTRY))
}
if (!DATASET %in% VALID_DATASETS) {
  stop(sprintf(
    "DATASET must be one of: %s\n  Got: '%s'",
    paste(VALID_DATASETS, collapse = ", "), DATASET
  ))
}
if (!DATA_SOURCE %in% c("auto", "database", "metabase", "mixed", "unknown")) {
  stop(sprintf("DATA_SOURCE must be 'auto', 'database' or 'metabase' (or left unset), got '%s'.",
               DATA_SOURCE))
}

#' Describe the export style of a raw CSV (for the log and reports only)
#'
#' Reads the header and the first n_rows rows as text and counts:
#'   - header style: Title Case system columns ("Unique Key", "Started At")
#'     = Metabase; snake_case ("unique_key", "started_at") = database;
#'   - datetime values in ISO form ("2000-01-31 13:45:00") and in month-name
#'     form ("January 31, 2000, 1:45 PM", "31 January 2000");
#'   - numbers with thousands separators ("3,500").
#' Month-name datetimes alone give the value style "metabase", ISO datetimes
#' alone "database", both together or ISO datetimes with thousands-separated
#' numbers "mixed".  The header style and the value style are then combined:
#' one recognised style gives that style, two give "mixed", none gives
#' "unknown".  Only counts are reported; no values are written to the log.
#'
#' @param csv_filepath  Path to the raw CSV
#' @param n_rows        Number of rows to sample (default 500)
#' @return list(source = "database" | "metabase" | "mixed" | "unknown",
#'              reason = <character summary>)
.detect_data_source <- function(csv_filepath, n_rows = 500L) {
  if (!file.exists(csv_filepath)) {
    return(list(source = "unknown", reason = "input file not found"))
  }
  sample_df <- tryCatch(
    suppressWarnings(readr::read_csv(
      csv_filepath, n_max = n_rows,
      col_types = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE, progress = FALSE, name_repair = "minimal"
    )),
    error = function(e) NULL
  )
  if (is.null(sample_df)) {
    return(list(source = "unknown", reason = "the file could not be sampled"))
  }

  hdr    <- trimws(names(sample_df))
  hdr_mb <- any(hdr %in% c("Unique Key", "Started At", "Completed At", "Ingested At"))
  hdr_db <- any(hdr %in% c("unique_key", "started_at", "completed_at", "ingested_at"))
  header <- if (hdr_mb && !hdr_db) "metabase" else if (hdr_db && !hdr_mb) "database" else "unknown"

  month_re <- paste0("(January|February|March|April|May|June|July|August|",
                     "September|October|November|December)")
  re_month <- paste0("^\\s*(", month_re, "\\s+\\d{1,2},\\s*\\d{4}|",
                     "\\d{1,2}\\s+", month_re, "\\s+\\d{4})")
  re_iso   <- "^\\s*\\d{4}-\\d{2}-\\d{2}([ T]\\d{2}:\\d{2}|\\s*$)"
  re_thou  <- "^\\s*[+-]?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?\\s*$"
  n_month <- 0L; n_iso <- 0L; n_thou <- 0L
  for (col in names(sample_df)) {
    v <- sample_df[[col]]
    v <- v[!is.na(v) & nzchar(v)]
    if (length(v) == 0) next
    n_month <- n_month + sum(grepl(re_month, v, perl = TRUE))
    n_iso   <- n_iso   + sum(grepl(re_iso,   v, perl = TRUE))
    n_thou  <- n_thou  + sum(grepl(re_thou,  v, perl = TRUE))
  }

  values <- if (n_month > 0L && n_iso == 0L) "metabase"
            else if (n_iso > 0L && n_month == 0L) "database"
            else if (n_iso > 0L && n_month > 0L) "mixed"
            else "unknown"
  if (n_thou > 0L && values == "database") values <- "mixed"

  styles <- setdiff(unique(c(header, values)), "unknown")
  label  <- if (length(styles) == 0) "unknown" else if (length(styles) == 1) styles else "mixed"

  reason <- sprintf(
    "header %s; first %d rows: %d ISO datetime, %d month-name datetime, %d thousands-separated number value(s)",
    switch(header, metabase = "Metabase-style ('Unique Key')",
                   database = "database-style ('unique_key')",
                   "style not recognised"),
    nrow(sample_df), n_iso, n_month, n_thou)
  list(source = label, reason = reason)
}

# DATA_SOURCE is replaced by the style detected from the file.  A different
# value set beforehand is logged.
ds_detected <- .detect_data_source(CSV_FILEPATH)
if (DATA_SOURCE != "auto" && !identical(DATA_SOURCE, ds_detected$source)) {
  log_info(paste("DATA_SOURCE was set to '%s'; the file itself looks '%s'.",
                 "Parsing is format-agnostic, so this does not change the result."),
           DATA_SOURCE, ds_detected$source)
}
DATA_SOURCE <- ds_detected$source
log_info("Data source format : %s (detected: %s)", DATA_SOURCE, ds_detected$reason)

# =============================================================================
# SHAPE-ROUTED VALUE PARSERS
# =============================================================================
# Each value is routed by its own shape and parsed by the one rule that fits
# that shape.
#
# Datetimes -- parse_datetime_by_shape():
#   iso         "2000-01-31", "2000-01-31 13:45:00", "2000-01-31T13:45:00Z",
#               "2000-01-31T13:45:00+02:00".  A trailing "Z" or UTC offset is
#               dropped and the time is kept as written (no conversion).
#   day_first   "25/12/2023", "25-12-2023", "25.12.2023", with an optional time.
#               Always read as day/month/year.  A two-digit year is read as
#               20yy.  A value that is only valid as month/day/year is not
#               reinterpreted: it becomes NA and is counted.
#   month_name  "January 31, 2000, 1:45 PM", "31 January 2000", "31 Jan 2000".
#   Anything else (free text that contains a date, bare digit strings) is NA.
#
#   A general parser is not used for day-first values:
#   lubridate::parse_date_time() with year-first orders listed before day-first
#   orders accepts a day-first date and returns a different, valid-looking date.
#
# Numbers -- parse_numeric_by_shape():
#   plain          "3500", "3.5", "-2"
#   thousands      "3,500", "1,234,567.8"   -> separators removed
#   decimal_comma  "3,5", "36,75"           -> comma read as the decimal point
#   fallback       text holding exactly one number ("ANC4", "4 ANC visits")
#                  -> that number.  Text holding two or more numbers (a date, a
#                  range, exponent or hexadecimal notation) is NA and counted.
#
# Booleans -- NEOTREE_TRUE_TOKENS / NEOTREE_FALSE_TOKENS (lower case).
# =============================================================================

NEOTREE_TRUE_TOKENS  <- c("true",  "yes", "y", "1", "t")
NEOTREE_FALSE_TOKENS <- c("false", "no",  "n", "0", "f")

#' Parse datetimes value by value, routed by shape
#'
#' @param x  Character (or coercible) vector.
#' @return   POSIXct (UTC) vector with attribute "counts": named integer vector
#'           iso, day_first, month_name, offset_dropped, month_first_rejected,
#'           unparsed.  Counts only; no values are kept.
parse_datetime_by_shape <- function(x) {
  s   <- trimws(as.character(x))
  n   <- length(s)
  out <- as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  ok  <- !is.na(s) & nzchar(s) & s != "NA"
  counts <- c(iso = 0L, day_first = 0L, month_name = 0L, offset_dropped = 0L,
              month_first_rejected = 0L, unparsed = 0L)
  if (!any(ok)) { attr(out, "counts") <- counts; return(out) }

  build <- function(y, m, d, H, M, S, ampm) {
    H[is.na(H)] <- 0L; M[is.na(M)] <- 0L; S[is.na(S)] <- 0
    pm <- !is.na(ampm) & ampm == "pm"; am <- !is.na(ampm) & ampm == "am"
    bad12 <- (pm | am) & (H < 1L | H > 12L)
    H[pm & H < 12L]  <- H[pm & H < 12L] + 12L
    H[am & H == 12L] <- 0L
    res <- suppressWarnings(ISOdatetime(y, m, d, H, M, S, tz = "UTC"))
    res[bad12 | H > 23L | M > 59L | S >= 60] <- NA
    res
  }
  time_re <- "([ T,]+([0-9]{1,2}):([0-9]{2})(:([0-9]{2})(\\.[0-9]+)?)?\\s*([AaPp][Mm])?)?"

  # -- ISO (four-digit year first) ---------------------------------------------
  iso_re <- paste0("^[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}",
                   "([ T][0-9]{1,2}(:[0-9]{2}(:[0-9]{2}(\\.[0-9]+)?)?)?",
                   "\\s*(Z|[+-][0-9]{2}(:?[0-9]{2})?)?)?$")
  is_iso <- ok & grepl(iso_re, s, perl = TRUE)
  if (any(is_iso)) {
    v <- s[is_iso]
    has_time <- grepl("[ T][0-9]{1,2}:[0-9]{2}", v, perl = TRUE)
    off <- has_time & grepl("(Z|[+-][0-9]{2}(:?[0-9]{2})?)$", v, perl = TRUE)
    v[off] <- trimws(sub("(Z|[+-][0-9]{2}(:?[0-9]{2})?)$", "", v[off], perl = TRUE))
    counts["offset_dropped"] <- sum(off)
    p <- suppressWarnings(lubridate::parse_date_time(
      v, orders = c("Ymd HMS", "Ymd HM", "Ymd H", "Ymd"), tz = "UTC", quiet = TRUE))
    out[is_iso] <- p
    counts["iso"] <- sum(!is.na(p))
  }

  # -- Day first: d/m/y, d-m-y, d.m.y (two- or four-digit year) ----------------
  df_re <- paste0("^([0-9]{1,2})([/.-])([0-9]{1,2})\\2([0-9]{4}|[0-9]{2})", time_re, "$")
  is_df <- ok & !is_iso & grepl(df_re, s, perl = TRUE)
  if (any(is_df)) {
    g <- regmatches(s[is_df], regexec(df_re, s[is_df], perl = TRUE))
    gi <- function(k) vapply(g, function(z) z[k], "")
    d <- as.integer(gi(2)); m <- as.integer(gi(4)); y <- as.integer(gi(5))
    y[nchar(gi(5)) == 2L] <- 2000L + y[nchar(gi(5)) == 2L]
    H <- suppressWarnings(as.integer(gi(7))); M <- suppressWarnings(as.integer(gi(8)))
    S <- suppressWarnings(as.numeric(gi(10))); ap <- tolower(gi(12)); ap[!nzchar(ap)] <- NA
    month_first_only <- m > 12L & d <= 12L
    m[month_first_only] <- NA
    p <- build(y, m, d, H, M, S, ap)
    out[is_df] <- p
    counts["day_first"] <- sum(!is.na(p))
    counts["month_first_rejected"] <- sum(month_first_only)
  }

  # -- Month name: "January 31, 2000[, 1:45 PM]" or "31 January 2000[, 1:45 PM]" --
  mon_re <- "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"
  mdy_re <- paste0("^(?i)", mon_re, "\\s+([0-9]{1,2}),?\\s+([0-9]{4})", time_re, "$")
  dmy_re <- paste0("^(?i)([0-9]{1,2})[ -]", mon_re, "[ ,-]+([0-9]{4})", time_re, "$")
  rest   <- ok & !is_iso & !is_df
  is_mdy <- rest & grepl(mdy_re, s, perl = TRUE)
  is_dmy <- rest & grepl(dmy_re, s, perl = TRUE)
  mon_num <- function(z) match(tolower(substr(z, 1, 3)),
                               c("jan", "feb", "mar", "apr", "may", "jun",
                                 "jul", "aug", "sep", "oct", "nov", "dec"))
  parse_named <- function(idx, re, k_mon, k_day, k_year) {
    g <- regmatches(s[idx], regexec(re, s[idx], perl = TRUE))
    gi <- function(k) vapply(g, function(z) z[k], "")
    ap <- tolower(gi(11)); ap[!nzchar(ap)] <- NA
    build(as.integer(gi(k_year)), mon_num(gi(k_mon)), as.integer(gi(k_day)),
          suppressWarnings(as.integer(gi(6))), suppressWarnings(as.integer(gi(7))),
          suppressWarnings(as.numeric(gi(9))), ap)
  }
  if (any(is_mdy)) out[is_mdy] <- parse_named(is_mdy, mdy_re, 1L + 1L, 1L + 2L, 1L + 3L)
  if (any(is_dmy)) out[is_dmy] <- parse_named(is_dmy, dmy_re, 1L + 2L, 1L + 1L, 1L + 3L)
  counts["month_name"] <- sum(!is.na(out[is_mdy | is_dmy]))

  counts["unparsed"] <- sum(ok & is.na(out))
  attr(out, "counts") <- counts
  out
}

#' Parse numbers value by value, routed by shape
#'
#' @param x  Character (or coercible) vector.
#' @return   list(value = numeric vector, counts = named integer vector: plain,
#'           thousands, decimal_comma, fallback, multi_number_rejected,
#'           non_numeric).  Counts only; no values are kept.
parse_numeric_by_shape <- function(x) {
  s   <- trimws(as.character(x))
  n   <- length(s)
  out <- rep(NA_real_, n)
  ok  <- !is.na(s) & nzchar(s)
  plain <- ok & grepl("^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)$", s, perl = TRUE)
  thou  <- ok & !plain & grepl("^[+-]?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$", s, perl = TRUE)
  dcom  <- ok & !plain & !thou & grepl("^[+-]?[0-9]+,[0-9]{1,2}$", s, perl = TRUE)
  out[plain] <- suppressWarnings(as.numeric(s[plain]))
  out[thou]  <- suppressWarnings(as.numeric(gsub(",", "", s[thou], fixed = TRUE)))
  out[dcom]  <- suppressWarnings(as.numeric(sub(",", ".", s[dcom], fixed = TRUE)))
  rest <- which(ok & !plain & !thou & !dcom)
  n_fallback <- 0L; n_multi <- 0L
  if (length(rest)) {
    runs  <- regmatches(s[rest], gregexpr("[0-9]+(\\.[0-9]+)?", s[rest], perl = TRUE))
    n_run <- lengths(runs)
    one   <- n_run == 1L
    out[rest[one]] <- suppressWarnings(as.numeric(vapply(runs[one], `[`, "", 1L)))
    n_fallback <- sum(one)
    n_multi    <- sum(n_run > 1L)
  }
  list(value = out,
       counts = c(plain = sum(plain), thousands = sum(thou), decimal_comma = sum(dcom),
                  fallback = n_fallback, multi_number_rejected = n_multi,
                  non_numeric = sum(ok & is.na(out)) - n_multi))
}

# =============================================================================
# DICTIONARY FALLBACK MAP
# =============================================================================
# A dataset listed here uses the dictionary of the named dataset when its own
# dictionaries/dictionary_{country}_{dataset}.xlsx does not exist.  NULL means
# no fallback.

DICT_FALLBACK <- list(
  joined_admissions_discharges = "admissions",
  phc_admissions               = "admissions",               # fallback only; specific dict preferred
  phc_discharges               = "discharges",               # fallback only; specific dict preferred
  dhis2_maternal_outcomes      = "combined_maternity_outcomes", # fallback only; specific dict preferred
  maternity_completeness       = "maternal_outcomes",         # fallback only; specific dict preferred
  baseline                     = "admissions",               # fallback; dedicated dict preferred
  infections                   = NULL,                       # no fallback; needs its own dictionary
  twenty_8_day_follow_up       = NULL                        # no fallback; needs its own dictionary
)

# -- Resolve auto paths --------------------------------------------------------
if (is.null(DICT_FILEPATH)) {
  primary_path <- sprintf("dictionaries/dictionary_%s_%s.xlsx", tolower(COUNTRY), DATASET)
  fallback_type <- DICT_FALLBACK[[DATASET]]
  if (!file.exists(primary_path) && !is.null(fallback_type)) {
    fallback_path <- sprintf("dictionaries/dictionary_%s_%s.xlsx", tolower(COUNTRY), fallback_type)
    if (file.exists(fallback_path)) {
      log_info(
        "No specific dictionary for %s x %s; falling back to %s dictionary.",
        COUNTRY, DATASET, fallback_type
      )
      DICT_FILEPATH <- fallback_path
    } else {
      DICT_FILEPATH <- primary_path # stops below: dictionary not found
    }
  } else {
    DICT_FILEPATH <- primary_path
  }
}

if (is.null(OUTPUT_CSV)) {
  OUTPUT_CSV <- file.path(RUN_OUTPUT_DIR, paste0(file_stem, "_cleaned.csv"))
}

if (is.null(OUTPUT_RDS)) {
  OUTPUT_RDS <- file.path(RUN_OUTPUT_DIR, paste0(file_stem, "_cleaned.rds"))
}

# -- Report directory ----------------------------------------------------------
# Defaults to a reports/ subfolder inside the run output directory.
if (is.null(REPORT_DIR)) {
  REPORT_DIR <- file.path(RUN_OUTPUT_DIR, "reports")
}
if (!isFALSE(REPORT_DIR) && nzchar(REPORT_DIR) && !dir.exists(REPORT_DIR)) {
  dir.create(REPORT_DIR, recursive = TRUE)
}
# Normalise suppression: treat FALSE or "" as NULL so downstream modules skip writing
if (isFALSE(REPORT_DIR) || identical(REPORT_DIR, "")) REPORT_DIR <- NULL

log_info("Running for: COUNTRY=%s  DATASET=%s", COUNTRY, DATASET)
log_info("Dictionary : %s", DICT_FILEPATH)

# =============================================================================
# PAIRED DATASET RESOLUTION
# =============================================================================
# Admissions and discharges are two halves of the same patient record, and the
# pipeline cleans one file at a time.  Some checks look the other half up:
# Module 02 calls a repaired uid "confirmed" only if the corrected uid exists
# in the paired file for the same country.
#
# This block resolves the path of the paired raw CSV, stored as
# cfg$paired_csv_filepath.  Nothing is read here; a module that needs the file
# reads the columns it wants.
#
# NULL means no paired file is available: either the dataset has no pair, or
# the file is not in the input folder.  Modules treat that as "cannot check",
# not as a negative result.

PAIRED_DATASET <- c(
  admissions     = "discharges",
  discharges     = "admissions",
  phc_admissions = "phc_discharges",
  phc_discharges = "phc_admissions"
)

#' Locate the paired admissions/discharges raw CSV for the current run
#'
#' Prefers the file with the identical date stamp.  If that is absent, it
#' takes the last file, in sorted name order, of the paired dataset with the
#' same country prefix and source token.
#'
#' @return list(dataset = <paired dataset name or NULL>, path = <path or NULL>)
.resolve_paired_csv <- function(csv_filepath, dataset) {
  paired <- unname(PAIRED_DATASET[dataset])
  if (is.na(paired)) return(list(dataset = NULL, path = NULL))

  in_dir <- dirname(csv_filepath)
  bname  <- basename(csv_filepath)

  # 1. Same extract: swap only the dataset token in the filename.
  direct <- file.path(
    in_dir,
    sub(sprintf("_%s_", dataset), sprintf("_%s_", paired), bname, fixed = TRUE)
  )
  if (file.exists(direct)) return(list(dataset = paired, path = direct))

  # 2. Any extract of the paired dataset with the same prefix: the country,
  #    plus the db/mb token if the file name has one.
  m <- regmatches(bname, regexec("^(mwi|zim)_((db|mb)_)?", bname, ignore.case = TRUE))[[1]]
  if (length(m) == 0) return(list(dataset = paired, path = NULL))

  pattern <- sprintf(
    "^%s%s_(\\d{12}|\\d{8}|\\d{4}-\\d{2}-\\d{2})\\.csv$",
    tolower(m[1]), paired
  )
  candidates <- sort(list.files(in_dir, pattern = pattern, ignore.case = TRUE))
  if (length(candidates) == 0) return(list(dataset = paired, path = NULL))

  if (length(candidates) > 1) {
    log_info(
      "Paired-file lookup: %d %s extracts found; using the most recent (%s).",
      length(candidates), paired, candidates[length(candidates)]
    )
  }
  list(dataset = paired, path = file.path(in_dir, candidates[length(candidates)]))
}

paired_info <- .resolve_paired_csv(CSV_FILEPATH, DATASET)

if (is.null(paired_info$dataset)) {
  log_info("Paired file : none (dataset '%s' has no admissions/discharges pair).", DATASET)
} else if (is.null(paired_info$path)) {
  log_warn(
    paste("Paired file : %s dataset not found in '%s'.",
          "Cross-file checks (e.g. Module 02 uid repair confirmation) will report 'unchecked'."),
    paired_info$dataset, dirname(CSV_FILEPATH)
  )
} else {
  log_info("Paired file : %s", paired_info$path)
}

# =============================================================================
# LOAD DICTIONARY
# =============================================================================

if (!file.exists(DICT_FILEPATH)) {
  stop(sprintf(
    "Dictionary not found: '%s'\n  Run 00_build_dictionary/00_build_dictionary.r first.",
    DICT_FILEPATH
  ))
}

dict_variables <- readxl::read_excel(DICT_FILEPATH, sheet = "Variables") %>%
  janitor::clean_names()
dict_value_maps <- readxl::read_excel(DICT_FILEPATH, sheet = "ValueMaps") %>%
  janitor::clean_names()

log_info(
  "Dictionary loaded: %d variables | %d value-map rows",
  nrow(dict_variables), nrow(dict_value_maps)
)

# =============================================================================
# HELPER: EXTRACT FEATURE LISTS FROM DICTIONARY
# =============================================================================

#' Return raw_value_column names for a given r_type (plus KEY_COLS)
#'
#' @param r_type_filter  One of "numeric", "boolean", "categorical", "object",
#'                       "datetime"
#' @param include_keys   Prepend KEY_COLS (default TRUE)
cols_of_type <- function(r_type_filter, include_keys = TRUE) {
  cols <- dict_variables %>%
    filter(
      r_type == r_type_filter,
      use_in_analysis == TRUE,
      !is.na(raw_value_column)
    ) %>%
    pull(raw_value_column) %>%
    unique()
  if (include_keys) cols <- unique(c(KEY_COLS, cols))
  return(cols)
}

# =============================================================================
# PRIMARY KEY COLUMNS  (always present in every dataset)
# =============================================================================

KEY_COLS <- c("facility", "uid", "uniquekey")

# Extra metadata columns per dataset (normalised names, as after Module 01).
# Stored in cfg$extra_meta_cols and treated as system columns by the dictionary
# coverage check below.
EXTRA_META_COLS <- switch(DATASET,
  phc_admissions              = c("scriptversion"),
  phc_discharges              = c("scriptversion"),
  combined_maternity_outcomes = c("scriptversion", "scriptid"),
  dhis2_maternal_outcomes     = c("scriptversion", "scriptid"),
  maternity_completeness      = c("scriptversion", "scriptid"),
  neolab                      = c("scriptversion", "scriptid"),
  baseline                    = c("scriptversion", "scriptid"),
  infections                  = c("scriptversion", "scriptid"),
  twenty_8_day_follow_up      = c("scriptversion", "scriptid"),
  character(0) # all other datasets: no extra metadata columns
)

# Dataset-specific timestamp columns included in the datetime frame
TIMESTAMP_COLS <- switch(DATASET,
  admissions = c(
    "ingestedat", "startedat", "completedat"
  ),
  discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  maternal_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  phc_admissions = c(
    "ingestedat", "startedat", "completedat"
  ),
  phc_discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  combined_maternity_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  dhis2_maternal_outcomes = c(
    "ingestedat", "startedat", "completedat"
  ),
  maternity_completeness = c(
    "ingestedat", "startedat", "completedat"
  ),
  joined_admissions_discharges = c(
    "ingestedat", "startedat", "completedat",
    "startedatdischarge", "completedatdischarge",
    "ingestedatdischarge"
  ),
  neolab = c(
    "ingestedat", "startedat", "completedat"
  ),
  baseline = c(
    "ingestedat", "startedat", "completedat"
  ),
  infections = c(
    "ingestedat", "startedat", "completedat"
  ),
  twenty_8_day_follow_up = c(
    "ingestedat", "startedat", "completedat"
  )
)

# =============================================================================
# FEATURE LISTS  (derived from dictionary)
# =============================================================================

numeric_features <- cols_of_type("numeric")
bool_features <- cols_of_type("boolean")
cat_features <- cols_of_type("categorical")
obj_features <- cols_of_type("object")
dt_features <- unique(c(KEY_COLS, TIMESTAMP_COLS, cols_of_type("datetime",
  include_keys = FALSE
)))

log_info(
  "Feature lists: num=%d | bool=%d | cat=%d | obj=%d | dt=%d",
  length(numeric_features), length(bool_features),
  length(cat_features), length(obj_features), length(dt_features)
)

# =============================================================================
# WEIGHT COLUMNS  (kg -> g conversion in Module 11)
# =============================================================================

weight_cols <- dict_variables %>%
  filter(!is.na(weight_unit), tolower(weight_unit) == "grams") %>%
  pull(question_key) %>%
  unique()

log_info("Weight columns (kg->g): %s", paste(weight_cols, collapse = ", "))

# =============================================================================
# PII COLUMNS  (from confidential flag in dictionary)
# =============================================================================
# raw_value_column + raw_label_column for every confidential variable.
# Used by Module 00a.

pii_columns <- dict_variables %>%
  filter(confidential == TRUE) %>%
  select(raw_value_column, raw_label_column) %>%
  tidyr::pivot_longer(everything(), values_to = "col_name") %>%
  filter(!is.na(col_name)) %>%
  pull(col_name) %>%
  unique()

log_info("PII columns from dictionary: %d", length(pii_columns))

# =============================================================================
# HARMONISED NAME MAP  (question_key -> harmonised_variable_name)
# Used by Module 00b to rename columns in the final clean dataset.
# =============================================================================

harmonised_name_map <- dict_variables %>%
  filter(
    !is.na(harmonised_variable_name),
    use_in_analysis == TRUE
  ) %>%
  select(question_key, harmonised_variable_name) %>%
  deframe() # named character vector: names=question_key, values=harmonised

log_info("Harmonised name map: %d entries", length(harmonised_name_map))

# =============================================================================
# RANGE LOOKUP  (for Module 11 numeric validation)
# =============================================================================

range_lookup <- dict_variables %>%
  filter(
    r_type == "numeric",
    !is.na(suggested_plausible_min) | !is.na(suggested_plausible_max)
  ) %>%
  select(question_key, suggested_plausible_min, suggested_plausible_max) %>%
  rename(min = suggested_plausible_min, max = suggested_plausible_max)

log_info("Range lookup entries: %d", nrow(range_lookup))

# =============================================================================
# VALUE MAP LIST  (for Module 04 dictionary-based value cleaning)
# =============================================================================
# Nested list: question_key -> list(allowed_codes, canonical_codes,
#                                   label_to_code, code_to_canonical)
#   allowed_codes     : character vector of valid raw_code values
#   canonical_codes   : character vector of valid canonical_code values (the
#                       harmonisation targets Module 04 should emit)
#   label_to_code     : named list  option_label -> canonical_code
#   code_to_canonical : named list  raw_code     -> canonical_code
#                       (lets Module 04 convert a raw code to its canonical form
#                       and underpins case-insensitive matching)

value_map_list <- dict_value_maps %>%
  group_by(question_key) %>%
  group_map(function(rows, key) {
    allowed   <- unique(na.omit(rows$raw_code))
    canonical <- unique(na.omit(rows$canonical_code))
    lbl_map <- setNames(
      as.list(rows$canonical_code),
      rows$option_label
    )
    lbl_map <- lbl_map[!is.na(names(lbl_map)) & names(lbl_map) != ""]
    # raw_code -> canonical_code (drop rows with missing raw_code or canonical)
    c2c_keep <- !is.na(rows$raw_code) & !is.na(rows$canonical_code) &
                rows$raw_code != ""  & rows$canonical_code != ""
    code_map <- setNames(
      as.list(rows$canonical_code[c2c_keep]),
      rows$raw_code[c2c_keep]
    )
    list(
      allowed_codes     = allowed,
      canonical_codes   = canonical,
      label_to_code     = lbl_map,
      code_to_canonical = code_map
    )
  }) %>%
  # group_keys() gives the names in the same sorted order in which group_map()
  # processes the groups.
  setNames(
    dict_value_maps %>%
      group_by(question_key) %>%
      group_keys() %>%
      pull(question_key)
  )

log_info("Value map list: %d keys", length(value_map_list))

# =============================================================================
# CANONICAL CONFIGURATION OBJECT
# =============================================================================

cfg <- list(
  # Identity
  country = COUNTRY,
  dataset = DATASET,
  data_source = DATA_SOURCE, # detected style, for reports only

  # File paths
  csv_filepath   = CSV_FILEPATH,
  dict_filepath  = DICT_FILEPATH,

  # Paired admissions/discharges raw CSV for cross-file checks (Module 02).
  # Both are NULL when the dataset has no pair or the file is absent.
  paired_dataset      = paired_info$dataset,
  paired_csv_filepath = paired_info$path,

  output_dir     = OUTPUT_DIR,        # base output/ directory
  run_output_dir = RUN_OUTPUT_DIR,    # per-run subfolder (output/<file_stem>/)
  file_stem      = file_stem,         # input CSV stem (no extension)
  output_csv     = OUTPUT_CSV,
  output_rds     = OUTPUT_RDS,
  report_dir     = REPORT_DIR,

  # Feature lists
  num = numeric_features,
  bool = bool_features,
  cat = cat_features,
  obj = obj_features,
  dt = dt_features,

  # Extra metadata columns for this dataset (see EXTRA_META_COLS).
  extra_meta_cols = EXTRA_META_COLS,

  # Validation helpers
  weight_cols = weight_cols,
  range_lookup = range_lookup, # tibble: question_key, min, max
  value_map_list = value_map_list, # nested list for Module 04

  # Module 13 optional configuration.
  # value_mappings : named list of alias -> canonical mappings applied per column
  #   during categorical validation (Step 1 of validate_categorical).
  #   Format: list(column_base = list(canonical = c("alias1", "alias2")))
  #   Leave as list() to skip this step.
  # values_to_delete : named list of known-bad values to force-NA per column
  #   during categorical validation (Step 3 of validate_categorical).
  #   Format: list(column_base = c("bad_value_1", "bad_value_2"))
  #   Leave as list() to skip this step.
  value_mappings = list(),
  values_to_delete = list(),

  # PII & harmonisation
  pii_columns = pii_columns, # vector of column names to drop
  harmonised_map = harmonised_name_map, # named vector for Module 00b

  # Module 02: characters treated as a mistyped hyphen in a uid.
  uid_repair_separators = UID_REPAIR_SEPARATORS,

  # Module 01: raw columns to rename to avoid colliding with a reserved
  # system key column (facility/uid/uniquekey).
  # NULL when the current dataset has no entry in RESERVED_COLUMN_RENAMES.
  reserved_column_renames = RESERVED_COLUMN_RENAMES[[DATASET]],

  # Module 05: label-to-value rules for the current country and dataset.
  # NULL when none is configured.
  label_value_rules = LABEL_VALUE_RULES[[COUNTRY]][[DATASET]],

  # Module 16: NA Reason Coding
  neotree_scripts_dir = NEOTREE_SCRIPTS_DIR, # path to neotree_scripts/

  # Output file flags
  save_deidentified      = SAVE_DEIDENTIFIED,
  save_stage1_checkpoint = SAVE_STAGE1_CHECKPOINT,
  save_harmonised        = SAVE_HARMONISED,
  save_na_coded          = SAVE_NA_CODED,
  save_na_reasons_long   = SAVE_NA_REASONS_LONG,

  # Module 10: TRUE skips Stage 2 (patient-level) deduplication.
  skip_dedup_stage2 = SKIP_DEDUP_STAGE2,

  # Module 14a: TRUE fills missing neolab datebct from the raw admissions file
  # (see RESOLVE_NEOLAB_DATEBCT).
  resolve_neolab_datebct = RESOLVE_NEOLAB_DATEBCT
)

log_info(
  paste(
    "Config ready: COUNTRY=%s | DATASET=%s | SOURCE=%s |",
    "num=%d | bool=%d | cat=%d | obj=%d | dt=%d |",
    "pii_cols=%d | weight_cols=%d | range_entries=%d | extra_meta_cols=%d"
  ),
  toupper(cfg$country), cfg$dataset, cfg$data_source,
  length(cfg$num), length(cfg$bool),
  length(cfg$cat), length(cfg$obj), length(cfg$dt),
  length(cfg$pii_columns), length(cfg$weight_cols),
  nrow(cfg$range_lookup), length(cfg$extra_meta_cols)
)
log_info(
  "Output flags: deidentified=%s | stage1=%s | harmonised=%s | na_coded=%s | na_reasons_long=%s | skip_dedup_stage2=%s | resolve_neolab_datebct=%s",
  cfg$save_deidentified, cfg$save_stage1_checkpoint, cfg$save_harmonised,
  cfg$save_na_coded, cfg$save_na_reasons_long, cfg$skip_dedup_stage2,
  cfg$resolve_neolab_datebct
)

# =============================================================================
# DATA DICTIONARY COVERAGE CHECK
# =============================================================================
# Reads the header row of the raw CSV and checks that every data column is in
# the dictionary (dict_variables).  Columns absent from the dictionary pass
# through uncleaned: no type coercion, no value validation, no NA reason
# coding.  They are reported in the log, on the console and in
# 00c_undocumented_columns.txt.
# =============================================================================

.check_dict_coverage <- function() {
  raw_cols <- tryCatch(
    names(readr::read_csv(cfg$csv_filepath, n_max = 0, show_col_types = FALSE)),
    error = function(e) {
      log_warn("Dict coverage check: could not read '%s' -- %s", cfg$csv_filepath, e$message)
      return(NULL)
    }
  )
  if (is.null(raw_cols)) return(invisible(character(0)))

  # Columns always present and handled outside the dictionary
  system_cols <- tolower(unique(c(
    "uid", "facility", "uniquekey",
    "startedat", "completedat", "ingestedat",
    "startedatdischarge", "completedatdischarge", "ingestedatdischarge",
    "scriptversion", "scriptid",
    cfg$extra_meta_cols
  )))

  # Exclude .parentKey columns (dropped by Module 01) and system columns
  data_cols <- raw_cols[
    !grepl("\\.parentKey$", raw_cols, ignore.case = TRUE) &
    !tolower(raw_cols) %in% system_cols
  ]

  # All column names the dictionary accounts for
  known_cols <- union(
    na.omit(dict_variables$raw_value_column),
    na.omit(dict_variables$raw_label_column)
  )

  undocumented <- data_cols[!data_cols %in% known_cols]

  if (length(undocumented) == 0) {
    log_info(
      "Dict coverage check: all %d data columns are in the dictionary.",
      length(data_cols)
    )
  } else {
    msg <- paste(undocumented, collapse = "\n    ")
    log_warn(
      paste(
        "Dict coverage check: %d column(s) in the raw CSV are NOT in the dictionary.",
        "They will pass through uncleaned (no type coercion, no value validation).",
        "Download updated data keys from the web editor and rebuild the dictionary.",
        "Undocumented columns:\n    %s"
      ),
      length(undocumented), msg
    )
    cat(sprintf(
      paste0(
        "\n",
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n",
        "!! DICT COVERAGE WARNING: %d undocumented column(s) found     !!\n",
        "!! Download updated data keys and rebuild the dictionary.     !!\n",
        "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n",
        "%s\n\n"
      ),
      length(undocumented),
      paste0("  - ", undocumented, collapse = "\n")
    ))

    # Save to file in the report directory (or run output dir if reports suppressed)
    out_dir <- if (!is.null(cfg$report_dir)) cfg$report_dir else cfg$run_output_dir
    out_path <- file.path(out_dir, "00c_undocumented_columns.txt")
    writeLines(
      c(
        sprintf("Undocumented columns -- %s x %s -- %s",
                cfg$country, cfg$dataset, format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Input file : %s", cfg$csv_filepath),
        sprintf("Dictionary : %s", cfg$dict_filepath),
        sprintf("Total data columns in CSV        : %d", length(data_cols)),
        sprintf("Columns missing from dictionary  : %d", length(undocumented)),
        "",
        "These columns will pass through uncleaned (no type coercion, no value",
        "validation, no NA reason coding). Download updated data keys from the",
        "web editor and rebuild the dictionary to cover them.",
        "",
        "--- Undocumented columns ---",
        undocumented
      ),
      out_path
    )
    log_info("Undocumented columns saved to: %s", out_path)
  }
  invisible(undocumented)
}

cfg$undocumented_cols <- .check_dict_coverage()

# =============================================================================
# PII DEFINITIONS AND GUARD
# =============================================================================
# The PII constants are defined here so that every module can run the same
# checks as Module 00a through assert_pii_removed().
#
#   - cfg is rebuilt every time this file is sourced, so a flag held in cfg
#     cannot show that 00a ran.  00a writes a completion marker file to the
#     run output folder, and the guard reads it back.
#   - A module that writes row-level data calls the guard immediately before
#     writing.
#
# The guard reports counts only (columns, patterns, number of cells), never
# cell values.

# -- Tier 2 column-name patterns: built-in defaults ----------------------------
# Applied together with the patterns in the dictionary's PII_Patterns sheet
# (union; see PII_TIER2_PATTERNS).
PII_FALLBACK_PATTERNS_DEFAULT <- c(
  "name\\.value$",      # any *name.value  (baby name, mother name, etc.)
  "cell\\.value$",      # mobile/cell phone columns
  "phone\\.value$",     # landline/phone columns
  "address\\.value$",   # physical address columns
  "hcwid",              # healthcare worker ID (catches .value and .label)
  "hospnum",            # hospital patient number
  "neotreeid",          # internal Neotree patient ID
  "stuid",              # study/student HCW ID (catches both .value and .label)
  "uidbid\\.value$",    # baby unique ID
  "uiddc\\.value$",     # discharge unique ID
  "drid\\.value$",      # DR/practitioner ID
  # Fields whose value and label identify a member of staff: consultant on
  # call, discharge signature, and the person entering the data.  Anchored so
  # that only these fields match.
  "^(firm|concall|hcwsigdis|dataentryname(other)?)\\.(value|label)(discharge)?$",
  # Mother's date of birth.  Anchored on the .value/.label suffix so that
  # motherdobyn does not match.
  "^(mother|moth|mat|mum)s?(dob|dateofbirth)\\.(value|label)$"
)

# -- Value-level patterns ------------------------------------------------------
# Matched against trimmed cell values (see pii_value_hits()).
#
#   phone_international  country code 263 + 9 digits, or 265 + 7 to 9 digits,
#                        with or without a leading "+"
#   phone_local_zw       0 + 6 or 7 + 8 digits
#   phone_local_mwi      0 + 8 or 9 + 8 digits
#   email                an e-mail address anywhere in the cell
#   nhs_number           3, 3 and 4 digits separated by hyphens or spaces
#   zw_national_id       Zimbabwe national registration number: 2 digits, 6-7
#                        digits, a letter and 2 digits, with or without
#                        separators (00-000000-A-00, 000000000A00), anywhere in
#                        the cell.
#   mw_national_id       Malawi national ID: 8 alphanumeric characters with at
#                        least two letters and at least two digits (so dates,
#                        plain numbers and ordinary words do not match), not
#                        part of a longer alphanumeric or hyphenated token (so
#                        the XXXX-YYYY Neotree uid does not match).
#                        Case-insensitive.
PII_VALUE_PATTERNS <- list(
  phone_international = "^\\+?(263[0-9]{9}|265[0-9]{7,9})$",
  phone_local_zw      = "^0[67][0-9]{8}$",    # Zimbabwe mobile (07xx, 06xx)
  phone_local_mwi     = "^0[89][0-9]{8}$",    # Malawi mobile   (08xx, 09xx)
  email               = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}",
  nhs_number          = "^[0-9]{3}[- ][0-9]{3}[- ][0-9]{4}$",
  zw_national_id      = paste0("(?<![A-Za-z0-9])[0-9]{2}[- ]{0,2}[0-9]{6,7}",
                               "[- ]{0,2}[A-Za-z][- ]{0,2}[0-9]{2}(?![A-Za-z0-9])"),
  mw_national_id      = paste0("(?i)(?<![A-Za-z0-9-])",
                               "(?=(?:[A-Za-z0-9]*[A-Za-z]){2})",
                               "(?=(?:[A-Za-z0-9]*[0-9]){2})",
                               "[A-Za-z0-9]{8}(?![A-Za-z0-9-])")
)

# -- Columns exempt from the value-level patterns ------------------------------
# Normalised names.  These are the structural columns the pipeline keys on.
PII_VALUE_SCAN_EXEMPT <- c(
  "uid", "facility", "uniquekey",
  "startedat", "completedat", "ingestedat",
  "startedatdischarge", "completedatdischarge", "ingestedatdischarge",
  "scriptversion", "scriptid"
)

#' Logical mask of cells matching a value-level PII pattern (values trimmed)
pii_value_hits <- function(x, pattern) {
  vals <- trimws(as.character(x))
  !is.na(vals) & grepl(pattern, vals, perl = TRUE)
}

#' Tier 2 patterns from a dictionary's PII_Patterns sheet (NULL if unavailable)
load_pii_patterns <- function(dict_path) {
  tryCatch({
    pii_df <- readxl::read_excel(dict_path, sheet = "PII_Patterns")
    if (!is.null(pii_df) && "pattern" %in% names(pii_df) && nrow(pii_df) > 0)
      return(stats::na.omit(pii_df$pattern))
    NULL
  }, error = function(e) NULL)
}

PII_SHEET_PATTERNS <- load_pii_patterns(DICT_FILEPATH)
PII_TIER2_PATTERNS <- unique(c(PII_SHEET_PATTERNS, PII_FALLBACK_PATTERNS_DEFAULT))

# -- Completion marker written by Module 00a -----------------------------------
# One per input file, in the run output folder (always exists, even when
# reports are suppressed).  Plain DCF text: names, sizes and times only.
PII_MARKER_PATH <- file.path(RUN_OUTPUT_DIR, "00a_pii_removal_complete.dcf")

.pii_dict_md5 <- function(path) unname(as.character(tools::md5sum(path)))

#' Write the 00a completion marker (called by Module 00a only)
write_pii_marker <- function(input_path, run_id, n_cols_removed, n_values_redacted) {
  info <- file.info(input_path)
  rec  <- data.frame(
    completed_at        = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    completed_at_epoch  = sprintf("%.3f", as.numeric(Sys.time())),
    run_id              = run_id,
    pipeline_version    = PIPELINE_VERSION,
    input_path          = normalizePath(input_path, mustWork = TRUE),
    input_size_bytes    = sprintf("%.0f", info$size),
    input_mtime         = format(info$mtime, "%Y-%m-%d %H:%M:%S %Z"),
    input_mtime_epoch   = sprintf("%.3f", as.numeric(info$mtime)),
    dictionary_path     = normalizePath(cfg$dict_filepath, mustWork = TRUE),
    dictionary_md5      = .pii_dict_md5(cfg$dict_filepath),
    tier2_patterns      = length(PII_TIER2_PATTERNS),
    columns_removed     = n_cols_removed,
    values_redacted     = n_values_redacted,
    stringsAsFactors    = FALSE
  )
  write.dcf(rec, PII_MARKER_PATH)
  log_info("00a_pii: completion marker written: %s", PII_MARKER_PATH)
  invisible(PII_MARKER_PATH)
}

#' Map an output column name back to the raw-name forms the PII rules use
#'
#' Output names can differ from the raw names 00a checked: Module 01 renames
#' reserved-name collisions (facility.value -> facilityname.value), Module 15
#' strips .value / .valuedischarge, and Module 00b renames to harmonised names.
#' Each column is therefore tested as itself, as <base>.value (bare and
#' .valuedischarge names only), and (for a harmonised name) as
#' <question_key>.value, after undoing the Module 01 renames.
.pii_candidate_names <- function(nm) {
  res     <- cfg$reserved_column_renames
  res_inv <- if (length(res)) stats::setNames(names(res), unname(res)) else character(0)
  harm    <- cfg$harmonised_map
  undo    <- function(x) ifelse(x %in% names(res_inv), unname(res_inv[x]), x)

  base <- sub("\\.(valuedischarge|labeldischarge|value|label)$", "", nm)
  # A .label column keeps its suffix in every output, so it is tested exactly as
  # 00a tested it; only bare and .valuedischarge names are mapped to <base>.value.
  cand <- if (grepl("\\.(label|labeldischarge)$", nm)) nm else c(nm, paste0(base, ".value"))
  if (length(harm) && nm %in% harm)
    cand <- c(cand, paste0(names(harm)[match(nm, harm)], ".value"))
  unique(undo(cand))
}

#' Stop unless PII removal (Module 00a) has demonstrably run for this input
#'
#' Checks, in order:
#'   1. the 00a completion marker exists for this run's input file;
#'   2. the marker is not stale: same input path, size and modification time,
#'      written after the input was last modified, same dictionary (MD5);
#'   3. optionally (Module 01) that df is the very object 00a produced;
#'   4. no column matches Tier 1 (dictionary confidential flag) or Tier 2
#'      (column-name patterns), allowing for renaming and suffix stripping;
#'   5. no value in a non-exempt column matches PII_VALUE_PATTERNS.
#' Reports counts only, never values.
#'
#' @param df            data.frame about to be used or written
#' @param stage         short label for messages, e.g. "15_cleaned_output"
#' @param check_run_id  TRUE to require df to carry 00a's run id (Module 01)
#' @param value_exempt  extra columns left out of the value scan (step 5) only,
#'                      for tables in which a column holds the names of another
#'                      table's columns, which can have the shape of an ID.
#' @return              invisible(TRUE); otherwise stop()s
assert_pii_removed <- function(df, stage, check_run_id = FALSE,
                               value_exempt = character(0)) {

  fail <- function(fmt, ...) {
    msg <- sprintf(paste0("PII guard [%s]: ", fmt), stage, ...)
    log_error("%s", msg)
    stop(msg, call. = FALSE)
  }
  how_to_fix <- paste(
    "Run the full pipeline (run_pipeline.r or run_all.r) so that Module 00a",
    "removes PII from this input before any other module runs."
  )

  # -- 1. Marker exists ---------------------------------------------------------
  if (!file.exists(PII_MARKER_PATH))
    fail("Module 00a completion marker not found (%s). PII removal has not run for %s. %s",
         PII_MARKER_PATH, cfg$csv_filepath, how_to_fix)
  mk <- tryCatch(as.list(read.dcf(PII_MARKER_PATH)[1, ]),
                 error = function(e) NULL)
  need <- c("completed_at_epoch", "run_id", "input_path", "input_size_bytes",
            "input_mtime_epoch", "dictionary_md5")
  if (is.null(mk) || !all(need %in% names(mk)))
    fail("Module 00a completion marker is unreadable or incomplete (%s). %s",
         PII_MARKER_PATH, how_to_fix)

  # -- 2. Marker matches the current input and dictionary -------------------
  if (!file.exists(cfg$csv_filepath))
    fail("input file not found: %s", cfg$csv_filepath)
  info <- file.info(cfg$csv_filepath)
  if (!identical(mk$input_path, normalizePath(cfg$csv_filepath)))
    fail("the 00a marker was written for a different input (%s), not %s. %s",
         mk$input_path, cfg$csv_filepath, how_to_fix)
  if (as.numeric(mk$completed_at_epoch) < as.numeric(info$mtime))
    fail("the 00a marker (written %s) is older than the input file (modified %s). %s",
         format(as.POSIXct(as.numeric(mk$completed_at_epoch), origin = "1970-01-01")),
         format(info$mtime), how_to_fix)
  if (as.numeric(mk$input_size_bytes) != info$size ||
      abs(as.numeric(mk$input_mtime_epoch) - as.numeric(info$mtime)) > 1)
    fail("the input file has changed since Module 00a ran (size or modification time differ). %s",
         how_to_fix)
  if (!identical(mk$dictionary_md5, .pii_dict_md5(cfg$dict_filepath)))
    fail("the dictionary (%s) has changed since Module 00a ran. %s",
         cfg$dict_filepath, how_to_fix)

  # -- 3. The object is the one 00a produced (Module 01 only) ----------------
  if (check_run_id && !identical(attr(df, "neotree_pii_run_id"), mk$run_id))
    fail(paste("the data frame was not produced by the Module 00a run recorded in the",
               "marker (run id mismatch or missing). It may have been loaded directly",
               "from the raw CSV. %s"), how_to_fix)

  # -- 4. Column names: Tier 1 and Tier 2 ---------------------------------------
  conf_harm <- dict_variables$harmonised_variable_name[
    !is.na(dict_variables$confidential) & dict_variables$confidential == TRUE]
  tier1_base <- unique(c(
    sub("\\.(valuedischarge|labeldischarge|value|label)$", "", cfg$pii_columns),
    stats::na.omit(conf_harm)
  ))
  strip <- function(x) sub("\\.(valuedischarge|labeldischarge|value|label)$", "", x)

  bad_t1 <- character(0); bad_t2 <- character(0)
  for (nm in names(df)) {
    cand <- .pii_candidate_names(nm)
    if (any(strip(cand) %in% tier1_base)) bad_t1 <- c(bad_t1, nm)
    if (any(vapply(PII_TIER2_PATTERNS, function(p)
          any(grepl(p, cand, ignore.case = TRUE, perl = TRUE)), logical(1))))
      bad_t2 <- c(bad_t2, nm)
  }
  if (length(bad_t1) || length(bad_t2))
    fail(paste("%d column(s) match the dictionary confidential flag (Tier 1) and %d",
               "match a PII name pattern (Tier 2): %s. Nothing has been written."),
         length(bad_t1), length(bad_t2),
         paste(unique(c(bad_t1, bad_t2)), collapse = ", "))

  # -- 5. Values: PII_VALUE_PATTERNS on non-exempt columns -------------------
  harm_exempt <- if (length(cfg$harmonised_map))
    unname(cfg$harmonised_map[intersect(PII_VALUE_SCAN_EXEMPT, names(cfg$harmonised_map))])
    else character(0)
  exempt <- c(PII_VALUE_SCAN_EXEMPT, harm_exempt, value_exempt)
  hits <- character(0)
  for (col in setdiff(names(df), exempt)) {
    x <- df[[col]]
    if (inherits(x, c("POSIXt", "Date")) || is.logical(x) || is.list(x)) next
    # Same test as pii_value_hits(), run on distinct values only (much faster
    # on large files, where most columns hold a handful of codes).
    v <- trimws(as.character(x))
    u <- unique(v[!is.na(v)])
    if (length(u) == 0) next
    for (pat_name in names(PII_VALUE_PATTERNS)) {
      hit_u <- grepl(PII_VALUE_PATTERNS[[pat_name]], u, perl = TRUE)
      if (!any(hit_u)) next
      n <- sum(v %in% u[hit_u])
      hits <- c(hits, sprintf("%s: %d cell(s) match '%s'", col, n, pat_name))
    }
  }
  if (length(hits))
    fail("%d column/pattern combination(s) contain PII-like values (counts only): %s. Nothing has been written.",
         length(hits), paste(hits, collapse = "; "))

  log_info("PII guard [%s]: passed (marker %s, run %s; %d cols checked).",
           stage, basename(PII_MARKER_PATH), mk$run_id, ncol(df))
  invisible(TRUE)
}
