# =============================================================================
# validate_dictionaries.r
# =============================================================================
# Checks that every dictionary_*.xlsx produced by 00_build_dictionary_v8.r
# contains all the sheets, columns, and data quality constraints required by
# the Neotree cleaning pipeline (00_setup.r and downstream modules).
#
# HOW TO RUN:
#   source("00_build_dictionary/validate_dictionaries.r")
#   # or from the command line:
#   Rscript 00_build_dictionary/validate_dictionaries.r
#
# WHAT IS CHECKED:
#   1.  All 6 core expected files exist; extended files validated if present.
#   2.  Each file has sheets: Variables, ValueMaps, PII_Patterns, ReviewNeeded.
#   3.  Variables sheet contains every column consumed by 00_setup.r and the
#       PII tier columns (pii_tier, pii_category, pii_matching_pattern).
#   4.  ValueMaps sheet contains every column consumed by Module 04.
#   5.  PII_Patterns sheet has all required columns, at least one pattern,
#       no blank pattern strings, and no duplicate patterns.
#   6.  No r_type value is NA for use_in_analysis=TRUE rows.
#   7.  ValueMaps question_keys are a subset of Variables question_keys.
#   8.  Numeric rows with ranges have valid (min < max) bounds.
#   9.  pii_tier values are valid ("1", "2", "quasi", or NA).
#       Tier 2 fields must have a non-null pii_matching_pattern.
#       confidential=TRUE fields must have pii_tier in ("1", "2").
#   10. Spot-check: MANUAL_RANGES entries (Apgar, SpO2, Thompson) are present
#       in ZIM admissions with correct bounds.
#   11. Summary statistics printed per dictionary, including PII tier counts.
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is required. Install with: install.packages('openxlsx')")
  }
  library(openxlsx)
})

# -- Configuration -------------------------------------------------------------

# Resolve the script's own directory robustly.
# Works with: source(), Rscript --file=, RStudio, plain R console.
.get_script_dir <- function() {
  # 1. Rscript --file= invocation
  args     <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0)
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))

  # 2. source() call -- walk the call stack for the ofile slot
  for (i in seq_len(sys.nframe())) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile) && nchar(ofile) > 0)
      return(dirname(normalizePath(ofile)))
  }

  # 3. RStudio interactive (optional -- only loaded when available)
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    ctx <- tryCatch(rstudioapi::getSourceEditorContext(), error = function(e) NULL)
    if (!is.null(ctx) && nchar(ctx$path) > 0)
      return(dirname(normalizePath(ctx$path)))
  }

  # 4. Fallback: working directory (correct when sourced from pipeline root)
  getwd()
}

SCRIPT_DIR    <- .get_script_dir()
PIPELINE_ROOT <- normalizePath(file.path(SCRIPT_DIR, ".."), mustWork = FALSE)
DICT_DIR      <- file.path(PIPELINE_ROOT, "dictionaries")

# Core dictionaries -- always required
EXPECTED_FILES <- c(
  "dictionary_zim_admissions.xlsx",
  "dictionary_zim_discharges.xlsx",
  "dictionary_zim_maternal_outcomes.xlsx",
  "dictionary_mwi_admissions.xlsx",
  "dictionary_mwi_discharges.xlsx",
  "dictionary_mwi_maternal_outcomes.xlsx"
)

# Extended dictionaries -- optional (validated if present, skipped if absent)
OPTIONAL_FILES <- c(
  # ZIM extended
  "dictionary_zim_phc_admissions.xlsx",
  "dictionary_zim_phc_discharges.xlsx",
  "dictionary_zim_neolab.xlsx",
  "dictionary_zim_infections.xlsx",
  "dictionary_zim_baseline.xlsx",
  "dictionary_zim_twenty_8_day_follow_up.xlsx",
  # MWI extended
  "dictionary_mwi_phc_admissions.xlsx",
  "dictionary_mwi_phc_discharges.xlsx",
  "dictionary_mwi_neolab.xlsx",
  "dictionary_mwi_combined_maternity_outcomes.xlsx",
  "dictionary_mwi_dhis2_maternal_outcomes.xlsx",
  "dictionary_mwi_maternity_completeness.xlsx"
)

