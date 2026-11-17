# =============================================================================
# NEOTREE CLEANING PIPELINE -- label-to-value recovery tests
# =============================================================================
# PURPOSE:
#   Tests that an answer stored only in the .label column is recovered into the
#   field when a label-to-value rule is configured, and only then.
#
# METHOD:
#   1. The antenatal care parser (Module 05) on label and value combinations.
#   2. A pipeline run on a small synthetic Malawi admissions file whose
#      antenatalcare.value is empty and whose antenatalcare.label is filled:
#      the cleaned antenatalcare, antenatalcare_source and
#      antenatalcare_category are checked row by row.
#   3. The same labels in a synthetic Zimbabwe admissions file, where no rule
#      is configured: antenatalcare stays empty and no source column is added.
#   The runs use a copy of the pipeline under tempdir().
#
# INPUTS:
#   None.  All values are generated.
#
# OUTPUTS:
#   PASS/FAIL lines on the console.  Exit status 0 = all tests passed;
#   1 = at least one failure.
#
# USAGE (from the cleaning_pipeline_R folder):
#   Rscript tests/test_label_value_recovery.r
# =============================================================================

suppressPackageStartupMessages(library(readr))

.args     <- commandArgs(trailingOnly = FALSE)
.file_arg <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
PIPELINE_ROOT <- if (length(.file_arg))
  normalizePath(file.path(dirname(.file_arg[1]), "..")) else normalizePath(".")
stopifnot(file.exists(file.path(PIPELINE_ROOT, "run_all.r")))
RSCRIPT <- file.path(R.home("bin"), "Rscript")

results <- data.frame(test = character(0), ok = logical(0), detail = character(0),
                      stringsAsFactors = FALSE)
