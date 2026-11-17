# =============================================================================
# NEOTREE CLEANING PIPELINE -- Module 10 episode mode tests
# =============================================================================
# PURPOSE:
#   Tests ep_dedup() (10_remove_duplicate_rows/episode_ids.r) on made-up
#   admissions and discharges with a known number of babies and stays.
#
# METHOD:
#   1. Fifteen scenarios, each checked for the baby_id and stay_no given to
#      one record.
#   2. Collapsing: rows of one event are collapsed; a readmission flag keeps
#      two rows apart even within one hour.
#   3. Flags: unresolved, no_admission, ambiguous_link, outcome_conflict, and
#      one primary discharge form per stay.
#   4. Known totals: babies, stays and kept rows for the whole made-up set.
#   5. The original uid is unchanged and no kept rows share
#      uid + facility + uniquekey.
#   6. The admissions key file is refused when its input file, the code
#      that runs before the keys are built, the dictionary build code, a
#      dictionary workbook or the dictionary the admissions run used has
#      changed.
#   7. Discharge matching ranks identity agreement before dates.
#   8. Main and PHC admissions and discharges, ZIM maternal_outcomes and MWI
#      combined_maternity_outcomes are covered, other datasets not.
#   9. Births: repeats collapsed; twins, live and stillbirths, and records on
#      other days kept as babies of their own; flags; no stay_no.
#
# INPUTS:
#   None.  All rows are generated; identifiers are invented (TEST-nn).
#
# OUTPUTS:
#   PASS/FAIL lines on the console.  Exit status 0 = all tests passed;
#   1 = at least one failure.
#
# USAGE (from the cleaning_pipeline_R folder):
#   Rscript tests/test_dedup_episode.r
# =============================================================================

suppressPackageStartupMessages(library(dplyr))

.args     <- commandArgs(trailingOnly = FALSE)
.file_arg <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
PIPELINE_ROOT <- if (length(.file_arg))
  normalizePath(file.path(dirname(.file_arg[1]), "..")) else getwd()
source(file.path(PIPELINE_ROOT, "10_remove_duplicate_rows", "episode_ids.r"))

n_pass <- 0L; n_fail <- 0L
check <- function(label, ok) {
  ok <- isTRUE(ok)
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (ok) n_pass <<- n_pass + 1L else n_fail <<- n_fail + 1L
}

t0  <- as.POSIXct("2025-03-03 10:15:00", tz = "UTC")
day <- 86400
row <- function(uid, fac, key, t_adm = NA, t_dis = NA, sex = NA, bw = NA, ga = NA, readm = NA,
                apgar5 = NA, mode = NA, outcome = NA, extra = NA) {
  data.frame(uid = uid, facility = fac, uniquekey = key,
             datetimeadmission.value = as.POSIXct(t_adm, origin = "1970-01-01", tz = "UTC"),
             startedat = as.POSIXct(NA, tz = "UTC"),
             datetimedischarge.value = as.POSIXct(t_dis, origin = "1970-01-01", tz = "UTC"),
             gender.value = sex, birthweight.value = bw, gestation.value = ga,
             readmission.value = if (is.na(readm)) NA_character_ else if (readm) "Y" else "N",
             apgar5.value = apgar5, modedelivery.value = mode,
             neotreeoutcome.value = outcome, other.value = extra,
             stringsAsFactors = FALSE)
}
n <- as.numeric

