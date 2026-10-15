# =============================================================================
# NEOTREE CLEANING PIPELINE -- PII guard tests
# =============================================================================
# PURPOSE:
#   Tests the PII patterns, the Module 00a completion marker and
#   assert_pii_removed() on synthetic data.
#
# METHOD:
#   1. Pattern unit tests: the mother's date of birth column-name pattern, the
#      Zimbabwe and Malawi national ID value patterns, the phone patterns and
#      value trimming.
#   2. A full run: expected columns removed, expected values redacted, key
#      columns left alone, guard passed at every write.
#   3. The guard stops when Module 00a did not run.
#   4. The guard stops when the completion marker is stale.
#   5. The guard stops when a PII column or value is added before a write.
#   6. run_all.r reports the file as failed in the same situations.
#   Sections 2 to 6 each run in a copy of the pipeline under tempdir().
#
# INPUTS:
#   dictionaries/dictionary_zim_admissions.xlsx (column names and value-map
#   codes only).  The input rows are generated, with invented identifiers
#   added.
#
# OUTPUTS:
#   PASS/FAIL lines on the console.  Exit status 0 = all tests passed;
#   1 = at least one failure.
#
# USAGE (from the cleaning_pipeline_R folder):
#   Rscript tests/test_pii_guard.r
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
})

.args     <- commandArgs(trailingOnly = FALSE)
.file_arg <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
PIPELINE_ROOT <- if (length(.file_arg))
  normalizePath(file.path(dirname(.file_arg[1]), "..")) else normalizePath(".")
stopifnot(file.exists(file.path(PIPELINE_ROOT, "run_pipeline.r")))

RSCRIPT <- file.path(R.home("bin"), "Rscript")
INPUT_NAME <- "zim_db_admissions_20261008.csv"
FREE_TEXT_COL <- "CSReasonOther.value"   # free text, passthrough to the output

# -- Test bookkeeping ----------------------------------------------------------
results <- data.frame(test = character(0), ok = logical(0), detail = character(0),
                      stringsAsFactors = FALSE)