check <- function(test, ok, detail = "") {
  ok <- isTRUE(ok)
  results[nrow(results) + 1, ] <<- list(test, ok, detail)
  cat(sprintf("  [%s] %s%s\n", if (ok) "PASS" else "FAIL", test,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("\n=== Neotree label-to-value recovery tests ===\n")
cat(sprintf("Pipeline under test: %s\n\n", PIPELINE_ROOT))

# -- Test cases: value, label, expected count, expected source, expected category
cases <- data.frame(
  value = c("", "", "", "", "", "", "", "", "", "2.0", "5", "0", "", "0.5", "-1", "0.5", "", ""),
  label = c("3 ANC visits", "1 ANC visit ", "None", "4 ANC visits",
            "Not sure", "ANC visits", "More than 4 ANC visits",
            "More than 8 ANC visits", "Number of antenatal care visits?",
            "Number of antenatal care visits?", "3 ANC visits", "", "", "",
            "Not sure", "2 ANC visits", "0.5", "-1"),
  count = c(3, 1, 0, 4, NA, NA, NA, NA, NA, 2, 5, 0, NA, NA, NA, 2, NA, NA),
  source = c("raw_exact_label", "raw_exact_label", "raw_exact_label",
             "raw_exact_label", "unresolved", "unresolved", "raw_range_label",
             "raw_range_label", "unresolved", "raw_numeric_value",
             "raw_numeric_value", "raw_numeric_value", "unresolved",
             "unresolved", "unresolved", "raw_exact_label", "unresolved",
             "unresolved"),
  category = c("1_3", "1_3", "none", "ge4", NA, NA, "ge4", "ge4", NA,
               "1_3", "ge4", "none", NA, NA, NA, "1_3", NA, NA),
  stringsAsFactors = FALSE
)

# =============================================================================
# 1. Parser
# =============================================================================
cat("1. Antenatal care parser\n")

load_defs <- function(path, names, envir) {
  for (ex in parse(path, keep.source = FALSE)) {
    if (is.call(ex) && as.character(ex[[1]]) %in% c("<-", "=") &&
        is.name(ex[[2]]) && as.character(ex[[2]]) %in% names) eval(ex, envir = envir)
  }
  missing <- setdiff(names, ls(envir, all.names = TRUE))
  if (length(missing)) stop("Not found in ", path, ": ", paste(missing, collapse = ", "))
}
e <- new.env()
loaded <- tryCatch({
  load_defs(file.path(PIPELINE_ROOT, "05_forward_fill_placeholders",
                      "05_forward_fill_placeholders.r"),
            c("anc_count", "parse_anc_visit_count"), e)
  TRUE
}, error = function(err) FALSE)
check("parser: parse_anc_visit_count is defined in Module 05", loaded)
if (loaded) {
  p <- e$parse_anc_visit_count(cases$value, cases$label)
  check("parser: counts from labels, None as 0, valid value kept",
        identical(unname(p$count), cases$count))
  check("parser: source column values",
        identical(unname(p$source), cases$source))
  check("parser: a value that disagrees with the label count is flagged and kept",
        identical(which(p$conflict), 11L) && p$count[11] == 5)
  check("parser: unknown, no-number and question-text labels give no count",
        all(is.na(p$count[c(5, 6, 9, 13)])))
  check("parser: a fractional or negative value without a label count is flagged invalid",
        identical(which(p$invalid & !p$from_label), c(14L, 15L)))
}

# =============================================================================
# 2 and 3. Pipeline runs on synthetic files
# =============================================================================
fresh_copy <- function(tag) {
  dest <- file.path(tempdir(), paste0("neotree_labelvalue_", tag))
  unlink(dest, recursive = TRUE)
  dir.create(dest, recursive = TRUE)
  keep <- list.files(PIPELINE_ROOT, all.files = FALSE)
  keep <- keep[grepl("^(0|1)[0-9]|^dictionaries$|^neotree_scripts$|^run_.*\\.r$", keep)]
  for (k in keep) file.copy(file.path(PIPELINE_ROOT, k), dest, recursive = TRUE)
  dir.create(file.path(dest, "input"))
  dest
}

make_raw <- function(n_extra = 20L) {
  n  <- nrow(cases) + n_extra
  tt <- format(as.POSIXct("2024-03-01 08:00:00", tz = "UTC") + (seq_len(n) * 3600),
               "%Y-%m-%d %H:%M:%S")
  df <- data.frame(
    uid = sprintf("T%03d-%04d", seq_len(n), seq_len(n)),
    facility = rep("FAC1", n),
    unique_key = sprintf("k%06d", seq_len(n)),
    started_at = tt, completed_at = tt, ingested_at = tt,
    datetimeadmission.value = tt,
    antenatalcare.value = c(cases$value, as.character(rep(3, n_extra))),
    antenatalcare.label = c(cases$label, rep("Number of antenatal care visits?", n_extra)),
    stringsAsFactors = FALSE
  )
  df
}

run_one <- function(tag, country) {
  root <- fresh_copy(tag)
  readr::write_csv(make_raw(), file.path(root, "input",
                   sprintf("%s_admissions_2026-10-08.csv", country)), na = "")
  f <- file.path(root, "_batch.r")
  writeLines(c(sprintf('setwd("%s")', root), 'source("run_all.r")'), f)
  out <- suppressWarnings(system2(RSCRIPT, shQuote(f), stdout = TRUE, stderr = TRUE))
  writeLines(out, file.path(root, "_batch.log"))
  stem <- sprintf("%s_admissions_2026-10-08", country)
  cf <- file.path(root, "output", stem, paste0(stem, "_cleaned.csv"))
  list(root = root, ok = file.exists(cf),
       cleaned = if (file.exists(cf)) readr::read_csv(cf, col_types = readr::cols(.default = "c"),
                                                      show_col_types = FALSE) else NULL)
}

cat("\n2. Malawi admissions: value empty, label filled (takes about a minute)\n")
mw <- run_one("mwi", "mwi")
check("MWI run: cleaned file written", mw$ok, mw$root)
if (mw$ok) {
  cl <- mw$cleaned[match(sprintf("k%06d", seq_len(nrow(cases))), mw$cleaned$uniquekey), ]
  check("MWI: antenatalcare recovered from labels, row by row",
        identical(suppressWarnings(as.numeric(cl$antenatalcare)), cases$count),
        paste(cl$antenatalcare, collapse = ","))
  check("MWI: fractional and negative raw values and labels are not left in antenatalcare",
        all(is.na(cl$antenatalcare[c(14, 15, 17, 18)])) && cl$antenatalcare[16] == "2",
        paste(cl$antenatalcare[14:18], collapse = ","))
  check("MWI: antenatalcare_source as expected",
        identical(cl$antenatalcare_source, cases$source))
  check("MWI: antenatalcare_category as expected (range label gives ge4 without a count)",
        identical(cl$antenatalcare_category, cases$category))
}

cat("\n3. Zimbabwe admissions: no rule configured (takes about a minute)\n")
zw <- run_one("zim", "zim")
check("ZIM run: cleaned file written", zw$ok, zw$root)
if (zw$ok) {
  cz <- zw$cleaned[match(sprintf("k%06d", c(3L, 5L, 6L)), zw$cleaned$uniquekey), ]
  check("ZIM: labels None, Not sure and ANC visits stay empty (no rule)",
        all(is.na(cz$antenatalcare)))
  check("ZIM: no antenatalcare_source or antenatalcare_category column",
        !any(c("antenatalcare_source", "antenatalcare_category") %in% names(zw$cleaned)))
}

# =============================================================================
# Summary
# =============================================================================
n_fail <- sum(!results$ok)
cat(sprintf("\n=== %d test(s): %d passed, %d failed ===\n",
            nrow(results), sum(results$ok), n_fail))
if (n_fail > 0) {
  cat("Failed:\n"); cat(paste0("  - ", results$test[!results$ok], "\n"), sep = "")
  cat(sprintf("Run logs and outputs are in %s\n", tempdir()))
}
quit(status = if (n_fail > 0) 1L else 0L)