# Columns required by 00_setup.r / downstream modules
REQUIRED_VAR_COLS <- c(
  "environment", "dataset", "question_key",
  "raw_value_column", "raw_label_column",
  "variable_label", "raw_data_type", "r_type", "section",
  "harmonised_variable_name", "use_in_analysis",
  "weight_unit", "confidential",
  "record_id_role", "linkage_role",
  "suggested_plausible_min", "suggested_plausible_max",
  "cleaning_note", "key_unique_key",
  # PII tier columns -- added by 00_build_dictionary_v8.r
  "pii_tier", "pii_category", "pii_matching_pattern"
)

# Columns required by Module 04 (dictionary-based value cleaning)
REQUIRED_VM_COLS <- c(
  "question_key", "raw_code", "option_label",
  "option_order", "option_uuid", "canonical_code"
)

# Columns required in the PII_Patterns sheet
REQUIRED_PII_COLS <- c(
  "pattern", "pattern_type", "pii_category",
  "reason", "countries", "examples", "added_date", "notes"
)

# Valid pii_tier values (NA = field is not PII)
VALID_PII_TIERS <- c("1", "2", "quasi")

# Spot-check: MANUAL_RANGES entries for ZIM admissions.
# NOTE: Continuous physiological measures (temperature, birthweight, gestation,
# heart rate etc.) deliberately have NO range set -- extreme values are retained
# for analyst review. Only fields with formally defined hard limits are checked.
EXPECTED_RANGES_ZIM_ADM <- list(
  apgar1     = c(0,   10),
  apgar5     = c(0,   10),
  apgar10    = c(0,   10),
  satsair    = c(0,  100),
  satso2     = c(0,  100),
  thompscore = c(0,   22)
)

# -- Helpers -------------------------------------------------------------------

read_sheet_df <- function(wb, sheet_name) {
  tryCatch(
    readWorkbook(wb, sheet = sheet_name, colNames = TRUE),
    error = function(e) NULL
  )
}

cat_line <- function(...) cat(paste0(..., "\n"))

tag_ok   <- function(msg) cat_line("  [OK]  ", msg)
tag_fail <- function(msg) cat_line("  [FAIL]  ", msg)
tag_warn <- function(msg) cat_line("  [WARN]  ", msg)

# -- Main ----------------------------------------------------------------------

all_failures <- character(0)
all_warnings <- character(0)

cat_line(strrep("=", 70))
cat_line("Neotree Dictionary Validation")
cat_line(strrep("=", 70))

# 1. File existence ------------------------------------------------------------
cat_line("\n[1] Checking file existence...")

for (fname in EXPECTED_FILES) {
  fpath <- file.path(DICT_DIR, fname)
  if (file.exists(fpath)) {
    tag_ok(fname)
  } else {
    all_failures <- c(all_failures, paste("Missing file:", fname))
    tag_fail(paste("MISSING:", fname))
  }
}

present_optional <- character(0)
for (fname in OPTIONAL_FILES) {
  fpath <- file.path(DICT_DIR, fname)
  if (file.exists(fpath)) {
    cat_line("  [OK]  (optional) ", fname)
    present_optional <- c(present_optional, fname)
  } else {
    cat_line("  -  (optional, not yet built) ", fname)
  }
}

files_to_validate <- c(EXPECTED_FILES, present_optional)

