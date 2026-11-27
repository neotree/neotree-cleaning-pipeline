################################################################################
# Neotree cleaning pipeline -- tests: HIV clinical fields are not confidential
# FILE:    tests/test_hiv_fields_kept.r
# PURPOSE: Checks, in the built data dictionaries, that the HIV and syphilis
#          clinical fields and ZIM ethnicity2 are not flagged confidential (so
#          Module 00a keeps them), that no field whose name looks HIV- or
#          syphilis-related is still flagged in any dictionary (a renamed key
#          would be), and that names, contact details and dates of birth still
#          are.
#
# USAGE (from the cleaning_pipeline_R folder):
#   Rscript tests/test_hiv_fields_kept.r
#   Exit status 0 = all tests passed; 1 = at least one failure.
################################################################################

suppressPackageStartupMessages(library(readxl))

.args     <- commandArgs(trailingOnly = FALSE)
.file_arg <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
ROOT <- if (length(.file_arg)) normalizePath(file.path(dirname(.file_arg[1]), "..")) else getwd()

n_pass <- 0L; n_fail <- 0L
check <- function(label, ok) {
  ok <- isTRUE(ok)
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (ok) n_pass <<- n_pass + 1L else n_fail <<- n_fail + 1L
}

HIV_KEYS <- list(
  mwi = c("hivtestresult", "hivtestresultdc", "datehivtest", "haart", "lengthhaart", "mathivstat"),
  zim = c("hivtestresult", "datehivtest", "haart", "lengthhaart", "mahaart", "hivmeds", "vlnumber",
          "hivpcrinfr", "isthebabyhivexposed", "mathivpr", "dnapcrresult", "matpart", "matrprr",
          "matrprt", "prophylaxis")
)
IDENTIFIERS <- c("motherfirstname", "mothersurname", "babyfirst", "babylast", "babyfirstname",
                 "babysurname", "dobtob", "mothcell", "kincell", "kinname", "motheraddressvillage")
DATASETS <- c("admissions", "discharges", "phc_admissions", "phc_discharges")

is_conf <- function(x) !is.na(x) & toupper(as.character(x)) == "TRUE"

for (cc in names(HIV_KEYS)) for (ds in DATASETS) {
  f <- file.path(ROOT, "dictionaries", sprintf("dictionary_%s_%s.xlsx", cc, ds))
  if (!file.exists(f)) next
  v <- read_excel(f, sheet = "Variables", col_types = "text")
  hiv <- v[v$question_key %in% HIV_KEYS[[cc]], ]
  bad <- hiv$question_key[is_conf(hiv$confidential)]
  check(sprintf("%s %s: HIV fields present (%d) are not confidential%s", cc, ds, nrow(hiv),
                if (length(bad)) paste0(" -- still flagged: ", paste(bad, collapse = ", ")) else ""),
        nrow(hiv) > 0 && length(bad) == 0)
  ids <- v[v$question_key %in% IDENTIFIERS, ]
  kept <- ids$question_key[!is_conf(ids$confidential)]
  check(sprintf("%s %s: identifiers present (%d) stay confidential%s", cc, ds, nrow(ids),
                if (length(kept)) paste0(" -- not flagged: ", paste(kept, collapse = ", ")) else ""),
        nrow(ids) > 0 && length(kept) == 0)
}

f <- file.path(ROOT, "dictionaries", "dictionary_zim_admissions.xlsx")
v <- read_excel(f, sheet = "Variables", col_types = "text")
check("zim admissions: ethnicity2 is not confidential",
      any(v$question_key == "ethnicity2") && !is_conf(v$confidential[v$question_key == "ethnicity2"]))

# Any HIV- or syphilis-like key still flagged in any dictionary, for example a
# key renamed in a later data-key export, fails here.
HIV_LIKE <- "hiv|haart|pcr|rpr|vdrl|syph|vlnumber|viral|prophylaxis|matpart|arv"
still <- character(0)
for (f in Sys.glob(file.path(ROOT, "dictionaries", "dictionary_*.xlsx"))) {
  if (grepl("_enriched\\.xlsx$", f)) next
  v <- read_excel(f, sheet = "Variables", col_types = "text")
  hit <- v$question_key[grepl(HIV_LIKE, v$question_key, ignore.case = TRUE) & is_conf(v$confidential)]
  if (length(hit)) still <- c(still, paste0(gsub("^dictionary_|\\.xlsx$", "", basename(f)), ": ", hit))
}
check(sprintf("no HIV- or syphilis-like field is flagged confidential in any dictionary%s",
              if (length(still)) paste0(" -- flagged: ", paste(still, collapse = "; ")) else ""),
      length(still) == 0)

cat(sprintf("\n=== %d test(s): %d passed, %d failed ===\n", n_pass + n_fail, n_pass, n_fail))
quit(status = if (n_fail > 0) 1 else 0)
