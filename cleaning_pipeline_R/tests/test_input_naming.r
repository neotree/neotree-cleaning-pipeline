# =============================================================================
# NEOTREE CLEANING PIPELINE -- input naming and export-format tests
# =============================================================================
# PURPOSE:
#   Tests that the pipeline reads an input file whatever its name form and
#   export style.
#
# METHOD:
#   1. run_all.r parse_input_filename(): names without a source token, names
#      with a db/mb token, the three date stamp forms, rejected names.
#   2. 00_setup.r .detect_data_source(): database, metabase, mixed, unknown.
#   3. 00_setup.r .resolve_paired_csv(): admissions/discharges pairing with
#      and without the source token.
#   4. A run_all.r batch on synthetic files in database, Metabase and mixed
#      style (Metabase column names, ISO datetimes, thousands separators),
#      checking that datetimes and numbers parse in every case.  Runs in a
#      copy of the pipeline under tempdir().
#   5. The shape-routed value parsers in 00_setup.r, the Module 04 list
#      normalisation and the Module 14 derived column hepbdate_date.
#
# INPUTS:
#   The ZIM admissions and discharges dictionaries (column names and value-map
#   codes only).  All data values are generated.
#
# OUTPUTS:
#   PASS/FAIL lines on the console.  Exit status 0 = all tests passed;
#   1 = at least one failure.
#
# USAGE (from the cleaning_pipeline_R folder):
#   Rscript tests/test_input_naming.r
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(readxl)
})

.args     <- commandArgs(trailingOnly = FALSE)
.file_arg <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
PIPELINE_ROOT <- if (length(.file_arg))
  normalizePath(file.path(dirname(.file_arg[1]), "..")) else normalizePath(".")
stopifnot(file.exists(file.path(PIPELINE_ROOT, "run_all.r")))

RSCRIPT <- file.path(R.home("bin"), "Rscript")

# -- Test bookkeeping ----------------------------------------------------------
results <- data.frame(test = character(0), ok = logical(0), detail = character(0),
                      stringsAsFactors = FALSE)