# 2-11. Per-file checks --------------------------------------------------------
for (fname in files_to_validate) {
  fpath <- file.path(DICT_DIR, fname)
  if (!file.exists(fpath)) next

  failures <- character(0)
  warnings <- character(0)

  cat_line("\n[", fname, "]")

  wb <- tryCatch(
    loadWorkbook(fpath),
    error = function(e) {
      all_failures <<- c(all_failures, paste0(fname, ": could not open -- ", e$message))
      cat_line("  [FAIL]  Could not open: ", e$message)
      NULL
    }
  )
  if (is.null(wb)) next

  sheet_names <- names(wb)

  # 2. Sheet presence ----------------------------------------------------------
  for (sname in c("Variables", "ValueMaps", "PII_Patterns", "ReviewNeeded")) {
    if (sname %in% sheet_names) {
      tag_ok(paste("Sheet present:", sname))
    } else {
      failures <- c(failures, paste("Missing sheet:", sname))
      tag_fail(paste("Missing sheet:", sname))
    }
  }

  if (!("Variables" %in% sheet_names && "ValueMaps" %in% sheet_names)) {
    all_failures <- c(all_failures, failures)
    next
  }

  # 3. Variables columns -------------------------------------------------------
  var_df <- read_sheet_df(wb, "Variables")
  if (is.null(var_df)) {
    failures <- c(failures, "Could not read Variables sheet")
    tag_fail("Could not read Variables sheet")
  } else {
    missing_var <- setdiff(REQUIRED_VAR_COLS, names(var_df))
    if (length(missing_var) > 0) {
      msg <- paste("Variables missing columns:", paste(sort(missing_var), collapse = ", "))
      failures <- c(failures, msg)
      tag_fail(msg)
    } else {
      tag_ok(paste0("Variables columns complete (", nrow(var_df), " rows)"))
    }
  }

  # 4. ValueMaps columns -------------------------------------------------------
  vm_df <- read_sheet_df(wb, "ValueMaps")
  if (is.null(vm_df)) {
    failures <- c(failures, "Could not read ValueMaps sheet")
    tag_fail("Could not read ValueMaps sheet")
  } else {
    missing_vm <- setdiff(REQUIRED_VM_COLS, names(vm_df))
    if (length(missing_vm) > 0) {
      msg <- paste("ValueMaps missing columns:", paste(sort(missing_vm), collapse = ", "))
      failures <- c(failures, msg)
      tag_fail(msg)
    } else {
      tag_ok(paste0("ValueMaps columns complete (", nrow(vm_df), " rows)"))
    }
  }

  # 5. PII_Patterns sheet ------------------------------------------------------
  if ("PII_Patterns" %in% sheet_names) {
    pii_df <- read_sheet_df(wb, "PII_Patterns")
    if (!is.null(pii_df)) {
      missing_pii <- setdiff(REQUIRED_PII_COLS, names(pii_df))
      if (length(missing_pii) > 0) {
        msg <- paste("PII_Patterns missing columns:", paste(sort(missing_pii), collapse = ", "))
        failures <- c(failures, msg)
        tag_fail(msg)
      } else {
        tag_ok("PII_Patterns columns complete")
      }

      if (nrow(pii_df) == 0) {
        failures <- c(failures, "PII_Patterns sheet is empty")
        tag_fail("PII_Patterns sheet is empty")
      } else {
        tag_ok(paste0("PII_Patterns has ", nrow(pii_df), " pattern(s)"))
      }

      if ("pattern" %in% names(pii_df)) {
        blank_rows <- which(is.na(pii_df$pattern) | trimws(pii_df$pattern) == "")
        if (length(blank_rows) > 0) {
          msg <- paste("PII_Patterns: blank pattern in row(s)", paste(blank_rows + 1, collapse = ", "))
          failures <- c(failures, msg)
          tag_fail(msg)
        } else {
          tag_ok("All PII_Patterns pattern strings non-empty")
        }

        pat_vals <- pii_df$pattern[!is.na(pii_df$pattern)]
        dupes <- names(which(table(pat_vals) > 1))
        if (length(dupes) > 0) {
          msg <- paste("PII_Patterns: duplicate pattern(s):", paste(dupes, collapse = ", "))
          warnings <- c(warnings, msg)
          tag_warn(msg)
        } else {
          tag_ok("No duplicate patterns in PII_Patterns")
        }
      }
    }
  }

  if (is.null(var_df) || is.null(vm_df)) {
    all_failures <- c(all_failures, failures)
    all_warnings <- c(all_warnings, warnings)
    next
  }

  # 6. No null r_type for use_in_analysis rows ---------------------------------
  if ("r_type" %in% names(var_df) && "use_in_analysis" %in% names(var_df) &&
      "question_key" %in% names(var_df)) {
    null_rtypes <- var_df$question_key[
      var_df$use_in_analysis %in% TRUE & is.na(var_df$r_type)
    ]
    if (length(null_rtypes) > 0) {
      msg <- paste0("Null r_type for ", length(null_rtypes),
                    " use_in_analysis rows: ", paste(head(null_rtypes, 5), collapse = ", "))
      warnings <- c(warnings, msg)
      tag_warn(paste0("Null r_type in ", length(null_rtypes), " use_in_analysis rows"))
    } else {
      tag_ok("All use_in_analysis rows have r_type")
    }
  }

  # 7. ValueMap keys subset of Variable keys -----------------------------------
  if ("question_key" %in% names(var_df) && "question_key" %in% names(vm_df)) {
    var_qkeys <- unique(var_df$question_key)
    vm_qkeys  <- unique(vm_df$question_key)
    orphan_vm <- setdiff(vm_qkeys, var_qkeys)
    if (length(orphan_vm) > 0) {
      msg <- paste0("ValueMap keys not in Variables: ",
                    paste(head(sort(orphan_vm), 5), collapse = ", "))
      warnings <- c(warnings, msg)
      tag_warn(paste0(length(orphan_vm), " ValueMap keys not in Variables"))
    } else {
      tag_ok("All ValueMap keys present in Variables")
    }
  }

  # 8. Valid numeric ranges (min < max) ----------------------------------------
  if ("suggested_plausible_min" %in% names(var_df) &&
      "suggested_plausible_max" %in% names(var_df) &&
      "question_key" %in% names(var_df)) {
    rmin <- suppressWarnings(as.numeric(var_df$suggested_plausible_min))
    rmax <- suppressWarnings(as.numeric(var_df$suggested_plausible_max))
    bad  <- which(!is.na(rmin) & !is.na(rmax) & rmin >= rmax)
    if (length(bad) > 0) {
      msg <- paste("Invalid ranges (min >= max):", paste(var_df$question_key[bad], collapse = ", "))
      failures <- c(failures, msg)
      tag_fail(msg)
    } else {
      tag_ok("All numeric ranges valid (min < max)")
    }
  }

  # 9. PII tier consistency ----------------------------------------------------
  if ("pii_tier" %in% names(var_df) && "question_key" %in% names(var_df)) {
    actual_tiers <- var_df$pii_tier
    invalid_tiers <- var_df$question_key[
      !is.na(actual_tiers) & !(actual_tiers %in% VALID_PII_TIERS)
    ]
    if (length(invalid_tiers) > 0) {
      msg <- paste("Invalid pii_tier values for:", paste(head(invalid_tiers, 5), collapse = ", "))
      failures <- c(failures, msg)
      tag_fail(paste0("Invalid pii_tier values in ", length(invalid_tiers), " row(s)"))
    } else {
      tag_ok("All pii_tier values valid")
    }

    if ("pii_matching_pattern" %in% names(var_df)) {
      tier2_no_pat <- var_df$question_key[
        !is.na(actual_tiers) & actual_tiers == "2" &
        (is.na(var_df$pii_matching_pattern) | trimws(var_df$pii_matching_pattern) == "")
      ]
      if (length(tier2_no_pat) > 0) {
        msg <- paste("Tier 2 fields missing pii_matching_pattern:",
                     paste(head(tier2_no_pat, 5), collapse = ", "))
        warnings <- c(warnings, msg)
        tag_warn(paste0(length(tier2_no_pat), " Tier 2 field(s) missing pii_matching_pattern"))
      } else {
        tag_ok("All Tier 2 fields have pii_matching_pattern")
      }
    }

    if ("confidential" %in% names(var_df)) {
      conf_not_pii <- var_df$question_key[
        var_df$confidential %in% TRUE &
        (is.na(actual_tiers) | !(actual_tiers %in% c("1", "2")))
      ]
      if (length(conf_not_pii) > 0) {
        msg <- paste("confidential=TRUE fields without pii_tier 1/2:",
                     paste(head(conf_not_pii, 5), collapse = ", "))
        warnings <- c(warnings, msg)
        tag_warn(paste0(length(conf_not_pii), " confidential field(s) without pii_tier 1/2"))
      } else {
        tag_ok("All confidential=TRUE fields have pii_tier 1 or 2")
      }
    }
  }

  # 10. Spot-check MANUAL_RANGES entries for ZIM admissions -------------------
  if (grepl("zim_admissions", fname, ignore.case = TRUE) &&
      "question_key" %in% names(var_df)) {
    rmin_lookup <- stats::setNames(
      suppressWarnings(as.numeric(var_df$suggested_plausible_min)),
      var_df$question_key
    )
    rmax_lookup <- stats::setNames(
      suppressWarnings(as.numeric(var_df$suggested_plausible_max)),
      var_df$question_key
    )
    for (qk in names(EXPECTED_RANGES_ZIM_ADM)) {
      exp <- EXPECTED_RANGES_ZIM_ADM[[qk]]
      act_min <- rmin_lookup[qk]
      act_max <- rmax_lookup[qk]
      if (is.na(act_min) && is.na(act_max)) {
        msg <- paste0("Expected MANUAL_RANGES entry for '", qk, "' not found")
        warnings <- c(warnings, msg)
        tag_warn(paste0("No range for expected key: ", qk))
      } else if (!isTRUE(act_min == exp[1]) || !isTRUE(act_max == exp[2])) {
        msg <- paste0("Range for '", qk, "' = [", act_min, ", ", act_max, "], ",
                      "expected [", exp[1], ", ", exp[2], "]")
        warnings <- c(warnings, msg)
        tag_warn(msg)
      } else {
        tag_ok(paste0("Range for ", qk, ": [", exp[1], ", ", exp[2], "]"))
      }
    }
  }

  # 11. Summary statistics ------------------------------------------------------
  rtype_counts <- if ("r_type" %in% names(var_df)) table(var_df$r_type, useNA = "no") else table(character(0))
  pii_counts   <- if ("pii_tier" %in% names(var_df)) table(var_df$pii_tier[!is.na(var_df$pii_tier)]) else table(character(0))

  rev_df  <- if ("ReviewNeeded" %in% sheet_names) read_sheet_df(wb, "ReviewNeeded") else data.frame()
  n_rev   <- if (is.null(rev_df)) 0L else nrow(rev_df)

  cat_line("")
  cat_line("  Summary: ", nrow(var_df), " variables | ", nrow(vm_df),
           " value-map rows | ", n_rev, " review items")
  if (length(rtype_counts) > 0) {
    cat_line("  r_type counts: ",
             paste(names(rtype_counts), rtype_counts, sep = "=", collapse = ", "))
  }
  if (length(pii_counts) > 0) {
    cat_line("  pii_tier counts: ",
             paste(names(pii_counts), pii_counts, sep = "=", collapse = ", "))
  } else {
    cat_line("  pii_tier: no fields classified (pii_tier column absent or all NA)")
  }

  all_failures <- c(all_failures, failures)
  all_warnings <- c(all_warnings, warnings)
}