adm <- rbind(
  row("TEST-01", "H1", "a1", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-02", "H1", "a2", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-02", "H1", "a3", n(t0) + 600, sex = "M", bw = 2900, ga = 39, extra = "x"),
  row("TEST-03", "H1", "a4", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-03", "H1", "a5", n(t0) + 100 * day, sex = "F", bw = 1800, ga = 33),
  row("TEST-04", "H1", "a6", n(t0), sex = "M", bw = 2900, ga = 39, readm = FALSE),
  row("TEST-04", "H1", "a7", n(t0) + 20 * day, sex = "M", bw = 2900, ga = 39, readm = TRUE),
  row("TEST-05", "H1", "a8", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-05", "H1", "a9", n(t0) + 10 * day, sex = "M", bw = 2950, ga = 39),
  row("TEST-06", "H1", "a10", n(t0), sex = "M", bw = 2900, ga = 39, apgar5 = 9, mode = "SVD"),
  row("TEST-06", "H1", "a11", n(t0) + 10 * day, sex = "M", bw = 2900, ga = 39, apgar5 = 9, mode = "SVD"),
  row("TEST-07", "H1", "a12", n(t0), sex = "M", bw = 2900, ga = 39, apgar5 = 9, mode = "SVD"),
  row("TEST-07", "H1", "a13", n(t0) + 10 * day, sex = "M", bw = 2900, ga = 39, apgar5 = 5, mode = "CS"),
  row("TEST-08", "H1", "a14", n(t0), sex = "F", bw = 2100, ga = 35),
  row("TEST-08", "H2", "a15", n(t0) + 2 * day, sex = "F", bw = 2100, ga = 35),
  row("TEST-10", "H1", "a16", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-11", "H1", "a17", n(t0), sex = "M", bw = 3000, ga = 39),
  row("TEST-11", "H1", "a18", n(t0) + 60 * day, sex = "M", bw = 3020, ga = 39),
  row("TEST-12", "H1", "a19", n(t0), sex = "M", bw = 3000, ga = 39),
  row("TEST-13", "H1", "a20", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-13", "H1", "a21", n(t0) + 100 * day, sex = "F", bw = 1800, ga = 33),
  row("TEST-14", "H1", "a22", n(t0), sex = "M", bw = 2900, ga = 39, readm = FALSE),
  row("TEST-14", "H1", "a23", n(t0) + 1800, sex = "M", bw = 2900, ga = 39, readm = TRUE),
  row("TEST-15", "H1", "a24", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-15", "H1", "a25", n(t0) + 1800),
  row("TEST-15", "H1", "a26", n(t0) + 3000, sex = "F", bw = 1800, ga = 33),
  row("TEST-16", "H1", "a27", n(t0), sex = "M", bw = 2900, ga = 39),
  row("TEST-16", "H1", "a28", n(t0), sex = "F", bw = 1800, ga = 33),
  row(NA, "H1", "a29", n(t0), sex = "M", bw = 2900, ga = 39)
)
dis <- rbind(
  row("TEST-01", "H1", "d1", n(t0), n(t0) + 5 * day, sex = "M", bw = 2900, ga = 39, outcome = "DC"),
  row("TEST-03", "H1", "d2", n(t0), n(t0) + 6 * day, sex = "M", bw = 2900, ga = 39, outcome = "DC"),
  row("TEST-03", "H1", "d3", NA, n(t0) + 110 * day, sex = "F", bw = 1800, ga = 33, outcome = "DC"),
  row("TEST-09", "H1", "d4", NA, n(t0) + 3 * day, sex = "F", bw = 2500, ga = 37, outcome = "DC"),
  row("TEST-10", "H1", "d5", n(t0), n(t0) + 4 * day, sex = "M", bw = 2900, ga = 39, outcome = "NND"),
  row("TEST-10", "H1", "d6", n(t0), n(t0) + 6 * day, sex = "M", bw = 2900, ga = 39, outcome = "DC"),
  row("TEST-11", "H1", "d7", NA, n(t0) + 70 * day, sex = "M", bw = 3000, ga = 39, outcome = "DC"),
  row("TEST-12", "H1", "d8", NA, n(t0) + 4 * day, sex = "F", bw = 1800, ga = 33, outcome = "DC"),
  row("TEST-13", "H1", "d9", n(t0) + 100 * day - 2 * 3600, n(t0) + 104 * day, sex = "F", bw = 1800, ga = 33,
      outcome = "DC"),
  row("TEST-13", "H1", "d10", n(t0) + 100 * day - 2 * 3600, n(t0) + 104 * day + 600, sex = "F", bw = 1800,
      ga = 33, outcome = "DC")
)

A <- ep_dedup(adm, "admissions")
D <- ep_dedup(dis, "discharges", A$keys)
got <- bind_rows(A$df %>% select(uniquekey, baby_id, stay_no, dedup_flag),
                 D$df %>% select(uniquekey, baby_id, stay_no, dedup_flag))

cat("\n1. Scenarios\n")
exp <- tibble::tribble(
  ~scenario, ~key, ~exp_baby, ~exp_stay,
  "1  one admission, one discharge",                       "a1",  "TEST-01.A", 1,
  "1  one admission, one discharge",                       "d1",  "TEST-01.A", 1,
  "3  two different babies under one UID",                 "a4",  "TEST-03.A", 1,
  "3  two different babies under one UID",                 "a5",  "TEST-03.B", 1,
  "3  discharge carrying the admission date",              "d2",  "TEST-03.A", 1,
  "3  discharge matched on sex, weight, gestation",        "d3",  "TEST-03.B", 1,
  "4  flagged readmission",                                "a6",  "TEST-04.A", 1,
  "4  flagged readmission",                                "a7",  "TEST-04.A", 2,
  "5  nothing disagrees, nothing more to compare",         "a8",  "TEST-05.A", 1,
  "5  nothing disagrees, nothing more to compare",         "a9",  "TEST-05.B", 1,
  "6  other fields agree",                                 "a10", "TEST-06.A", 1,
  "6  other fields agree",                                 "a11", "TEST-06.A", 2,
  "7  other fields differ",                                "a12", "TEST-07.A", 1,
  "7  other fields differ",                                "a13", "TEST-07.B", 1,
  "8  transfer: same UID at two sites",                    "a14", "TEST-08.A", 1,
  "8  transfer: same UID at two sites",                    "a15", "TEST-08.A", 2,
  "9  discharge with no admission",                        "d4",  "TEST-09.A", 1,
  "10 one admission, two discharge forms",                 "d5",  "TEST-10.A", 1,
  "10 one admission, two discharge forms",                 "d6",  "TEST-10.A", 1,
  "11 discharge fits two admissions: earlier one used",    "d7",  "TEST-11.A", 1,
  "12 discharge fits no admission under the UID",          "d8",  "TEST-12.B", 1,
  "13 admission time two hours off on the discharge form", "d9",  "TEST-13.B", 1,
  "14 readmission flag keeps rows within 1 hour apart",    "a22", "TEST-14.A", 1,
  "14 readmission flag keeps rows within 1 hour apart",    "a23", "TEST-14.A", 2,
  "16 identical times, identity differs: two babies",      "a27", "TEST-16.A", 1,
  "16 identical times, identity differs: two babies",      "a28", "TEST-16.B", 1
)
res <- exp %>% left_join(got, by = c(key = "uniquekey"))
for (i in seq_len(nrow(res)))
  check(sprintf("%s (%s -> %s stay %d)", res$scenario[i], res$key[i], res$exp_baby[i], res$exp_stay[i]),
        !is.na(res$baby_id[i]) && res$baby_id[i] == res$exp_baby[i] && res$stay_no[i] == res$exp_stay[i])

cat("\n2. Collapsing\n")
check("2  same record sent twice: one row kept, the more complete one (a3)",
      sum(A$df$uid %in% "TEST-02") == 1 && A$df$uniquekey[A$df$uid %in% "TEST-02"] == "a3" &&
        A$df$dedup_rows_merged[A$df$uid %in% "TEST-02"] == 2)
check("15 two discharge forms of one stay 10 minutes apart: collapsed (d9, d10)",
      sum(D$df$uid %in% "TEST-13") == 1)
check("17 no chaining: a25 fits a24 and a26, but a24 and a26 differ, so a26 stays apart",
      sum(A$df$uid %in% "TEST-15") == 2 && "a26" %in% A$df$uniquekey &&
        A$df$baby_id[A$df$uniquekey == "a26"] == "TEST-15.B")
check("18 row without a uid kept, flagged no_uid, no baby_id",
      "a29" %in% A$df$uniquekey && A$df$dedup_flag[A$df$uniquekey == "a29"] == "no_uid" &&
        is.na(A$df$baby_id[A$df$uniquekey == "a29"]))

cat("\n3. Flags\n")
flag_of <- function(k) got$dedup_flag[got$uniquekey == k]
check("5  unresolved record flagged (a9)", grepl("unresolved", flag_of("a9")))
check("6  decision on other fields flagged probable (a11)", grepl("probable", flag_of("a11")))
check("9  discharge with no admission flagged no_admission (d4)", grepl("no_admission", flag_of("d4")))
check("11 discharge fitting two admissions flagged ambiguous_link (d7)", grepl("ambiguous_link", flag_of("d7")))
check("10 death and discharge alive on one stay flagged outcome_conflict (d5, d6)",
      grepl("outcome_conflict", flag_of("d5")) && grepl("outcome_conflict", flag_of("d6")))
check("10 one primary form per stay",
      all((D$df %>% group_by(baby_id, stay_no) %>% summarise(p = sum(stay_form_primary), .groups = "drop"))$p == 1))
check("10 primary form is the one started last (d6)", D$df$stay_form_primary[D$df$uniquekey == "d6"])
check("1  settled record carries the flag none (a1)", identical(flag_of("a1"), "none"))

cat("\n4. Known totals\n")
check("admissions: 29 rows in, 27 kept", nrow(adm) == 29 && nrow(A$df) == 27)
check("admissions: 22 babies", A$summary[["distinct_babies"]] == 22)
check("admissions: 26 stays", A$summary[["distinct_stays"]] == 26)
check("discharges: 10 rows in, 9 kept", nrow(dis) == 10 && nrow(D$df) == 9)
check("every kept row with a uid has baby_id and stay_no",
      !anyNA(c(A$df$baby_id[!is.na(A$df$uid)], D$df$baby_id, A$df$stay_no[!is.na(A$df$uid)], D$df$stay_no)))

cat("\n5. Keys\n")
check("uid unchanged", all(A$df$uid %in% adm$uid) && all(D$df$uid %in% dis$uid) &&
        all(startsWith(na.omit(A$df$baby_id), paste0(A$df$uid[!is.na(A$df$uid)], "."))))
check("no kept rows share uid + facility + uniquekey",
      A$summary[["rows_sharing_uid_facility_uniquekey"]] == 0 &&
        D$summary[["rows_sharing_uid_facility_uniquekey"]] == 0)

col <- rbind(row("TEST-20", "H1", "k1", n(t0), sex = "M", bw = 2900, ga = 39),
             row("TEST-20", "H1", "k1", n(t0) + 50 * day, sex = "F", bw = 1800, ga = 33))
check("reused uniquekey on two kept rows is counted (Module 10 stops on it)",
      ep_dedup(col, "admissions")$summary[["rows_sharing_uid_facility_uniquekey"]] == 2)

cat("\n7. Discharge matching ranks identity before date\n")
a2 <- rbind(row("TEST-30", "H1", "r1", n(t0), sex = "M", bw = 2900, ga = 39),
            row("TEST-30", "H1", "r2", n(t0) + 1800, sex = "F", bw = 1800, ga = 33))
d2 <- rbind(row("TEST-30", "H1", "r3", n(t0) + 1800, n(t0) + 5 * day, sex = "F", bw = 1850, ga = 33))
A2 <- ep_dedup(a2, "admissions"); D2 <- ep_dedup(d2, "discharges", A2$keys)
check("two babies 30 minutes apart: the discharge goes to the baby it matches (TEST-30.B)",
      D2$df$baby_id == "TEST-30.B")
check("rows collapsed with no identity field to compare are flagged collapsed_no_identity",
      grepl("collapsed_no_identity",
            ep_dedup(rbind(row("TEST-31", "H1", "q1", n(t0)), row("TEST-31", "H1", "q2", n(t0) + 60)),
                     "admissions")$df$dedup_flag))

cat("\n8. Datasets covered\n")
check("admissions and phc_admissions play the admissions role",
      identical(ep_role(c("admissions", "phc_admissions")), c("admissions", "admissions")))
check("discharges and phc_discharges play the discharges role",
      identical(ep_role(c("discharges", "phc_discharges")), c("discharges", "discharges")))
check("other datasets are not covered", all(is.na(ep_role(c("neolab", "baseline", "dhis2_maternal_outcomes")))))
check("ZIM maternal_outcomes and MWI combined_maternity_outcomes play the births role",
      identical(c(ep_role("maternal_outcomes", "ZIM"), ep_role("combined_maternity_outcomes", "MWI")), c("births", "births")))
check("MWI maternal_outcomes (a component of the combined file) is not covered",
      is.na(ep_role("maternal_outcomes", "MWI")))

cat("\n9. Births\n")
brow <- function(uid, key, t, sex = NA, bw = NA, ga = NA, out = NA, tb = NA) {
  data.frame(uid = uid, facility = "H1", uniquekey = key,
             dateadmission.value = as.POSIXct(t, origin = "1970-01-01", tz = "UTC"),
             startedat = as.POSIXct(NA, tz = "UTC"),
             sexdis.value = sex, bwtdis.value = bw, gestation.value = ga,
             neotreeoutcome.value = out, typebirth.value = tb, stringsAsFactors = FALSE)
}
births <- rbind(
  brow("TEST-40", "m1", n(t0), "M", 3000, 39, "LB"),
  brow("TEST-41", "m2", n(t0), "M", 3000, 39, "LB"),
  brow("TEST-41", "m3", n(t0) + 600, "M", 3000, 39, "LB"),
  brow("TEST-42", "m4", n(t0), "M", 2400, 36, "LB", "Tw1"),
  brow("TEST-42", "m5", n(t0) + 300, "F", 2300, 36, "LB", "Tw2"),
  brow("TEST-43", "m6", n(t0), "M", 2400, 36, "LB", "Tw1"),
  brow("TEST-43", "m7", n(t0) + 300, "M", 2420, 36, "LB", "Tw2"),
  brow("TEST-44", "m8", n(t0), "F", 3100, 40, "LB"),
  brow("TEST-44", "m9", n(t0) + 300, "F", 3100, 40, "STBM"),
  brow("TEST-45", "m10", n(t0), "F", 3100, 40, "LB"),
  brow("TEST-45", "m11", n(t0) + 200 * day, "M", 2500, 38, "LB"),
  brow("TEST-46", "m12", n(t0), "F", 3100, 40, "LB"),
  brow("TEST-46", "m13", n(t0) + 5 * 3600, "F", 3100, 40, "LB"),
  brow("TEST-47", "m14", n(t0), "M", 2900, 38, "LB"),
  brow("TEST-47", "m15", n(t0) + 300, "M", 2900, 38, "STB")
)
B <- ep_dedup(births, "births")
bget <- function(k, col) B$df[[col]][B$df$uniquekey == k]
check("births: the same record sent twice is collapsed (m2, m3)", sum(B$df$uid %in% "TEST-41") == 1)
check("births: twins of different sex under one UID are two babies (m4, m5)",
      bget("m4", "baby_id") == "TEST-42.A" && bget("m5", "baby_id") == "TEST-42.B")
check("births: same-sex twins of similar weight are kept apart by birth order (m6, m7)",
      sum(B$df$uid %in% "TEST-43") == 2)
check("births: live birth and stillbirth are not collapsed (m8, m9)", sum(B$df$uid %in% "TEST-44") == 2)
check("births: a same-day pair is flagged same_day_pair (m5)", grepl("same_day_pair", bget("m5", "dedup_flag")))
check("births: a different baby on another day gets its own letter, no flag (m11)",
      bget("m11", "baby_id") == "TEST-45.B" && bget("m11", "dedup_flag") == "none")
check("births: same day, nothing differs, more than 1 hour apart is unresolved (m13)",
      grepl("unresolved", bget("m13", "dedup_flag")) && bget("m13", "baby_id") == "TEST-46.B")
check("births: no stay_no column", !"stay_no" %in% names(B$df))
check("births: LB and STB within the hour are two babies (m14, m15)",
      bget("m14", "baby_id") == "TEST-47.A" && bget("m15", "baby_id") == "TEST-47.B")
check("births: 15 rows in, 14 kept, 14 babies", nrow(B$df) == 14 && B$summary[["distinct_babies"]] == 14)

cat("\n6. Admissions key file\n")
root <- file.path(tempdir(), "ep_root"); dir.create(file.path(root, "05_step"), recursive = TRUE)
dir.create(file.path(root, "00b_after"))
writeLines("x <- 1", file.path(root, "05_step", "05_step.r"))
writeLines("y <- 1", file.path(root, "00b_after", "00b_after.r"))
src <- tempfile(fileext = ".csv"); writeLines("a,b", src)
kp  <- tempfile(fileext = ".rds")
dct <- tempfile(fileext = ".xlsx"); writeLines("d0", dct)
wk  <- function() ep_write_keys(A$keys, kp, src, dct, unname(tools::md5sum(dct)), root)
wk()
check("key file read back for the same admissions file and code", nrow(ep_read_keys(kp, src, root)) == nrow(A$keys))
writeLines("y <- 2", file.path(root, "00b_after", "00b_after.r"))
check("key file still accepted after a change to code that runs after Module 10",
      !inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
writeLines("x <- 2", file.path(root, "05_step", "05_step.r"))
check("key file refused after a change to code that runs before the keys are built",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
dir.create(file.path(root, "00_build_dictionary")); dir.create(file.path(root, "dictionaries"))
writeLines("z <- 1", file.path(root, "00_build_dictionary", "build.r"))
writeLines("v1", file.path(root, "dictionaries", "dictionary_test.xlsx"))
wk()
writeLines("z <- 2", file.path(root, "00_build_dictionary", "build.r"))
check("key file refused after a change to the dictionary build code",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
wk()
writeLines("v2", file.path(root, "dictionaries", "dictionary_test.xlsx"))
check("key file refused after a dictionary workbook changed",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
wk()
writeLines(c("a,b", "1,2"), src)
check("key file refused after the admissions file changed",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
wk()
check("key file read back while the dictionary used is unchanged",
      nrow(ep_read_keys(kp, src, root)) == nrow(A$keys))
writeLines("d1", dct)
check("key file refused after the dictionary used by the admissions run changed",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
check("key file not written when the dictionary changed after it was read",
      inherits(try(ep_write_keys(A$keys, kp, src, dct, "stale-md5", root), silent = TRUE), "try-error"))
check("key file not written without a dictionary",
      inherits(try(ep_write_keys(A$keys, kp, src, NULL, NULL, root), silent = TRUE), "try-error"))
obj <- readRDS(kp); obj$dict <- NULL; saveRDS(obj, kp)
check("key file without a dictionary fingerprint refused",
      inherits(try(ep_read_keys(kp, src, root), silent = TRUE), "try-error"))
check("missing key file refused", inherits(try(ep_read_keys(tempfile(), src, root), silent = TRUE), "try-error"))

cat(sprintf("\n=== %d test(s): %d passed, %d failed ===\n", n_pass + n_fail, n_pass, n_fail))
quit(status = if (n_fail > 0) 1 else 0)