check <- function(test, ok, detail = "") {
  ok <- isTRUE(ok)
  results[nrow(results) + 1, ] <<- list(test, ok, detail)
  cat(sprintf("  [%s] %s%s\n", if (ok) "PASS" else "FAIL", test,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

# -- Throw-away pipeline copy --------------------------------------------------
fresh_copy <- function(tag) {
  dest <- file.path(tempdir(), paste0("neotree_pii_test_", tag))
  unlink(dest, recursive = TRUE)
  dir.create(dest, recursive = TRUE)
  keep <- list.files(PIPELINE_ROOT, all.files = FALSE)
  keep <- keep[grepl("^(0|1)[0-9]|^dictionaries$|^neotree_scripts$|^run_.*\\.r$", keep)]
  for (k in keep) file.copy(file.path(PIPELINE_ROOT, k), dest, recursive = TRUE)
  dir.create(file.path(dest, "input"))
  dest
}

# -- Synthetic input (dictionary-driven, no real data) -------------------------
make_synthetic_raw <- function(dict_path, n = 60L, seed = 20261008L) {
  set.seed(seed)
  v  <- readxl::read_excel(dict_path, sheet = "Variables")
  vm <- readxl::read_excel(dict_path, sheet = "ValueMaps")
  v  <- v[!is.na(v$raw_value_column) &
          (is.na(v$confidential) | v$confidential != TRUE), ]
  ts <- format(as.POSIXct("2025-01-01", tz = "UTC") + sample(0:3e7, n),
               "%Y-%m-%d %H:%M:%S")
  df <- data.frame(
    uid          = sprintf("%04X-%04d", sample(4096:65535, n), sample(1:9999, n)),
    facility     = sample(c("SMCH", "CPH"), n, replace = TRUE),
    unique_key   = sprintf("k%06d", seq_len(n)),
    started_at   = ts, completed_at = ts, ingested_at = ts,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  for (i in seq_len(nrow(v))) {
    key   <- v$question_key[i]
    rt    <- v$r_type[i]
    codes <- unique(stats::na.omit(vm$raw_code[vm$question_key == key]))
    val <- if (length(codes) > 0) {
      sample(codes, n, replace = TRUE)
    } else if (identical(rt, "numeric")) {
      lo <- suppressWarnings(as.numeric(v$suggested_plausible_min[i]))
      hi <- suppressWarnings(as.numeric(v$suggested_plausible_max[i]))
      if (is.na(lo)) lo <- 1
      if (is.na(hi) || hi <= lo) hi <- lo + 10
      as.character(round(stats::runif(n, lo, hi), 1))
    } else if (identical(rt, "datetime")) {
      ts
    } else {
      sample(c("seen on ward", "reviewed", "none"), n, replace = TRUE)
    }
    val[stats::runif(n) < 0.15] <- NA
    df[[v$raw_value_column[i]]] <- val
  }
  # Raw database exports use CamelCase keys; 00a normalises them.
  names(df)[names(df) == "csreasonother.value"] <- FREE_TEXT_COL
  names(df)[names(df) == "motherdobyn.value"]   <- "MotherDOBYN.value"

  # -- Injected, invented identifiers --------------------------------------
  # Mother's DOB columns, which are not in the dictionary.
  df[["MotherDOB.value"]] <- format(as.Date("1990-01-01") + sample(0:5000, n))
  df[["MotherDOB.label"]] <- "Mother Date of Birth"
  df[["MotherDOBYN.value"]] <- sample(c("Y", "N"), n, replace = TRUE)

  # Free-text field: rows 1-6 carry identifiers, rows 7-12 must survive.
  df[[FREE_TEXT_COL]][1:12] <- c(
    "63-123456-A-42",                 # ZW with hyphens
    "mother ID 631234567B53 noted",   # ZW, no separators, embedded in text
    "ID 63 1234567 C 45",             # ZW with spaces
    "MW12AB34",                       # MW NRIS-like, whole cell
    "nrb id: kx7p2m9q given",         # MW-like, lower case, embedded
    "  0771234567  ",                 # ZW mobile with padding (trim test)
    "seen 2024-01-01 at 10:00",       # date: must survive
    "ward 12 bed 3",                  # must survive
    "baby1",                          # short token: must survive
    "3f2a9c1e-77aa-4b1e-9c2d-1234567890ab",  # UUID: must survive
    "ABCDEFGH",                       # 8 letters, no digits: must survive
    "12345678A"                       # 9 chars: must survive
  )
  # An 8-character alphanumeric uid without a hyphen: it matches the MW ID
  # pattern, but uid is a key column -- must survive.
  df$uid[13] <- "AB12CD34"
  # An empty uid: Module 02 removes the row and writes it to its frame-shift
  # file, which exercises the guard on that write as well.
  df$uid[14] <- NA
  df
}

# -- Run an R snippet in a fresh R process inside a pipeline copy -------------
run_r <- function(root, code, name) {
  f <- file.path(root, paste0("_", name, ".r"))
  writeLines(code, f)
  out <- suppressWarnings(system2(RSCRIPT, shQuote(f), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status"); if (is.null(status)) status <- 0L
  writeLines(out, file.path(root, paste0("_", name, ".log")))
  list(status = status, out = paste(out, collapse = "\n"))
}

header <- function(root) c(
  sprintf('setwd("%s")', root),
  'COUNTRY <- "ZIM"; DATASET <- "admissions"; DATA_SOURCE <- "database"',
  sprintf('CSV_FILEPATH <- "input/%s"', INPUT_NAME),
  # Switch on the optional writes so that every guarded write is exercised.
  'SAVE_HARMONISED <- TRUE; SAVE_STAGE1_CHECKPOINT <- TRUE'
)

MODULES_02_TO_14A <- c(
  "02_frame_shift_correction/02_frame_shift_correction.r",
  "03_duplicate_column_merging/03_duplicate_column_merging.r",
  "04_dictionary_value_cleaning/04_dictionary_value_cleaning.r",
  "05_forward_fill_placeholders/05_forward_fill_placeholders.r",
  "06_forward_fill_numeric_datetime/06_forward_fill_numeric_datetime.r",
  "07_drop_label_columns/07_drop_label_columns.r",
  "08_drop_autopopulated_columns/08_drop_autopopulated_columns.r",
  "09_data_type_assignment/09_data_type_assignment.r",
  "10_remove_duplicate_rows/10_remove_duplicate_rows.r",
  "11_numeric_validation/11_numeric_validation.r",
  "12_boolean_validation/12_boolean_validation.r",
  "13_categorical_object_validation/13_categorical_object_validation.r",
  "14_datetime_validation/14_datetime_validation.r",
  "14a_resolve_neolab_datebct/14a_resolve_neolab_datebct.r"
)
up_to_14a <- c(
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")',
  sprintf('source("%s")', MODULES_02_TO_14A)
)

new_root <- function(tag) {
  root <- fresh_copy(tag)
  raw  <- make_synthetic_raw(file.path(root, "dictionaries", "dictionary_zim_admissions.xlsx"))
  readr::write_csv(raw, file.path(root, "input", INPUT_NAME), na = "")
  root
}
out_csv <- function(root) file.path(root, "output", sub("\\.csv$", "", INPUT_NAME),
                                    sub("\\.csv$", "_cleaned.csv", INPUT_NAME))
marker  <- function(root) file.path(root, "output", sub("\\.csv$", "", INPUT_NAME),
                                    "00a_pii_removal_complete.dcf")

cat("\n=== Neotree PII guard tests ===\n")
cat(sprintf("Pipeline under test: %s\n\n", PIPELINE_ROOT))

# =============================================================================
# 1. Pattern unit tests (no pipeline run)
# =============================================================================
cat("1. Pattern unit tests\n")
local({
  e <- new.env()
  # Only the PII section of 00_setup.r is needed; evaluate it in isolation.
  src <- readLines(file.path(PIPELINE_ROOT, "00_setup", "00_setup.r"))
  from <- grep("^PII_FALLBACK_PATTERNS_DEFAULT <- c\\(", src)
  to   <- grep("^pii_value_hits <- function", src) + 3L
  eval(parse(text = src[from:to]), envir = e)

  dob <- tail(e$PII_FALLBACK_PATTERNS_DEFAULT, 1)
  should <- c("motherdob.value", "motherdob.label", "mothersdob.value", "matdob.value",
              "mumdob.label", "motherdateofbirth.value")
  shouldnt <- c("motherdobyn.value", "motherdobyn.label", "dobtob.value", "dobyn.value",
                "matagedate.value", "biddobtob.value", "dob.value", "motherdob",
                "motherdobknown.value")
  check("motherdob pattern matches all mother-DOB forms",
        all(grepl(dob, should, perl = TRUE)),
        paste(should[!grepl(dob, should, perl = TRUE)], collapse = ", "))
  check("motherdob pattern leaves motherdobyn, dobtob, matagedate etc. alone",
        !any(grepl(dob, shouldnt, perl = TRUE)),
        paste(shouldnt[grepl(dob, shouldnt, perl = TRUE)], collapse = ", "))

  zw <- e$PII_VALUE_PATTERNS$zw_national_id
  mw <- e$PII_VALUE_PATTERNS$mw_national_id
  zw_yes <- c("63-123456-A-42", "63-1234567 A 53", "631234567A53", "63 1234567 C 45",
              "50-025544-Q-12", "id 63-123456 B 12 given", " 63123456a42 ")
  zw_no  <- c("2024-01-01", "0771234567", "63-12345-A-42", "631234567AB53",
              "X631234567A53", "XXXX-0001")
  mw_yes <- c("MW12AB34", "AB12CD34", "kx7p2m9q", "nrb XK7P2M9Q ok", " 9ZZ4KQ7T ")
  mw_no  <- c("ABCDEFGH", "12345678", "20240101", "A1234567", "XXXX-0001",
              "3f2a9c1e-77aa-4b1e-9c2d-1234567890ab", "AB12CD345", "ward 12",
              "PRETERM", "Y", "2024-01-01 10:00:00")
  check("ZW ID pattern: positives", all(e$pii_value_hits(zw_yes, zw)),
        paste(zw_yes[!e$pii_value_hits(zw_yes, zw)], collapse = " | "))
  check("ZW ID pattern: negatives", !any(e$pii_value_hits(zw_no, zw)),
        paste(zw_no[e$pii_value_hits(zw_no, zw)], collapse = " | "))
  check("MW ID pattern: positives", all(e$pii_value_hits(mw_yes, mw)),
        paste(mw_yes[!e$pii_value_hits(mw_yes, mw)], collapse = " | "))
  check("MW ID pattern: negatives (dates, numbers, words, uid, UUID)",
        !any(e$pii_value_hits(mw_no, mw)),
        paste(mw_no[e$pii_value_hits(mw_no, mw)], collapse = " | "))
  ph <- e$PII_VALUE_PATTERNS$phone_international
  ph_yes <- c("+263771234567", "263771234567", "+265991234567", "265991234567", "2651234567")
  ph_no  <- c("1234567", "12345678", "20231019", "19102023", "87654321", "123456789012",
              "0771234567", "26312", "+44771234567", "2637712345678901")
  check("phone_international: +263 / +265 numbers match", all(e$pii_value_hits(ph_yes, ph)),
        paste(ph_yes[!e$pii_value_hits(ph_yes, ph)], collapse = " | "))
  check("phone_international: plain 7-15 digit numbers, dates as digits and other codes do not match",
        !any(e$pii_value_hits(ph_no, ph)), paste(ph_no[e$pii_value_hits(ph_no, ph)], collapse = " | "))
  check("local Zimbabwe and Malawi mobile shapes match",
        e$pii_value_hits("0771234567", e$PII_VALUE_PATTERNS$phone_local_zw) &&
        e$pii_value_hits("0991234567", e$PII_VALUE_PATTERNS$phone_local_mwi))
  check("hospital-number columns are removed by name (Tier 2 pattern hospnum)",
        all(vapply(c("mathospnum.value", "mathospnum.label", "babyhospnum.value"),
                   function(n) any(vapply(e$PII_FALLBACK_PATTERNS_DEFAULT,
                                          function(p) grepl(p, n, perl = TRUE), logical(1))),
                   logical(1))))
  staff_yes <- c("firm.value", "firm.label", "concall.value", "concall.label",
                 "hcwsigdis.value", "hcwsigdis.label", "hcwsigdis.valuedischarge",
                 "dataentryname.value", "dataentryname.label",
                 "dataentrynameother.value", "dataentrynameother.label")
  staff_no  <- c("confirm.value", "firmness.value", "affirm.label", "concallback.value", "firm",
                 "hcwsig.value", "dataentrydate.value", "hcwsigdisyn.value")
  hit <- function(n) any(vapply(e$PII_FALLBACK_PATTERNS_DEFAULT,
                                function(p) grepl(p, n, perl = TRUE), logical(1)))
  check("staff-identifier columns are removed by name",
        all(vapply(staff_yes, hit, logical(1))))
  check("the staff-identifier pattern does not match other column names",
        !any(vapply(staff_no, hit, logical(1))),
        paste(staff_no[vapply(staff_no, hit, logical(1))], collapse = ", "))
  check("values are trimmed before matching (padded phone number)",
        e$pii_value_hits("  0771234567  ", e$PII_VALUE_PATTERNS$phone_local_zw))
})

# =============================================================================
# 2. Normal full run passes, with the expected removals and redactions
# =============================================================================
cat("\n2. Normal full run (run_pipeline.r)\n")
root_ok <- new_root("normal")
r <- run_r(root_ok, c(header(root_ok), 'source("run_pipeline.r")'), "normal_run")
check("normal run completes", r$status == 0, if (r$status != 0) "see _normal_run.log" else "")
if (file.exists(out_csv(root_ok))) {
  cl <- readr::read_csv(out_csv(root_ok), col_types = readr::cols(.default = "c"),
                        show_col_types = FALSE)
  check("motherdob removed from the cleaned output",
        !any(grepl("^motherdob($|\\.)", names(cl))))
  check("motherdobyn kept in the cleaned output", "motherdobyn" %in% names(cl))
  ft <- tolower(sub("\\.value$", "", FREE_TEXT_COL))
  raw <- readr::read_csv(file.path(root_ok, "input", INPUT_NAME),
                         col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  key_raw <- paste(raw$uid, raw$facility)
  key_cl  <- paste(cl$uid, cl$facility)
  got <- cl[[ft]][match(key_raw[1:12], key_cl)]
  check("ZW and MW IDs (and padded phone) redacted in the free-text field",
        all(is.na(got[1:6])), sprintf("non-NA in rows: %s",
                                      paste(which(!is.na(got[1:6])), collapse = ",")))
  check("ordinary free text (date, ward, short token, UUID, words) survives",
        all(!is.na(got[7:12])), sprintf("NA in rows: %s",
                                        paste(6 + which(is.na(got[7:12])), collapse = ",")))
  check("8-char alphanumeric uid (matches MW pattern) is never redacted",
        "AB12CD34" %in% cl$uid)
  rep <- readLines(file.path(root_ok, "output", sub("\\.csv$", "", INPUT_NAME),
                             "reports", "00a_pii_audit_report.txt"))
  check("00a audit report lists motherdob.value and motherdob.label as removed",
        any(grepl("\\[pattern\\] motherdob\\.value", rep)) &&
        any(grepl("\\[pattern\\] motherdob\\.label", rep)))
  check("00a audit report shows the uid match as exempt, not redacted",
        any(grepl("uid .*matching 'mw_national_id'", rep)))
  log <- readLines(file.path(root_ok, "output", sub("\\.csv$", "", INPUT_NAME),
                             paste0(sub("\\.csv$", "", INPUT_NAME), ".log")))
  for (st in c("01_input", "02_frame_shift_rows", "10_stage1_checkpoint",
               "15_cleaned_output", "00b_harmonised_output",
               "16_na_reasons_wide", "16_na_reasons_summary", "16_na_coded_output")) {
    check(sprintf("guard passed at stage %s", st),
          any(grepl(sprintf("PII guard \\[%s\\]: passed", st), log)))
  }
  check("completion marker written", file.exists(marker(root_ok)))
} else {
  check("cleaned output written", FALSE, "no cleaned CSV")
}

# =============================================================================
# 3. Guard stops when 00a was skipped
# =============================================================================
cat("\n3. 00a skipped\n")
root_skip <- new_root("skip00a")
r <- run_r(root_skip, c(header(root_skip),
  'source("00_setup/00_setup.r")',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "skip_00a")
check("Module 01 stops when df_raw does not exist (no silent raw load)",
      r$status != 0 && grepl("df_raw not found", r$out))

r <- run_r(root_skip, c(header(root_skip),
  'source("00_setup/00_setup.r")',
  'df_raw <- readr::read_csv(CSV_FILEPATH, col_types = readr::cols(.default = "c"))',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "raw_loaded_no_marker")
check("Module 01 stops when raw data is loaded by hand and no marker exists",
      r$status != 0 && grepl("completion marker not found", r$out))

# Marker present from a genuine 00a run, but df_raw then replaced by raw data.
r <- run_r(root_skip, c(header(root_skip),
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'df_raw <- readr::read_csv(CSV_FILEPATH, col_types = readr::cols(.default = "c"))',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "raw_loaded_with_marker")
check("Module 01 stops when df_raw is not the object 00a produced (run id)",
      r$status != 0 && grepl("run id mismatch", r$out))

r <- run_r(root_skip, c(header(root_skip), up_to_14a,
  'file.remove(PII_MARKER_PATH)',
  'source("15_final_merge_output/15_final_merge_output.r")'), "module15_no_marker")
check("Module 15 stops before writing when the marker is missing",
      r$status != 0 && grepl("PII guard \\[15_cleaned_output\\].*marker not found", r$out) &&
      !file.exists(out_csv(root_skip)))

# =============================================================================
# 4. Guard stops when the marker is stale
# =============================================================================
cat("\n4. Stale marker\n")
root_stale <- new_root("stale")
r <- run_r(root_stale, c(header(root_stale),
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'Sys.setFileTime(CSV_FILEPATH, Sys.time() + 120)',   # input changes after 00a
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "stale_input")
check("guard stops when the input is newer than the marker",
      r$status != 0 && grepl("older than the input file", r$out))

root_stale <- new_root("stale_size")   # fresh copy: the test above moved the input mtime
r <- run_r(root_stale, c(header(root_stale),
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'm <- read.dcf(PII_MARKER_PATH)',
  'cat("x\\n", file = CSV_FILEPATH, append = TRUE)',
  # put the original modification time back, so only the size differs
  'Sys.setFileTime(CSV_FILEPATH, as.POSIXct(as.numeric(m[, "input_mtime_epoch"]), origin = "1970-01-01"))',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "stale_size")
check("guard stops when the input size changed since 00a (same modification time)",
      r$status != 0 && grepl("has changed since Module 00a ran", r$out))

root_stale <- new_root("stale_dict")
r <- run_r(root_stale, c(header(root_stale),
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'm <- read.dcf(PII_MARKER_PATH); m[, "dictionary_md5"] <- "0"; write.dcf(m, PII_MARKER_PATH)',
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "stale_dict")
check("guard stops when the dictionary changed since 00a",
      r$status != 0 && grepl("dictionary .* has changed", r$out))

root_stale <- new_root("stale_other")
r <- run_r(root_stale, c(header(root_stale),
  'source("00_setup/00_setup.r")',
  'source("00a_pii_detection_removal/00a_pii_detection_removal.r")',
  'marker_a <- PII_MARKER_PATH',
  'file.copy(CSV_FILEPATH, "input/zim_db_admissions_20261009.csv")',
  'CSV_FILEPATH <- "input/zim_db_admissions_20261009.csv"',
  'source("00_setup/00_setup.r")',
  'file.copy(marker_a, PII_MARKER_PATH, overwrite = TRUE)',   # marker of file A
  'source("01_standardise_column_headers/01_standardise_column_headers.r")'), "marker_other_input")
check("guard stops when the marker belongs to a different input file",
      r$status != 0 && grepl("different input", r$out))

# =============================================================================
# 5. Guard stops when a PII column or value is injected before a write
# =============================================================================
cat("\n5. Injected PII before the Module 15 write\n")
inject_and_run15 <- function(tag, inject) {
  root <- new_root(tag)
  r <- run_r(root, c(header(root), up_to_14a, inject,
                     'source("15_final_merge_output/15_final_merge_output.r")'), tag)
  list(r = r, written = file.exists(out_csv(root)))
}
x <- inject_and_run15("inj_tier1", 'df[["kincell.value"]] <- "x"')   # confidential in ZIM dict
check("Tier 1 column injected -> stop, nothing written",
      x$r$status != 0 && grepl("Tier 1", x$r$out) && !x$written)
x <- inject_and_run15("inj_tier2", 'df[["babyfathername.value"]] <- "x"')  # name pattern
check("Tier 2 column injected -> stop, nothing written",
      x$r$status != 0 && grepl("Tier 2", x$r$out) && grepl("babyfathername", x$r$out) &&
      !x$written)
x <- inject_and_run15("inj_dob", 'df[["motherdob.value"]] <- "1990-01-01"')
check("motherdob column injected after 00a -> stop (suffix-stripped name caught)",
      x$r$status != 0 && grepl("motherdob", x$r$out) && !x$written)
x <- inject_and_run15("inj_value",
  sprintf('df[["%s"]][2] <- "call 0771234567"; df[["%s"]][3] <- "0771234567"',
          tolower(FREE_TEXT_COL), tolower(FREE_TEXT_COL)))
check("phone number value injected -> stop, counts only, nothing written",
      x$r$status != 0 && grepl("phone_local_zw", x$r$out) &&
      !grepl("0771234567", x$r$out) && !x$written)
x <- inject_and_run15("inj_id_value",
  sprintf('df[["%s"]][4] <- "MW12AB34"', tolower(FREE_TEXT_COL)))
check("MW ID value injected -> stop, value not printed, nothing written",
      x$r$status != 0 && grepl("mw_national_id", x$r$out) &&
      !grepl("MW12AB34", x$r$out) && !x$written)

# =============================================================================
# 6. Batch runner: the guard applies in the same way
# =============================================================================
cat("\n6. Batch runner (run_all.r)\n")
root_all <- new_root("runall")
r <- run_r(root_all, c(sprintf('setwd("%s")', root_all), 'source("run_all.r")'), "run_all_ok")
check("run_all.r: normal batch run succeeds",
      r$status == 0 && grepl("1/1 succeeded", r$out) && file.exists(out_csv(root_all)))

# Neutralise 00a so that it loads the raw CSV but removes nothing (simulates a
# broken or skipped PII step inside a batch run).
root_all2 <- new_root("runall_broken00a")
writeLines(c('source("00_setup/00_setup.r")',
             'df_raw <- readr::read_csv(cfg$csv_filepath, col_types = readr::cols(.default = "c"))',
             'names(df_raw) <- tolower(gsub("[ _]", "", names(df_raw)))'),
           file.path(root_all2, "00a_pii_detection_removal", "00a_pii_detection_removal.r"))
r <- run_r(root_all2, c(sprintf('setwd("%s")', root_all2), 'source("run_all.r")'), "run_all_broken")
check("run_all.r with a broken 00a: file fails, no cleaned output written",
      grepl("0/1 succeeded", r$out) && grepl("PII guard \\[01_input\\]", r$out) &&
      !file.exists(out_csv(root_all2)))

# A marker left over from an earlier good run must not rescue a failing 00a.
root_all3 <- new_root("runall_failing00a")
r1 <- run_r(root_all3, c(sprintf('setwd("%s")', root_all3), 'source("run_all.r")'), "run_all_first")
unlink(file.path(root_all3, "output", sub("\\.csv$", "", INPUT_NAME), "*.csv"))
f00a <- file.path(root_all3, "00a_pii_detection_removal", "00a_pii_detection_removal.r")
src <- readLines(f00a)
at  <- grep("^df_raw <- remove_pii\\(", src)
writeLines(c(src[seq_len(at - 1)], 'stop("simulated failure inside 00a")', src[at:length(src)]), f00a)
r <- run_r(root_all3, c(sprintf('setwd("%s")', root_all3), 'source("run_all.r")'), "run_all_failing")
check("run_all.r: 00a failing mid-way removes the old marker and writes nothing",
      r1$status == 0 && grepl("0/1 succeeded", r$out) &&
      !file.exists(marker(root_all3)) && !file.exists(out_csv(root_all3)))

# =============================================================================
# Summary
# =============================================================================
n_fail <- sum(!results$ok)
cat(sprintf("\n=== %d test(s): %d passed, %d failed ===\n",
            nrow(results), sum(results$ok), n_fail))
if (n_fail > 0) {
  cat("Failed:\n"); cat(paste0("  - ", results$test[!results$ok], "\n"), sep = "")
  cat(sprintf("Logs of each scenario are in %s\n", tempdir()))
}
quit(status = if (n_fail > 0) 1L else 0L)