# -- Final report --------------------------------------------------------------
cat_line("\n", strrep("=", 70))
cat_line("VALIDATION SUMMARY")
cat_line(strrep("=", 70))

if (length(all_warnings) > 0) {
  cat_line("\n", length(all_warnings), " warning(s):")
  for (w in all_warnings) cat_line("  [WARN]  ", w)
}

if (length(all_failures) > 0) {
  cat_line("\n", length(all_failures), " FAILURE(S):")
  for (f in all_failures) cat_line("  [FAIL]  ", f)
  cat_line("\nResult: FAIL -- fix the issues above and re-run.\n")
  if (!interactive()) quit(status = 1)
} else {
  n_core     <- sum(file.exists(file.path(DICT_DIR, EXPECTED_FILES)))
  n_optional <- length(present_optional)
  cat_line("\nResult: ALL CHECKS PASSED [OK]")
  cat_line("  ", n_core, "/", length(EXPECTED_FILES), " core dictionaries validated.")
  if (n_optional > 0) {
    cat_line("  ", n_optional, " optional extended dictionaries also validated.")
  } else {
    cat_line("  0 optional extended dictionaries present ",
             "(run the build script to generate them).")
  }
  cat_line("Dictionaries are compatible with the Neotree cleaning pipeline.\n")
  if (!interactive()) quit(status = 0)
}