check <- function(test, ok, detail = "") {
  ok <- isTRUE(ok)
  results[nrow(results) + 1, ] <<- list(test, ok, detail)
  cat(sprintf("  [%s] %s%s\n", if (ok) "PASS" else "FAIL", test,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

# -- Load selected top-level definitions from a pipeline script ----------------
# Evaluates only the named assignments, so run_all.r is not executed and
# 00_setup.r does not need a dictionary or a log.
load_defs <- function(path, names, envir) {
  exprs <- parse(path, keep.source = FALSE)
  for (ex in exprs) {
    if (is.call(ex) && as.character(ex[[1]]) %in% c("<-", "=") &&
        is.name(ex[[2]]) && as.character(ex[[2]]) %in% names) {
      eval(ex, envir = envir)
    }
  }
  missing <- setdiff(names, ls(envir, all.names = TRUE))
  if (length(missing)) stop("Not found in ", path, ": ", paste(missing, collapse = ", "))
}

e <- new.env()
e$log_info <- function(...) invisible(NULL)
load_defs(file.path(PIPELINE_ROOT, "run_all.r"),
          c("INPUT_DIR", "KNOWN_DATASETS", "parse_input_filename"), e)
load_defs(file.path(PIPELINE_ROOT, "00_setup", "00_setup.r"),
          c("PAIRED_DATASET", ".resolve_paired_csv", ".detect_data_source"), e)

cat("\n=== Neotree input naming and value parsing tests ===\n")
cat(sprintf("Pipeline under test: %s\n\n", PIPELINE_ROOT))

# =============================================================================
# 1. File-name parsing
# =============================================================================
cat("1. File-name parsing\n")

# Names with a dataset in KNOWN_DATASETS, then names with any other dataset.
runnable <- c(
  "mwi_admissions_2026-10-08.csv"                   = "admissions",
  "mwi_combined_maternity_outcomes_2026-10-08.csv"  = "combined_maternity_outcomes",
  "mwi_dhis2_maternal_outcomes_2026-10-08.csv"      = "dhis2_maternal_outcomes",
  "mwi_discharges_2026-10-08.csv"                   = "discharges",
  "mwi_joined_admissions_discharges_2026-10-08.csv" = "joined_admissions_discharges",
  "mwi_maternal_outcomes_2026-10-08.csv"            = "maternal_outcomes",
  "mwi_maternity_completeness_2026-10-08.csv"       = "maternity_completeness",
  "mwi_neolab_2026-10-08.csv"                       = "neolab",
  "mwi_phc_admissions_2026-10-08.csv"               = "phc_admissions",
  "mwi_phc_discharges_2026-10-08.csv"               = "phc_discharges",
  "zim_admissions_2026-10-08.csv"                   = "admissions",
  "zim_baseline_2026-10-08.csv"                     = "baseline",
  "zim_discharges_2026-10-08.csv"                   = "discharges",
  "zim_infections_2026-10-08.csv"                   = "infections",
  "zim_joined_admissions_discharges_2026-10-08.csv" = "joined_admissions_discharges",
  "zim_maternal_outcomes_2026-10-08.csv"            = "maternal_outcomes",
  "zim_neolab_2026-10-08.csv"                       = "neolab",
  "zim_twenty_8_day_follow_up_2026-10-08.csv"       = "twenty_8_day_follow_up"
)
no_dictionary <- c(
  "mwi_combined_diagnoses_2026-10-08.csv", "mwi_diagnoses_2026-10-08.csv",
  "mwi_drugs_2026-10-08.csv", "mwi_eq_tips_3l_2026-10-08.csv",
  "mwi_eq_tips_5l_2026-10-08.csv", "mwi_field_metadata_2026-10-08.csv",
  "mwi_fluids_2026-10-08.csv", "mwi_peds_sql_2026-10-08.csv",
  "mwi_vital_signs_2026-10-08.csv", "zim_combined_diagnoses_2026-10-08.csv",
  "zim_diagnoses_2026-10-08.csv", "zim_field_metadata_2026-10-08.csv",
  "zim_hcai_2026-10-08.csv", "zim_joined_admissions_discharges_extra_columns_2026-10-08.csv",
  "zim_joined_peas_admissions_discharges_2026-10-08.csv",
  "zim_old_smch_admissions_2026-10-08.csv", "zim_old_smch_discharges_2026-10-08.csv",
  "zim_old_smch_matched_admissions_discharges_2026-10-08.csv",
  "zim_peads_admissions_2026-10-08.csv", "zim_peads_admissions_symptomsorsign_2026-10-08.csv",
  "zim_peads_discharges_2026-10-08.csv"
)

bad <- character(0)
for (f in names(runnable)) {
  p <- e$parse_input_filename(f)
  exp_country <- toupper(substr(f, 1, 3))
  if (is.null(p) || isTRUE(p$unknown) || p$dataset != runnable[[f]] ||
      p$data_source != "auto" || p$country != exp_country ||
      p$csv_filepath != file.path("input", f)) bad <- c(bad, f)
}
check(sprintf("names without a source token: all %d pipeline tables parsed (country, dataset, source = auto)",
              length(runnable)), length(bad) == 0, paste(bad, collapse = ", "))

bad <- character(0)
for (f in no_dictionary) {
  p <- e$parse_input_filename(f)
  if (is.null(p) || !isTRUE(p$unknown)) bad <- c(bad, f)
}
check(sprintf("names without a source token: all %d other tables flagged as unknown (skipped, not failed)",
              length(no_dictionary)), length(bad) == 0, paste(bad, collapse = ", "))

old <- list(
  list("mwi_db_admissions_20260501.csv",                  "MWI", "database", "admissions"),
  list("zim_mb_maternal_outcomes_2026-05-01.csv",         "ZIM", "metabase", "maternal_outcomes"),
  list("mwi_db_dhis2_maternal_outcomes_202608041252.csv", "MWI", "database", "dhis2_maternal_outcomes"),
  list("mwi_mb_Maternal_Outcomes_2026-05-07.csv",         "MWI", "metabase", "maternal_outcomes"),
  list("zim_db_twenty_8_day_follow_up_20260501.csv",      "ZIM", "database", "twenty_8_day_follow_up"),
  list("ZIM_MB_PHC_Discharges_2026-05-01.csv",            "ZIM", "metabase", "phc_discharges")
)
bad <- character(0)
for (o in old) {
  p <- e$parse_input_filename(o[[1]])
  if (is.null(p) || isTRUE(p$unknown) || p$country != o[[2]] ||
      p$data_source != o[[3]] || p$dataset != o[[4]]) bad <- c(bad, o[[1]])
}
check("names with a db/mb token: parsed", length(bad) == 0,
      paste(bad, collapse = ", "))

p_dates <- vapply(c("zim_admissions_20261008.csv", "zim_admissions_202610081230.csv",
                    "zim_admissions_2026-10-08.csv"),
                  function(f) { p <- e$parse_input_filename(f)
                                !is.null(p) && p$dataset == "admissions" }, logical(1))
check("names without a source token: all three date stamp forms accepted", all(p_dates))

rejects <- c("notes.csv", "zim_admissions.csv", "ken_admissions_2026-10-08.csv",
             "zim_admissions_2026-10-08.xlsx", "zim_admissions_08-10-2026.csv")
p_rej <- vapply(rejects, function(f) is.null(e$parse_input_filename(f)), logical(1))
check("non-matching names rejected", all(p_rej),
      paste(rejects[!p_rej], collapse = ", "))

# =============================================================================
# 2. Data-source detection
# =============================================================================
cat("\n2. Data-source detection\n")
tdir <- file.path(tempdir(), "neotree_naming_detect")
unlink(tdir, recursive = TRUE); dir.create(tdir)
w <- function(name, df) { p <- file.path(tdir, name); readr::write_csv(df, p, na = ""); p }

db_df <- data.frame(uid = c("A1", "A2"), unique_key = c("k1", "k2"),
                    started_at = c("2026-03-02 00:33:10", "2026-03-03 10:01:00"),
                    `BW.value` = c("3500", "2800"), check.names = FALSE)
title_case <- function(df) { names(df)[1:3] <- c("UID", "Unique Key", "Started At"); df }
month_dt   <- function(df) { df$started_at <- c("March 2, 2026, 12:33 AM", "March 3, 2026, 10:01 AM"); df }
dmy_month  <- function(df) { df$started_at <- c("2 March 2026, 12:33 AM", NA); df }
thousands  <- function(df) { df$BW.value <- c("3,500", "2,800"); df }

d_db    <- e$.detect_data_source(w("db.csv", db_df))
d_mb    <- e$.detect_data_source(w("mb.csv", title_case(month_dt(db_df))))
d_mbdmy <- e$.detect_data_source(w("mb_dmy.csv", dmy_month(db_df)))
d_mix1  <- e$.detect_data_source(w("mix_header.csv", title_case(db_df)))
d_mix2  <- e$.detect_data_source(w("mix_values.csv", month_dt(db_df)))
d_mix3  <- e$.detect_data_source(w("mix_thousands.csv", title_case(thousands(db_df))))
d_none  <- e$.detect_data_source(file.path(tdir, "does_not_exist.csv"))
check("snake_case header + ISO datetimes -> database", d_db$source == "database", d_db$reason)
check("Title Case header + month-name datetimes -> metabase", d_mb$source == "metabase", d_mb$reason)
check("day-month-name datetimes ('2 March 2026') recognised",
      d_mbdmy$source %in% c("metabase", "mixed") && grepl("1 month-name", d_mbdmy$reason), d_mbdmy$reason)
check("Title Case header + ISO datetimes -> mixed (header and values in different styles)",
      d_mix1$source == "mixed", d_mix1$reason)
check("snake_case header + month-name datetimes -> mixed", d_mix2$source == "mixed", d_mix2$reason)
check("thousands separators counted", grepl("2 thousands-separated", d_mix3$reason), d_mix3$reason)
check("missing file -> unknown (the pipeline then stops on the missing file)",
      d_none$source == "unknown", d_none$reason)
check("detection reason never contains data values",
      !any(grepl("3500|3,500|A1|k1|12:33", c(d_db$reason, d_mb$reason, d_mix1$reason,
                                             d_mix2$reason, d_mix3$reason))))

# =============================================================================
# 3. Paired admissions/discharges file
# =============================================================================
cat("\n3. Paired-file resolution\n")
pdir <- file.path(tempdir(), "neotree_naming_pair")
unlink(pdir, recursive = TRUE); dir.create(pdir)
touch <- function(...) for (f in c(...)) file.create(file.path(pdir, f))
touch("zim_admissions_2026-10-08.csv", "zim_discharges_2026-10-08.csv",
      "mwi_admissions_2026-10-08.csv", "mwi_discharges_2026-10-09.csv",
      "mwi_phc_admissions_2026-10-08.csv", "mwi_phc_discharges_2026-10-08.csv",
      "zim_db_admissions_20261008.csv", "zim_db_discharges_202610081201.csv")
pr <- function(f, ds) basename(e$.resolve_paired_csv(file.path(pdir, f), ds)$path %||% "")
`%||%` <- function(a, b) if (is.null(a)) b else a

check("no source token, same date: zim admissions -> zim discharges",
      pr("zim_admissions_2026-10-08.csv", "admissions") == "zim_discharges_2026-10-08.csv")
check("no source token, same date: zim discharges -> zim admissions",
      pr("zim_discharges_2026-10-08.csv", "discharges") == "zim_admissions_2026-10-08.csv")
check("no source token, different date: mwi admissions -> mwi discharges (fallback search)",
      pr("mwi_admissions_2026-10-08.csv", "admissions") == "mwi_discharges_2026-10-09.csv")
check("no source token: phc admissions pairs with phc discharges, not discharges",
      pr("mwi_phc_admissions_2026-10-08.csv", "phc_admissions") == "mwi_phc_discharges_2026-10-08.csv")
check("names with a token: fallback search",
      pr("zim_db_admissions_20261008.csv", "admissions") == "zim_db_discharges_202610081201.csv")
check("dataset without a pair: none",
      is.null(e$.resolve_paired_csv(file.path(pdir, "zim_neolab_2026-10-08.csv"), "neolab")$dataset))

# =============================================================================
# 4. Full batch run on synthetic files
# =============================================================================
cat("\n4. run_all.r on synthetic files (takes about a minute)\n")

fresh_copy <- function(tag) {
  dest <- file.path(tempdir(), paste0("neotree_naming_test_", tag))
  unlink(dest, recursive = TRUE)
  dir.create(dest, recursive = TRUE)
  keep <- list.files(PIPELINE_ROOT, all.files = FALSE)
  keep <- keep[grepl("^(0|1)[0-9]|^dictionaries$|^neotree_scripts$|^run_.*\\.r$", keep)]
  for (k in keep) file.copy(file.path(PIPELINE_ROOT, k), dest, recursive = TRUE)
  dir.create(file.path(dest, "input"))
  dest
}

# Dictionary-driven synthetic table: system columns, then every non-confidential
# raw_value_column filled with a value-map code, a number in range, a datetime
# or a short phrase.  No identifiers of any kind.
make_synthetic <- function(dict_path, n = 40L, seed = 1L,
                           header = c("database", "metabase"),
                           datetimes = c("iso", "month"),
                           thousands = FALSE) {
  header    <- match.arg(header)
  datetimes <- match.arg(datetimes)
  set.seed(seed)
  v  <- readxl::read_excel(dict_path, sheet = "Variables")
  vm <- readxl::read_excel(dict_path, sheet = "ValueMaps")
  v  <- v[!is.na(v$raw_value_column) &
          (is.na(v$confidential) | v$confidential != TRUE), ]
  tt <- as.POSIXct("2025-01-01", tz = "UTC") + sample(0:3e7, n)
  ts <- if (datetimes == "month") {
    # Month-name form, e.g. "January 31, 2000, 1:45 PM"
    hr <- as.integer(format(tt, "%I"))
    sprintf("%s %d, %s, %d:%s %s", format(tt, "%B"), as.integer(format(tt, "%d")),
            format(tt, "%Y"), hr, format(tt, "%M"), format(tt, "%p"))
  } else format(tt, "%Y-%m-%d %H:%M:%S")
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
  if (thousands) {
    # Weights in grams written with a thousands separator.
    for (wc in intersect(c("birthweight.value", "admissionweight.value"), names(df))) {
      g <- sample(1000:4500, n, replace = TRUE)
      df[[wc]] <- formatC(g, format = "d", big.mark = ",")
    }
  }
  if (header == "metabase") {
    names(df)[1:6] <- c("UID", "Facility", "Unique Key", "Started At",
                        "Completed At", "Ingested At")
  }
  df
}

root <- fresh_copy("batch")
dict <- function(ds) file.path(root, "dictionaries", sprintf("dictionary_zim_%s.xlsx", ds))
adm <- make_synthetic(dict("admissions"), seed = 11L)
# A field whose name has the shape of a Malawi national ID.  It must not stop
# Module 16, whose summary table lists column names as values.
adm[["10DexD12.value"]] <- sample(c("Y", "N"), nrow(adm), replace = TRUE)
readr::write_csv(adm, file.path(root, "input", "zim_admissions_2026-10-08.csv"), na = "")
# Full Metabase style: Title Case header, month-name datetimes.
readr::write_csv(make_synthetic(dict("discharges"), seed = 12L,
                                header = "metabase", datetimes = "month"),
                 file.path(root, "input", "zim_discharges_2026-10-08.csv"), na = "")
# Mixed style: Title Case header, ISO datetimes, weights with thousands
# separators.  Named with a "db" token, which must make no difference to
# parsing.
mixed_df <- make_synthetic(dict("admissions"), seed = 13L,
                           header = "metabase", datetimes = "iso", thousands = TRUE)
expected_bw <- setNames(as.numeric(gsub(",", "", mixed_df[["birthweight.value"]])),
                        mixed_df[["Unique Key"]])
readr::write_csv(mixed_df, file.path(root, "input", "zim_db_admissions_20261009.csv"), na = "")
# A table the pipeline has no dictionary for: listed as skipped.
writeLines("a,b\n1,2", file.path(root, "input", "zim_diagnoses_2026-10-08.csv"))

f <- file.path(root, "_batch.r")
writeLines(c(sprintf('setwd("%s")', root), 'source("run_all.r")'), f)
out <- suppressWarnings(system2(RSCRIPT, shQuote(f), stdout = TRUE, stderr = TRUE))
status <- attr(out, "status"); if (is.null(status)) status <- 0L
writeLines(out, file.path(root, "_batch.log"))
out <- paste(out, collapse = "\n")

log_of <- function(stem) {
  p <- file.path(root, "output", stem, paste0(stem, ".log"))
  if (file.exists(p)) paste(readLines(p, warn = FALSE), collapse = "\n") else ""
}
cleaned <- function(stem) file.exists(file.path(root, "output", stem, paste0(stem, "_cleaned.csv")))

check("batch: 3/3 succeeded", status == 0 && grepl("3/3 succeeded", out, fixed = TRUE))
check("batch: diagnoses table skipped as an unknown dataset",
      grepl("[SKIP] zim_diagnoses_2026-10-08.csv", out, fixed = TRUE) &&
      grepl("unrecognised dataset type 'diagnoses'", out, fixed = TRUE))
check("batch: run plan shows source=auto for names without a source token",
      grepl("zim_admissions_2026-10-08.csv\\s+country=ZIM\\s+source=auto", out))
check("batch: summary reports the detected style",
      grepl("zim_admissions_2026-10-08.csv  (ZIM x database x admissions)", out, fixed = TRUE) &&
      grepl("zim_discharges_2026-10-08.csv  (ZIM x metabase x discharges)", out, fixed = TRUE) &&
      grepl("zim_db_admissions_20261009.csv  (ZIM x mixed x admissions)", out, fixed = TRUE))

la <- log_of("zim_admissions_2026-10-08")
ld <- log_of("zim_discharges_2026-10-08")
lx <- log_of("zim_db_admissions_20261009")
check("admissions (snake_case, ISO): logged as database",
      grepl("Data source format : database (detected:", la, fixed = TRUE))
check("discharges (Title Case, month names): logged as metabase",
      grepl("Data source format : metabase (detected:", ld, fixed = TRUE))
check("admissions: paired discharges file found under the new name",
      grepl("Paired file : input/zim_discharges_2026-10-08.csv", la, fixed = TRUE))
check("discharges: paired admissions file found under the new name",
      grepl("Paired file : input/zim_admissions_2026-10-08.csv", ld, fixed = TRUE))
check("mixed file named with a db token: logged as mixed, token noted as irrelevant",
      grepl("Data source format : mixed (detected:", lx, fixed = TRUE) &&
      grepl("DATA_SOURCE was set to 'database'; the file itself looks 'mixed'", lx, fixed = TRUE))
check("cleaned outputs written for all three files",
      cleaned("zim_admissions_2026-10-08") && cleaned("zim_discharges_2026-10-08") &&
      cleaned("zim_db_admissions_20261009"))

summ <- function(stem) file.path(root, "output", stem, paste0(stem, "_cleaned_na_reasons_summary.csv"))
check("Module 16 NA summary written for all three files",
      all(file.exists(summ(c("zim_admissions_2026-10-08", "zim_discharges_2026-10-08",
                             "zim_db_admissions_20261009")))))
if (file.exists(summ("zim_admissions_2026-10-08"))) {
  sv <- readr::read_csv(summ("zim_admissions_2026-10-08"), show_col_types = FALSE)
  hit <- any(grepl("^10dexd12", sv$variable))
  check("ID-shaped field name (10dexd12) listed in the NA summary without stopping the guard",
        hit, if (hit) "" else "column dropped before Module 16; guard exemption not exercised")
}

# Metabase datetimes in the discharges file must have been parsed, not lost.
if (cleaned("zim_discharges_2026-10-08")) {
  cd <- readr::read_csv(file.path(root, "output", "zim_discharges_2026-10-08",
                                  "zim_discharges_2026-10-08_cleaned.csv"),
                        col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  sa <- grep("^started_?at$", names(cd), value = TRUE)[1]
  ok <- !is.na(sa) && mean(!is.na(cd[[sa]])) > 0.9 && all(grepl("^\\d{4}-", na.omit(cd[[sa]])))
  check("discharges: Metabase datetimes parsed to ISO in the cleaned output", ok,
        if (is.na(sa)) "started_at column not found" else
          sprintf("%s: %.0f%% non-missing", sa, 100 * mean(!is.na(cd[[sa]]))))
}

# Thousands-separated weights in the mixed file must parse to the exact gram
# value.  Reading "3,500" as 3 and rescaling from kg to g would give a
# plausible 3000 g, so the values are compared exactly, row by row.
if (cleaned("zim_db_admissions_20261009")) {
  cx <- readr::read_csv(file.path(root, "output", "zim_db_admissions_20261009",
                                  "zim_db_admissions_20261009_cleaned.csv"),
                        col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  bw  <- suppressWarnings(as.numeric(cx[["birthweight"]]))
  exp <- unname(expected_bw[cx[["uniquekey"]]])
  n_match <- sum(!is.na(bw) & !is.na(exp) & bw == exp)
  ok <- "birthweight" %in% names(cx) && n_match == nrow(cx)
  check("mixed file: '3,500'-style weights parsed to the exact gram value", ok,
        sprintf("%d of %d rows exact", n_match, nrow(cx)))
  sa <- grep("^started_?at$", names(cx), value = TRUE)[1]
  check("mixed file: ISO datetimes under Title Case header parsed",
        !is.na(sa) && mean(!is.na(cx[[sa]])) > 0.9)
}

# =============================================================================
# 5. Shape-routed value parsers (synthetic values only)
# =============================================================================
cat("\n5. Value parsing by shape\n")

p <- new.env()
p$log_info <- function(...) invisible(NULL)
load_defs(file.path(PIPELINE_ROOT, "00_setup", "00_setup.r"),
          c("NEOTREE_TRUE_TOKENS", "NEOTREE_FALSE_TOKENS",
            "parse_datetime_by_shape", "parse_numeric_by_shape"), p)
load_defs(file.path(PIPELINE_ROOT, "04_dictionary_value_cleaning",
                    "04_dictionary_value_cleaning.r"),
          "normalise_multiselect_encoding", p)
environment(p$normalise_multiselect_encoding) <- p
fmt <- function(x) format(x, "%Y-%m-%d %H:%M:%S")
dt  <- function(x) fmt(p$parse_datetime_by_shape(x))

# -- Datetimes ----------------------------------------------------------------
# Day-first dates sit in a column that is mostly ISO.
iso_bulk <- rep("2024-05-06 10:11:12", 200)
day_first <- c("25/12/2023", "12/03/2024", "12/03/24", "25-12-2023", "25.12.2023",
               "05/06/2024 14:30", "05/06/2024 02:30 pm", "1/2/2025")
exp_df <- c("2023-12-25 00:00:00", "2024-03-12 00:00:00", "2024-03-12 00:00:00",
            "2023-12-25 00:00:00", "2023-12-25 00:00:00", "2024-06-05 14:30:00",
            "2024-06-05 14:30:00", "2025-02-01 00:00:00")
got <- dt(c(iso_bulk, day_first))
check("datetime: ISO values unchanged when mixed with day-first dates",
      all(got[1:200] == "2024-05-06 10:11:12"))
check("datetime: day-first dates read as day/month/year (slash, dash, dot, with time)",
      identical(got[201:208], exp_df),
      sprintf("%d of %d exact", sum(got[201:208] == exp_df, na.rm = TRUE), length(exp_df)))
check("datetime: two-digit year read as 20yy",
      identical(dt("12/03/24"), "2024-03-12 00:00:00"))
r <- p$parse_datetime_by_shape(c("12/25/2023", "31/02/2024", "1/2/123"))
check("datetime: a value valid only as month/day/year is NA and counted, not reinterpreted",
      all(is.na(r)) && attr(r, "counts")[["month_first_rejected"]] == 1L)
check("datetime: ISO with Z, UTC offset or fractional seconds keeps the time as written",
      identical(dt(c("2023-10-19T22:00:00Z", "2023-10-19T22:00:00+02:00",
                     "2023-10-19T22:00:00.000+0200", "2023-10-19 22:00:00.123",
                     "2023-10-19 22:00", "2023-10-19")),
                c(rep("2023-10-19 22:00:00", 5), "2023-10-19 00:00:00")))
r <- p$parse_datetime_by_shape(c("2023-10-19T22:00:00+02:00", "2023-10-19T22:00:00Z"))
check("datetime: dropped offsets are counted", attr(r, "counts")[["offset_dropped"]] == 2L)
check("datetime: month-name forms, 12-hour and 24-hour, full and abbreviated",
      identical(dt(c("March 2, 2026, 12:33 AM", "2 March 2026, 12:33 PM",
                     "October 19, 2023, 2:05 PM", "March 2, 2026", "2 March 2026",
                     "19 Oct 2023", "19-Oct-2023", "2 March 2026 14:05:09")),
                c("2026-03-02 00:33:00", "2026-03-02 12:33:00", "2023-10-19 14:05:00",
                  "2026-03-02 00:00:00", "2026-03-02 00:00:00", "2023-10-19 00:00:00",
                  "2023-10-19 00:00:00", "2026-03-02 14:05:09")))
r <- p$parse_datetime_by_shape(c("Reviewed 3 May 2024, weight 2100", "20231019", "19102023",
                                 "12", "see notes", "2023-13-01", "2023-10-19 25:00", NA, ""))
check("datetime: free text, bare digits and impossible dates are NA",
      all(is.na(r)) && attr(r, "counts")[["unparsed"]] == 7L,
      sprintf("unparsed = %d", attr(r, "counts")[["unparsed"]]))

# -- Numbers ------------------------------------------------------------------
num <- function(x) p$parse_numeric_by_shape(x)
r <- num(c("3500", "3.5", "-2", " 42 ", ".5"))
check("number: plain values", identical(r$value, c(3500, 3.5, -2, 42, 0.5)))
r <- num(c("3,500", "1,234,567.8", "-12,345"))
check("number: thousands separators removed",
      identical(r$value, c(3500, 1234567.8, -12345)) && r$counts[["thousands"]] == 3L)
r <- num(c("3,5", "36,75", "0,5"))
check("number: decimal comma read as a decimal point, never as 3 or 35",
      identical(r$value, c(3.5, 36.75, 0.5)) && r$counts[["decimal_comma"]] == 3L)
r <- num(c("ANC4", "4 ANC visits", "36.5 C"))
check("number: text holding exactly one number recovers that number",
      identical(r$value, c(4, 4, 36.5)) && r$counts[["fallback"]] == 3L)
r <- num(c("2023-10-19 22:00:00", "10-12", "1e5", "0x1A", "1,2,3", "12/03/2024"))
check("number: a date, a range, exponent or hexadecimal notation is NA, not a year or a part",
      all(is.na(r$value)) && r$counts[["multi_number_rejected"]] == 6L)
r <- num(c("Unknown", NA, ""))
check("number: text without digits, NA and empty are NA", all(is.na(r$value)))

# -- Booleans -----------------------------------------------------------------
check("boolean: one shared token list, including t and f",
      all(c("t", "true", "yes", "y", "1") %in% p$NEOTREE_TRUE_TOKENS) &&
      all(c("f", "false", "no", "n", "0") %in% p$NEOTREE_FALSE_TOKENS))
src09 <- readLines(file.path(PIPELINE_ROOT, "09_data_type_assignment", "09_data_type_assignment.r"))
src12 <- readLines(file.path(PIPELINE_ROOT, "12_boolean_validation", "12_boolean_validation.r"))
check("boolean: Modules 09 and 12 both use the shared list",
      any(grepl("NEOTREE_TRUE_TOKENS", src09)) && any(grepl("NEOTREE_TRUE_TOKENS", src12)))

# -- Unquoted multi-select lists (Module 04) -------------------------------------
vm <- list(resus = list(allowed_codes = c("Stim", "Suc", "BVM"),
                        canonical_codes = c("Stim", "Suc", "BVM"),
                        label_to_code = list(), code_to_canonical = list()))
d4 <- data.frame(resus.value = c("[Stim, Suc]", "[stim,BVM]", "[Stim, not a code]",
                                 "[\"Stim\",\"Suc\"]", "{Stim,Suc}", "Stim", NA),
                 note.value  = c("[free text, in brackets]", rep(NA, 6)),
                 check.names = FALSE, stringsAsFactors = FALSE)
o4 <- p$normalise_multiselect_encoding(d4, vm)
check("list: unquoted [A, B] converted to {A,B} when every item is a dictionary code",
      identical(o4$resus.value[1:2], c("{Stim,Suc}", "{stim,BVM}")))
check("list: left unchanged when an item is not a dictionary code",
      identical(o4$resus.value[3], "[Stim, not a code]"))
check("list: quoted arrays, brace lists and single codes",
      identical(o4$resus.value[4:6], c("{Stim,Suc}", "{Stim,Suc}", "Stim")) &&
      is.na(o4$resus.value[7]))
check("list: a bracketed value in a column without a value map is not touched",
      identical(o4$note.value[1], "[free text, in brackets]"))

# -- hepbdate_date: dates split out of the mixed Y/N-and-date column (Module 14) ---
m14 <- new.env()
m14$log_info <- function(...) invisible(NULL); m14$log_warn <- function(...) invisible(NULL)
m14$parse_datetime_by_shape <- p$parse_datetime_by_shape
load_defs(file.path(PIPELINE_ROOT, "14_datetime_validation", "14_datetime_validation.r"),
          "validate_datetime", m14)
environment(m14$validate_datetime) <- m14
d14 <- data.frame(facility = "F", uid = sprintf("U%02d", 1:6), uniquekey = sprintf("K%02d", 1:6),
                  startedat = "2026-01-05 10:00:00",
                  hepbdate.value = factor(c("Y", "N", "2026-01-03 00:00:00", "2026-01-04T08:30:00",
                                            "03/01/2026", NA)),
                  check.names = FALSE, stringsAsFactors = FALSE)
cfg14 <- list(dt = c("facility", "uid", "uniquekey", "startedat"), country = "MWI",
              dataset = "admissions", data_source = "mixed")
o14 <- tryCatch(m14$validate_datetime(d14, cfg14), error = function(e) e)
if (inherits(o14, "error")) {
  check("hepbdate_date: Module 14 runs on a synthetic frame", FALSE, conditionMessage(o14))
} else {
  o14 <- o14[order(o14$uid), ]
  check("hepbdate_date: dates taken from the mixed column; Y/N answers and NA stay empty",
        "hepbdate_date" %in% names(o14) &&
        identical(format(o14$hepbdate_date, "%Y-%m-%d %H:%M"),
                  c(NA, NA, "2026-01-03 00:00", "2026-01-04 08:30", "2026-01-03 00:00", NA)))
  d14b <- d14[, setdiff(names(d14), "hepbdate.value")]
  check("hepbdate_date: not created when the dataset has no hepbdate column",
        !"hepbdate_date" %in% names(m14$validate_datetime(d14b, cfg14)))
  cfg14c <- cfg14; cfg14c$dt <- c(cfg14$dt, "hepbdate.value")
  check("hepbdate_date: not created when hepbdate is itself typed datetime",
        !"hepbdate_date" %in% names(m14$validate_datetime(d14, cfg14c)))
}

# -- No general datetime parser in the modules ----------------------------------
mods <- c("06_forward_fill_numeric_datetime/06_forward_fill_numeric_datetime.r",
          "09_data_type_assignment/09_data_type_assignment.r",
          "14_datetime_validation/14_datetime_validation.r",
          "14a_resolve_neolab_datebct/14a_resolve_neolab_datebct.r")
uses_general <- vapply(mods, function(m) {
  src <- readLines(file.path(PIPELINE_ROOT, m))
  any(grepl("parse_date_time\\(", src[!grepl("^\\s*#", src)]))
}, logical(1))
check("Modules 06, 09, 14 and 14a parse datetimes only through parse_datetime_by_shape()",
      !any(uses_general), paste(basename(mods[uses_general]), collapse = ", "))

# =============================================================================
# Summary
# =============================================================================
n_fail <- sum(!results$ok)
cat(sprintf("\n=== %d test(s): %d passed, %d failed ===\n",
            nrow(results), sum(results$ok), n_fail))
if (n_fail > 0) {
  cat("Failed:\n"); cat(paste0("  - ", results$test[!results$ok], "\n"), sep = "")
  cat(sprintf("Batch log and outputs are in %s\n", root))
}
quit(status = if (n_fail > 0) 1L else 0L)
