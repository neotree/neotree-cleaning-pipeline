# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00_build: Build the v8 Unified Data Dictionary
# =============================================================================
#
# PURPOSE:
#   Constructs one dictionary Excel workbook per country x dataset combination
#   directly from the official Neotree web-editor data-key exports (JSON +
#   usage XLSX).  No ChatGPT-derived files or prior dictionary versions are
#   required.
#
#   Output files (written to dictionaries/):
#     Standard (both countries):
#       dictionary_zim_admissions.xlsx
#       dictionary_zim_discharges.xlsx
#       dictionary_zim_maternal_outcomes.xlsx
#       dictionary_mwi_admissions.xlsx
#       dictionary_mwi_discharges.xlsx
#       dictionary_mwi_maternal_outcomes.xlsx
#
#     Extended (Malawi PHC + Combined Maternity + individual maternal sources):
#       dictionary_mwi_phc_admissions.xlsx
#       dictionary_mwi_phc_discharges.xlsx
#       dictionary_mwi_combined_maternity_outcomes.xlsx
#       dictionary_mwi_dhis2_maternal_outcomes.xlsx
#       dictionary_mwi_maternity_completeness.xlsx
#
#     Extended (Zimbabwe PHC):
#       dictionary_zim_phc_admissions.xlsx
#       dictionary_zim_phc_discharges.xlsx
#
#     Extended (Zimbabwe-specific longitudinal & follow-up forms):
#       dictionary_zim_baseline.xlsx
#       dictionary_zim_infections.xlsx
#       dictionary_zim_twenty_8_day_follow_up.xlsx
#
# INPUTS (from NEOTREE_DATA_KEYS/DOWNLOADED/):
#   Neotree Data Keys Zimbabwe/data-keys-metadata.json   <- all field definitions
#   Neotree Data Keys Zimbabwe/data-keys-usage.xlsx      <- which scripts use each key
#   Neotree Data Keys Malawi/data-keys-metadata.json
#   Neotree Data Keys Malawi/data-keys-usage.xlsx
#
# DICTIONARY SHEETS:
#   Variables    - one row per unique key, fully annotated for the pipeline
#   ValueMaps    - one row per allowed option code with its display label
#   ReviewNeeded - items flagged for manual QA (see notes below)
#
# -- ABOUT ReviewNeeded --------------------------------------------------------
#   Items are listed here when they need attention BEFORE the pipeline can fully
#   validate them.  Three categories are flagged:
#
#   1. "Categorical with no value map entries"
#      A single_select / dropdown / yesno / diagnosis field has no recognised
#      option values in the web-editor export.  The pipeline will still clean
#      the column, but cannot validate individual codes against an allow-list.
#      ACTION: Either (a) open the ValueMaps sheet and add the known valid codes
#      manually, or (b) confirm the field truly has no fixed options (free-text
#      disguised as a dropdown).  This is the most common category and does NOT
#      block the pipeline from running.
#
#   2. "Numeric without plausible range"
#      A numeric / period / timer field has no min/max defined.  Out-of-range
#      values will not be flagged in Module 11.
#      ACTION: Add the key + its min/max to the MANUAL_RANGES list below, then
#      re-run this script.
#
#   3. "Unknown pipeline_type"
#      The dataType from the web editor is not mapped in PIPELINE_TYPE_MAP.
#      This only happens if Neotree introduces a new field type.
#      ACTION: Add the new type to PIPELINE_TYPE_MAP.
#
#   You do NOT need to resolve every item before running the pipeline.
#   ReviewNeeded is purely informational - the pipeline handles unlisted fields
#   gracefully.
#
# HOW TO RUN:
#   1. Open an R session with working directory = neotree_cleaning_pipeline/
#   2. source("00_build_dictionary/00_build_dictionary_v8.r")
#   3. dictionary_*.xlsx files appear in the dictionaries/ folder.
#   4. Run the main pipeline as normal via run_pipeline.r.
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(writexl)
  library(janitor)
  library(purrr)
  library(logger)
})

# -----------------------------------------------------------------------------
# Run-from-anywhere: anchor the working directory to the pipeline root so every
# relative path below (data keys, dictionaries/, 00_build_dictionary/, the log
# file) resolves regardless of where the script was launched (Rscript,
# source(), RStudio "Source", or the R console).  This file lives in
# 00_build_dictionary/, so the pipeline root is one level up.
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

log_appender(appender_tee(file = "neotree_pipeline.log"))
log_threshold(INFO)

# =============================================================================
# USER CONFIGURATION  -  edit these paths if the folder layout changes
# =============================================================================

# Root of the downloaded data-key exports (relative to the pipeline root, which
# the working directory is anchored to above).  Lower-case to match the on-disk
# folder name so it also resolves on case-sensitive filesystems (e.g. a Linux
# GitHub clone), not only on case-insensitive macOS/Windows.
DOWNLOADED_KEYS_BASE <- "neotree_data_keys/downloaded"

# Subfolder name for each country inside DOWNLOADED_KEYS_BASE
COUNTRY_FOLDERS <- list(
  ZIM = "neotree_data_keys_zimbabwe",
  MWI = "neotree_data_keys_malawi"
)

# Output directory for the generated dictionary xlsx files
OUTPUT_DIR <- "dictionaries"
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# Directory containing this script (relative to pipeline root)
# Used to resolve sibling files such as user_ranges.xlsx
SCRIPT_DIR <- "00_build_dictionary"

# =============================================================================
# CONSTANTS
# =============================================================================

# Direct mapping: web-editor dataType -> r_type used throughout the pipeline
# (single level - no intermediate step needed)
PIPELINE_TYPE_MAP <- c(
  number                 = "numeric",
  period                 = "numeric",
  timer                  = "numeric",
  date                   = "datetime",
  datetime               = "datetime",
  yesno                  = "boolean",
  single_select          = "categorical",
  dropdown               = "categorical",
  multi_select           = "categorical",
  checklist              = "categorical",
  diagnosis              = "categorical",
  diagnosis_symptom_risk = "categorical",
  diagnosis_symptom_sign = "categorical",
  text                   = "object",
  zw_edliz_summary_table = "object",
  mwi_edliz_summary_table = "object"   # Malawi equivalent of zw_edliz_summary_table
)

# Which web-editor dataTypes are "categorical" (need a ValueMap)
CATEGORICAL_TYPES <- c(
  "single_select", "dropdown", "multi_select", "checklist",
  "diagnosis", "diagnosis_symptom_risk", "diagnosis_symptom_sign", "yesno"
)

# Dataset filter: maps dataset name -> regex for ScriptTitle in usage file
#
# Standard datasets (both countries):
#   admissions                  - all scripts with "Admission" in title
#   discharges                  - all scripts with "Discharge" in title
#   maternal_outcomes           - all scripts with "Maternal" in title
#
# Extended datasets:
#   phc_admissions              - Primary Health Care admission scripts
#   phc_discharges              - Primary Health Care discharge scripts
#   combined_maternity_outcomes - Maternal outcomes + DHIS2 maternity data
#                                 (superset of maternal_outcomes; includes DHIS2 Mat keys)
#   dhis2_maternal_outcomes     - DHIS2-linked maternal scripts only
#   maternity_completeness      - Maternity completeness / tracker scripts
#
# Note: "joined_admissions_discharges" is not built from the web-editor keys;
#   it is produced by joining cleaned admissions + discharges data frames.
#   No separate dictionary is generated for it.
DATASET_FILTERS <- list(
  admissions                  = "Admission",
  discharges                  = "Discharge",
  maternal_outcomes           = "Maternal",
  phc_admissions              = "PHC.*Admission|Generic PHC Admission|Kasungu.*Admission",
  phc_discharges              = "PHC.*Discharge|Generic PHC Discharge|NeoDischarge.*PHC",
  combined_maternity_outcomes = "Maternal|DHIS2 Mat|Maternity",
  dhis2_maternal_outcomes     = "DHIS2.*Mat|DHIS.*Matern",
  # maternity_completeness was introduced manually from paper records -- no dedicated
  # Neotree script exists for it. The regex below deliberately matches the same
  # maternal outcomes scripts so the dictionary is built from the closest available
  # approximation. At pipeline runtime, DICT_FALLBACK also maps this dataset to
  # the maternal_outcomes dictionary.
  maternity_completeness      = "Maternal",
  # Neolab (blood culture): matches "NeoLab - Zim" and "NeoLab - Malawi" only.
  # Deliberately excludes "NeoLab - Test 1" (test copy), "xNeolab" (retired older
  # script with different key names), and any other NeoLab variants.
  neolab                      = "^NeoLab - (Zim|Malawi)",
  # Zimbabwe-specific extended forms.
  # Adjust the regex strings below if the exact script titles in the ZIM
  # web-editor export differ from these patterns.
  baseline                    = "Baseline|Retrospective",
  # infections is a server-side derived file (all rows have Transformed = TRUE,
  # Scriptid is empty for >99% of rows). No dedicated Neotree script exists for it
  # in the web editor. The regex below matches the NeoLab script as the closest
  # available approximation. In 00c, 'infections' is aliased to 'neolab' in
  # normalise_dataset_name(), so enrichment uses the NeoLab script JSON; most
  # infections fields will not be found there (expected low enrichment rate).
  infections                  = "Infection|NeoInfect",
  twenty_8_day_follow_up      = "28.?[Dd]ay|Follow.?[Uu]p|28.*[Ff]ollow|NeoFollow"
)

# Record-level identifier keys (preserved, not treated as analysis variables)
RECORD_ID_KEYS <- c(
  "uid", "facility", "uniquekey", "startedat", "completedat",
  "ingestedat", "startedatdischarge", "completedatdischarge",
  "ingestedatdischarge", "uniquekeydischarge"
)

# Weight keys whose raw values may be in kg -> flagged for g conversion in Module 11
WEIGHT_KEYS_GRAMS <- c(
  "admissionweight", "birthweight", "bwtdis", "aw", "bwbid", "dischweight"
)

# Manual plausible ranges: lowercased question_key -> c(min, max)
#
# PHILOSOPHY: ranges are only set for variables whose scoring system defines
# hard biological limits -- i.e. values outside the range are definitively data
# entry errors, not unusual-but-real clinical findings.  Continuous physiological
# measures (weight, gestation, temperature, heart rate, etc.) have NO range set:
# extreme values should be retained and assessed in analysis rather than silently
# replaced with NA by Module 11.
#
# Hard limits retained:
#   apgar1/5/10         - Apgar scale is formally 0-10; an 11 is an entry error.
#   satsair/satso2      - Oxygen saturation is a percentage: 0-100 is a physical limit.
#   dischsats           - SpO2 at discharge (single reading on the discharge form,
#                         not split by air vs supplemental O2). Same definitional
#                         rationale as satsair/satso2: a percentage cannot exceed 100
#                         or be negative.
#   thompscore          - Thompson HIE scale has a fixed maximum of 22.
MANUAL_RANGES <- list(
  apgar1           = c(0,     10),
  apgar5           = c(0,     10),
  apgar10          = c(0,     10),
  satsair          = c(0,    100),
  satso2           = c(0,    100),
  dischsats        = c(0,    100),
  thompscore       = c(0,     22),
  # Neolab (blood culture) ranges -- set conservatively based on data distributions.
  # These limits are intended to remove only clear data-entry errors while retaining
  # unusual-but-plausible values from busy or resource-limited laboratory settings.
  #
  # bcreturntime: hours from specimen collection to result.
  #   Lower bound 0: negatives are impossible (confirmed in raw data: ~46 ZIM, ~10 MWI).
  #   Upper bound 1440h (60 days): a conservative ceiling. Raw data shows a clear
  #   discontinuity at ~432h (ZIM p95) before impossible values of 5000-14000h appear.
  #   MWI values reach ~1000h (42 days) which is plausible for delayed reporting;
  #   1440h gives comfortable headroom above this.
  #
  # poshours: hours from incubation start to positivity signal (ZIM only).
  #   Upper bound 120h (5 days) = the standard maximum blood culture incubation period.
  #   Observed ZIM max = 50h; this limit will not cut any current values.
  #
  # timespent: hours for the laboratory procedure or consultation.
  #   ZIM raw data shows 99% of values < 13.2h, then a sharp jump to 3069-21943h
  #   (clearly impossible for a procedure-level field). MWI max = 11.7h.
  #   Upper bound 72h (3 days) is generous and only removes the clearly impossible tail.
  #
  # episode: sequential episode counter per blood culture record.
  #   Raw data shows ZIM values up to 243 -- likely a row counter rather than a
  #   clinical episode count.  No upper bound is set (NA_real_ leaves
  #   suggested_plausible_max as NA so Module 11 enforces no upper limit).
  #   The lower bound of 1 removes any zero or negative values.
  bcreturntime     = c(0,         1440),
  poshours         = c(0,          120),
  timespent        = c(0,           72),
  episode          = c(1,     NA_real_)
)

# Explicit UUID overrides for specific country x dataset x question_key combinations.
#
# These are needed when two genuinely different clinical fields share the same
# question_key string (because to_db_name() strips both names to the same result)
# AND both appear in the same dataset's scripts, causing the publishDate-based
# dedup to select the wrong one.
#
# The canonical example: in MWI maternity scripts, both a birth-outcome field
# ("Birth Outcome" -> LB/SBF/SBM/UNK) and a neonatal discharge-outcome field
# ("Outcome" -> DC/NND<24/NND>24/TRH/...) produce question_key = "neotreeoutcome".
# The discharge-outcome UUID has a newer publishDate and would win the dedup,
# but the birth-outcome UUID is the correct one for any maternity dictionary.
#
# Only dhis2_maternal_outcomes and combined_maternity_outcomes need this override.
# The original maternal_outcomes script (retired Jan 2022) and maternity_completeness
# (paper-records backfill) never collected neotreeoutcome, so no override is needed.
#
# Format:  "COUNTRY:dataset_lc:question_key" = "full_UUID"
# country and dataset_lc must exactly match the values used in build_dictionary().
KEY_UUID_OVERRIDES <- list(
  "MWI:combined_maternity_outcomes:neotreeoutcome" = "9b361090-1b37-4056-b1a2-64908729b2d5",
  "MWI:dhis2_maternal_outcomes:neotreeoutcome"     = "9b361090-1b37-4056-b1a2-64908729b2d5"
)

# =============================================================================
# LEGACY VARIABLES
# =============================================================================
# Fields collected by early Neotree script versions that are absent from the
# current data-keys-metadata.json web-editor export.  These variables appear
# in raw PostgreSQL exports but would not receive a dictionary row from the
# JSON-driven build, causing Module 09 to skip them entirely (leaving "None"
# strings uncleaned and no numeric coercion).
#
# Each list entry defines:
#   country         - uppercase country code ("ZIM" or "MWI")
#   datasets        - character vector of dataset_lc values to inject into
#   question_key    - lowercase field key (no spaces or special characters)
#   label           - human-readable variable label
#   data_type       - raw_data_type (web-editor convention, e.g. "number")
#   r_type          - pipeline r_type ("numeric", "boolean", etc.)
#   weight_unit     - "grams" if a weight field; NA_character_ otherwise
#   use_in_analysis - TRUE / FALSE
#   plausible_min   - suggested_plausible_min (NA_real_ for no lower bound)
#   plausible_max   - suggested_plausible_max (NA_real_ for no upper bound)
#   note            - cleaning_note stored in the Variables sheet
#
# Entries are injected after the JSON-driven Variables sheet is built and
# before user_ranges.xlsx is applied, so user_ranges can still override the
# suggested ranges.  An entry is silently skipped if the question_key is
# already present in the Variables sheet (preventing double-registration if
# the field is reinstated in a future web-editor export).
#
# To add a new legacy field: append a new list() entry below and re-run the
# build script.  No changes to any other file are required.
# =============================================================================

LEGACY_VARIABLES <- list(

  # aw -- Admission Weight (g)
  # Collected by pre-v5 ZIM admission scripts.  Replaced in current scripts
  # by admissionweight, but still present in records from the earlier era.
  # "None" artefact fix: adding this entry ensures Module 09 processes the
  # column and coerces "None" strings to NA.  (2026-05-15)
  list(
    country         = "ZIM",
    datasets        = c("admissions"),
    question_key    = "aw",
    label           = "Admission Weight (g) (if different from birth weight)",
    data_type       = "number",
    r_type          = "numeric",
    weight_unit     = "grams",
    use_in_analysis = TRUE,
    plausible_min   = 300,
    plausible_max   = 7000,
    note = paste0(
      "Legacy field from pre-v5 Neotree ZIM admission scripts. ",
      "Absent from current data-keys-metadata.json. ",
      "Registered in LEGACY_VARIABLES 2026-05-15 to ensure Module 09 ",
      "coerces 'None' strings to NA and validates numeric range."
    )
  ),

  # bsmmol -- Blood Sugar (mmol/L)
  # Older equivalent of bloodsugarmmol; collected by pre-v5 ZIM scripts.
  # Same "None" artefact issue as aw.  (2026-05-15)
  list(
    country         = "ZIM",
    datasets        = c("admissions"),
    question_key    = "bsmmol",
    label           = "Blood Sugar (mmol/L)",
    data_type       = "number",
    r_type          = "numeric",
    weight_unit     = NA_character_,
    use_in_analysis = TRUE,
    plausible_min   = NA_real_,
    plausible_max   = 40,
    note = paste0(
      "Legacy field from pre-v5 Neotree ZIM admission scripts; ",
      "older equivalent of bloodsugarmmol. ",
      "Absent from current data-keys-metadata.json. ",
      "Registered in LEGACY_VARIABLES 2026-05-15 to ensure Module 09 ",
      "coerces 'None' strings to NA and validates numeric range."
    )
  ),

  # hivtestresult -- HIV Test Result
  # Present in ZIM raw admissions data but absent from the ZIM admissions
  # dictionary (it was not linked to ZIM admission scripts in the web-editor).
  # Without a Variables row the field passes through build_non_validated in
  # Module 15 without any value cleaning (Module 04 only processes typed keys).
  # Adding it here gives it a categorical Variables row and allows the
  # VALUEMAP_PATCHES below to supply canonical code mappings.  (2026-05)
  list(
    country         = "ZIM",
    datasets        = c("admissions"),
    question_key    = "hivtestresult",
    label           = "HIV Test Result",
    data_type       = "option",
    r_type          = "categorical",
    weight_unit     = NA_character_,
    use_in_analysis = TRUE,
    plausible_min   = NA_real_,
    plausible_max   = NA_real_,
    note = paste0(
      "Absent from ZIM admissions dictionary despite being present in raw data. ",
      "Injected via LEGACY_VARIABLES 2026-05 so Module 04 applies value cleaning. ",
      "ValueMaps (R/Positive->R, NR/Negative->NR, U/Unknown->U) added via VALUEMAP_PATCHES."
    )
  )

)

# =============================================================================
# DERIVED VARIABLES (computed by the cleaning pipeline; not present in raw data)
# =============================================================================
# These columns are CREATED by Module 15 (derive_weight_columns) AFTER all
# validation modules have run.  They have no raw .value / .label column and are
# never processed by Modules 04 / 09 / 11.  They are registered here purely so
# they are documented in the per-table dictionaries and flow into the
# researcher-facing user dictionary (00d).
#
# Documentation-only by construction: raw_value_column is NA for these rows, so
# 00_setup.r EXCLUDES them from the cleaning feature lists (cfg$num etc. require
# a non-NA raw_value_column).  weight_unit = "grams" documents the unit; Module
# 11's kg->g loop only touches columns that exist at that stage, so a derived
# entry is a no-op there.
#
# Concept mapping (see readme.md "Weight variables"):
#   birthweight_g      coalesce(birthweight, bwt, bwtdis)  -- emitted in EVERY dataset
#   admission_weight_g admissionweight                     -- admission-type forms
#   discharge_weight_g dischweight                          -- discharge-type forms
#
# Each entry mirrors the LEGACY_VARIABLES schema (country / datasets /
# question_key / label / r_type / weight_unit / use_in_analysis /
# plausible_min / plausible_max / note).  Injection is skipped if the
# question_key is already present in the Variables sheet.
# =============================================================================

DERIVED_VARIABLES <- list(

  # birthweight_g -- canonical birth weight (every dataset, both countries)
  list(
    country = "MWI",
    datasets = c("admissions", "discharges", "maternal_outcomes",
                 "combined_maternity_outcomes", "dhis2_maternal_outcomes",
                 "maternity_completeness", "phc_admissions", "phc_discharges",
                 "joined_admissions_discharges", "neolab"),
    question_key = "birthweight_g",
    label = "Birth weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical birth weight (grams). Cleaning pipeline Module 15 ",
      "computes coalesce(birthweight, bwt, bwtdis) -- three names for the same ",
      "concept across Neotree form/script versions (bwtdis is birth weight ",
      "despite its name; sources are identical where they overlap). Emitted in ",
      "every dataset (NA where no source column is present). Originals retained. ",
      "Use this column for low-birth-weight analysis. Not a raw field; no .value column.")
  ),
  list(
    country = "ZIM",
    datasets = c("admissions", "discharges", "maternal_outcomes",
                 "phc_admissions", "phc_discharges",
                 "joined_admissions_discharges", "neolab",
                 "baseline", "infections", "twenty_8_day_follow_up"),
    question_key = "birthweight_g",
    label = "Birth weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical birth weight (grams). Cleaning pipeline Module 15 ",
      "computes coalesce(birthweight, bwt, bwtdis) -- three names for the same ",
      "concept across Neotree form/script versions (bwtdis is birth weight ",
      "despite its name; sources are identical where they overlap). Emitted in ",
      "every dataset (NA where no source column is present). Originals retained. ",
      "Use this column for low-birth-weight analysis. Not a raw field; no .value column.")
  ),

  # admission_weight_g -- canonical admission weight (admission-type forms)
  list(
    country = "MWI",
    datasets = c("admissions", "phc_admissions", "joined_admissions_discharges"),
    question_key = "admission_weight_g",
    label = "Admission weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical admission weight (grams) = admissionweight. Distinct ",
      "concept from birth weight (weight at neonatal admission); never folded ",
      "into birth weight. Cleaning pipeline Module 15. Not a raw field; no .value column.")
  ),
  list(
    country = "ZIM",
    datasets = c("admissions", "phc_admissions", "baseline",
                 "joined_admissions_discharges"),
    question_key = "admission_weight_g",
    label = "Admission weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical admission weight (grams) = admissionweight. Distinct ",
      "concept from birth weight (weight at neonatal admission); never folded ",
      "into birth weight. Cleaning pipeline Module 15. Not a raw field; no .value column.")
  ),

  # discharge_weight_g -- canonical discharge / last-recorded weight (discharge forms)
  list(
    country = "MWI",
    datasets = c("discharges", "phc_discharges", "joined_admissions_discharges"),
    question_key = "discharge_weight_g",
    label = "Discharge / last-recorded weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical discharge / last-recorded weight (grams) = dischweight ",
      "(date in datedischweight). Distinct concept from birth weight; never ",
      "folded into it. Cleaning pipeline Module 15. Not a raw field; no .value column.")
  ),
  list(
    country = "ZIM",
    datasets = c("discharges", "phc_discharges", "joined_admissions_discharges",
                 "baseline"),
    question_key = "discharge_weight_g",
    label = "Discharge / last-recorded weight (g) -- canonical (derived)",
    r_type = "numeric", weight_unit = "grams", use_in_analysis = TRUE,
    plausible_min = 300, plausible_max = 7000,
    note = paste0(
      "Derived canonical discharge / last-recorded weight (grams) = dischweight ",
      "(date in datedischweight). Distinct concept from birth weight; never ",
      "folded into it. Cleaning pipeline Module 15. Not a raw field; no .value column.")
  )

)

# =============================================================================
# POST-BUILD PATCHES
# =============================================================================
# Applied inside build_dictionary() after the main Variables and ValueMaps
# sheets are assembled but before the workbook is written.  Use these to
# correct cases where the web-editor export data does not match the desired
# pipeline behaviour:
#   VARIABLE_PATCHES   -- column-level corrections to the Variables sheet
#   VALUEMAP_PATCHES   -- add rows, update canonical codes, or remove
#                         duplicate rows in the ValueMaps sheet
#
# To add a new patch: append a list() entry and re-run this script.
# Each entry is silently skipped when the target question_key is not present
# in the relevant sheet (safe to run against older export snapshots).
# =============================================================================

# -- VARIABLE_PATCHES ----------------------------------------------------------
# Each entry: country, datasets (vector), question_key, changes (named list).
# 'changes' maps column names to new values; NA_character_ clears a column.
#
# Documented changes (newest first):
#
#   2026-05  MWI adm+dis  hivtestresult, hivtestresultdc, datehivtest,
#                         haart, lengthhaart, mathivstat
#              -> confidential FALSE  (clinical-outcome fields incorrectly
#                 flagged as direct_identifier in MWI web-editor JSON)
#
#   2026-05  MWI adm+dis  mathivtest, birthplacesame  -> r_type categorical
#            MWI adm      dysmorphic, feversr, ortolani -> r_type categorical
#            MWI dis      inorout, phototherapy         -> r_type categorical
#              -> boolean fields that ZIM classifies as categorical; keeping
#                 r_type categorical gives character Y/N/U output in both sites

VARIABLE_PATCHES <- list(

  # -- PII misclassification corrections ----------------------------------------
  # Clinical-outcome HIV-related fields incorrectly flagged confidential=TRUE in
  # the MWI web-editor JSON.  Module 00a drops every confidential=TRUE column
  # before any cleaning; these corrections prevent that drop.

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "hivtestresult",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  list(country = "MWI", datasets = c("discharges"),
       question_key = "hivtestresultdc",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "datehivtest",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "haart",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "lengthhaart",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "mathivstat",
       changes = list(confidential = FALSE,
                      pii_tier     = NA_character_,
                      pii_category = NA_character_)),

  # -- r_type reclassifications: boolean -> categorical -------------------------
  # These fields use the yesno web-editor dataType which PIPELINE_TYPE_MAP
  # maps to "boolean".  ZIM dictionaries classify them as "categorical".
  # Module 12 (boolean) outputs TRUE/FALSE; Module 13 (categorical) outputs
  # Y/N/U character codes.  Reclassifying to categorical makes both sites
  # produce the same output format so joined data can be pooled.

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "mathivtest",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "birthplacesame",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "dysmorphic",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "feversr",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "ortolani",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("discharges"),
       question_key = "inorout",
       changes = list(r_type = "categorical")),

  list(country = "MWI", datasets = c("discharges"),
       question_key = "phototherapy",
       changes = list(r_type = "categorical"))
)

# -- VALUEMAP_PATCHES ----------------------------------------------------------
# Each entry: country, datasets (vector), question_key, action, ...
#
# action = "add_rows"
#   rows: data.frame with columns raw_code, option_label, canonical_code.
#   Rows are added only if option_label is not already present (idempotent).
#
# action = "update_canonical"
#   updates: named list of raw_code = new_canonical_code.
#   Updates existing rows; skips silently if raw_code not found.
#
# action = "remove_duplicate_raw_code"
#   raw_code:    the duplicated code
#   keep_label:  the option_label to retain; all other rows with this
#                raw_code are removed.
#
# Documented changes (newest first):
#
#   2026-07  Clinical-decision layer (clinical-team confirmations + 2024 public dictionary):
#            legacy categorical values mapped to current canonical codes for
#            inorout, modedelivery('1'), admittedfrom(ER=External Referral),
#            vomiting, murmur, punewborn, matsymptoms, matcomorbidities,
#            receivedantenatalcare, cadredis, admreason, admreasonadd, diagdis1.
#            See the dated block lower in this list and the follow-up file.
#
#   2026-05  ZIM dis   mecpresent canonical: N->No, U->UNK, Y->Yes
#            ZIM dis   mecthickthin canonical: U->UNK
#              -> aligns ZIM discharges with all other dicts
#
#   2026-05  MWI adm+dis  lengthhaart 3rdTrim duplicate removed
#              -> only "3rd Trimester more than 1 month before delivery" kept
#
#   2026-05  ZIM adm   hivtestresult ValueMaps added (R/NR/U)
#   2026-05  MWI adm+dis mathivtest, birthplacesame ValueMaps added (Y/N/U)
#   2026-05  MWI adm   dysmorphic, feversr, ortolani ValueMaps added (Y/N)
#   2026-05  MWI dis   inorout ValueMaps added (In/Out)
#   2026-05  MWI dis   phototherapy ValueMaps added (Y/N)

VALUEMAP_PATCHES <- list(

  # -- New ValueMaps rows -------------------------------------------------------

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "mathivtest", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N",  "U"),
         option_label   = c("Yes", "No", "Unknown"),
         canonical_code = c("Y",   "N",  "U"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "birthplacesame", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N",  "U"),
         option_label   = c("Yes", "No", "Unknown"),
         canonical_code = c("Y",   "N",  "U"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "dysmorphic", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N"),
         option_label   = c("Yes", "No"),
         canonical_code = c("Y",   "N"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "feversr", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N"),
         option_label   = c("Yes", "No"),
         canonical_code = c("Y",   "N"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("admissions"),
       question_key = "ortolani", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N"),
         option_label   = c("Yes", "No"),
         canonical_code = c("Y",   "N"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("discharges"),
       question_key = "inorout", action = "add_rows",
       rows = data.frame(
         raw_code       = c("In",          "Out"),
         option_label   = c("Within PHC",  "Outside PHC"),
         canonical_code = c("In",          "Out"),
         stringsAsFactors = FALSE
       )),

  list(country = "MWI", datasets = c("discharges"),
       question_key = "phototherapy", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "N"),
         option_label   = c("Yes", "No"),
         canonical_code = c("Y",   "N"),
         stringsAsFactors = FALSE
       )),

  # ZIM admissions: hivtestresult ValueMaps (field injected via LEGACY_VARIABLES).
  # ZIM raw values use long labels "Positive"/"Negative"; canonical codes R/NR/U
  # align with MWI and with the short-code values already present in raw data.
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "hivtestresult", action = "add_rows",
       rows = data.frame(
         raw_code       = c("R",        "NR",       "U"),
         option_label   = c("Positive", "Negative", "Unknown"),
         canonical_code = c("R",        "NR",       "U"),
         stringsAsFactors = FALSE
       )),

  # -- Canonical code corrections -----------------------------------------------

  # ZIM discharges mecpresent: canonical codes Y/N/U -> Yes/No/UNK to match all
  # other dictionaries and allow cross-site pooling.
  list(country = "ZIM", datasets = c("discharges"),
       question_key = "mecpresent", action = "update_canonical",
       updates = list("N" = "No", "U" = "UNK", "Y" = "Yes")),

  # ZIM discharges mecthickthin: canonical U -> UNK to match all other dicts.
  list(country = "ZIM", datasets = c("discharges"),
       question_key = "mecthickthin", action = "update_canonical",
       updates = list("U" = "UNK")),

  # -- Duplicate row removal ----------------------------------------------------

  # MWI: lengthhaart has 3rdTrim appearing twice (web-editor had two options
  # with the same code).  The shorter label "3rd Trimester" is the duplicate;
  # retain the more descriptive "3rd Trimester more than 1 month before delivery".
  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "lengthhaart", action = "remove_duplicate_raw_code",
       raw_code   = "3rdTrim",
       keep_label = "3rd Trimester more than 1 month before delivery"),

  # ===========================================================================
  # 2026-07-17  CLINICAL-DECISION LAYER (clinical-team confirmations + 2024
  #             public data dictionary).  Legacy categorical values from older
  #             Neotree form versions mapped to the CURRENT canonical code for
  #             each field.  Every target below was verified to already exist in
  #             that field's current ValueMaps (adding an alias raw_code, never a
  #             new canonical option).  Values with NO current target, or that
  #             remain clinically ambiguous, are LEFT UNTOUCHED (decision-free)
  #             and tracked as open clinical follow-ups.
  #             Sources: clinical-team decision sheet;
  #             Public_data_dictionary_2024.xlsx (confirms ER=External Referral,
  #             G=Gastroschisis, OM=Omphalocele).
  # ===========================================================================

  # -- Section 1: coding-scheme / direction -----------------------------------

  # inorout: older forms recorded Yes/No (true/false); current form uses In/Out.
  # Clinically confirmed: legacy TRUE/Yes = Inborn (In); legacy False/No = Outborn
  # (Out).  The decision-free boolean rule does NOT fire here because the field's
  # canonical set is {In,Out}, not {Y,N,U} -- so explicit aliases are required.
  list(country = "ZIM", datasets = c("admissions", "discharges"),
       question_key = "inorout", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Yes",              "true",             "No",                 "false"),
         option_label   = c("Inborn (legacy Yes)", "Inborn (legacy true)", "Outborn (legacy No)", "Outborn (legacy false)"),
         canonical_code = c("In",               "In",               "Out",                "Out"),
         stringsAsFactors = FALSE
       )),
  list(country = "MWI",
       datasets = c("admissions", "discharges", "phc_admissions", "phc_discharges"),
       question_key = "inorout", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Yes",              "true",             "No",                 "false"),
         option_label   = c("Inborn (legacy Yes)", "Inborn (legacy true)", "Outborn (legacy No)", "Outborn (legacy false)"),
         canonical_code = c("In",               "In",               "Out",                "Out"),
         stringsAsFactors = FALSE
       )),

  # modedelivery: clinically confirmed numeric 1-7 = old data-dictionary scheme
  # (1=SVD, 2=Vacuum, 3=Forceps, 4=Elective CS, 5=Emergency CS, 6=Breech,
  # 7=Induced Vaginal Delivery).  Text labels are already recoded to numeric by
  # harmonise_modedelivery() in Module 04.  Only "1" (=SVD) was missing from the
  # canonical set; registering it here so it is recognised, not flagged.  ("7"
  # was added to the form later, so it is absent from older datasets.)
  list(country = "ZIM",
       datasets = c("admissions", "discharges", "baseline", "maternal_outcomes"),
       question_key = "modedelivery", action = "add_rows",
       rows = data.frame(
         raw_code       = "1",
         option_label   = "Spontaneous Vaginal Delivery (SVD)",
         canonical_code = "1",
         stringsAsFactors = FALSE
       )),

  # -- Section 2: unknown admission source ------------------------------------

  # admittedfrom: 'ER' is NOT A&E/Casualty.  The 2024 public data dictionary
  # (Admission sheet) defines ER = "External Referral" as its own option.  Keep
  # ER as a distinct canonical source rather than collapsing into AE/Cas.
  list(country = "ZIM", datasets = c("admissions", "discharges"),
       question_key = "admittedfrom", action = "add_rows",
       rows = data.frame(
         raw_code       = "ER",
         option_label   = "External Referral",
         canonical_code = "ER",
         stringsAsFactors = FALSE
       )),
  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "admittedfrom", action = "add_rows",
       rows = data.frame(
         raw_code       = "ER",
         option_label   = "External Referral",
         canonical_code = "ER",
         stringsAsFactors = FALSE
       )),

  # -- Section 3: legacy Yes/No on fields now using coded scales ---------------

  # vomiting: legacy "No" = no vomiting = Norm (NONE).  "Yes" is left untouched
  # because it is already a canonical code (= "Vomiting all feeds").
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "vomiting", action = "add_rows",
       rows = data.frame(
         raw_code       = "No", option_label = "No vomiting (legacy No)",
         canonical_code = "Norm", stringsAsFactors = FALSE
       )),
  list(country = "MWI", datasets = c("admissions", "phc_admissions"),
       question_key = "vomiting", action = "add_rows",
       rows = data.frame(
         raw_code       = "No", option_label = "No vomiting (legacy No)",
         canonical_code = "Norm", stringsAsFactors = FALSE
       )),

  # murmur: legacy "No" = no added murmur/sounds = NormHSounds.
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "murmur", action = "add_rows",
       rows = data.frame(
         raw_code       = "No", option_label = "No added murmur/sounds (legacy No)",
         canonical_code = "NormHSounds", stringsAsFactors = FALSE
       )),

  # punewborn: legacy Yes = passed urine (YesUr); No = not passed urine (NoUr).
  # ("Not sure" already resolves to Unk via its option label.)
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "punewborn", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Yes",   "No"),
         option_label   = c("Passed urine (legacy Yes)", "Not passed urine (legacy No)"),
         canonical_code = c("YesUr", "NoUr"),
         stringsAsFactors = FALSE
       )),

  # matsymptoms: N = None (Norm); O = Other (Oth).  ASSUMPTION (clinical team) --
  # flagged for Tim to confirm against old data dictionaries (follow-up file).
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "matsymptoms", action = "add_rows",
       rows = data.frame(
         raw_code       = c("N",    "O"),
         option_label   = c("None (legacy N)", "Other (legacy O)"),
         canonical_code = c("Norm", "Oth"),
         stringsAsFactors = FALSE
       )),

  # matcomorbidities: N = None (Norm); O = Other (Oth).  ASSUMPTION (clinical team) --
  # flagged for Tim to confirm (follow-up file).
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "matcomorbidities", action = "add_rows",
       rows = data.frame(
         raw_code       = c("N",    "O"),
         option_label   = c("None (legacy N)", "Other (legacy O)"),
         canonical_code = c("Norm", "Oth"),
         stringsAsFactors = FALSE
       )),

  # receivedantenatalcare (Pregnancy Booking Status): Y/Yes = Booked (Bkd);
  # N/No = Unbooked (Ubkd).  Clinically confirmed.
  list(country = "ZIM", datasets = c("admissions", "baseline"),
       question_key = "receivedantenatalcare", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "Yes", "N",    "No"),
         option_label   = c("Booked (legacy Y)", "Booked (legacy Yes)", "Unbooked (legacy N)", "Unbooked (legacy No)"),
         canonical_code = c("Bkd", "Bkd", "Ubkd", "Ubkd"),
         stringsAsFactors = FALSE
       )),

  # cadredis (Type of Health Care Worker): 'NO' / 'NO - Nursing Officer' is a
  # registered nurse = N (Nurse).  Clinically confirmed.
  list(country = "MWI", datasets = c("discharges"),
       question_key = "cadredis", action = "add_rows",
       rows = data.frame(
         raw_code       = c("NO",             "NO - Nursing Officer"),
         option_label   = c("Nursing Officer (legacy NO)", "Nursing Officer (legacy long form)"),
         canonical_code = c("N",              "N"),
         stringsAsFactors = FALSE
       )),

  # -- Section 4: legacy diagnosis / admission-reason codes --------------------
  # Clinically confirmed mappings, each bound to a code that already exists in the
  # field's CURRENT canonical set.  Multi-diagnosis legacy tokens map to a brace
  # multi-select of current codes (e.g. PremRDS -> {Prem,DIB}).  Codes with no
  # current target (admreason Safe/Safekeeping/Hyperth/HIVLR; admreasonadd
  # Mec/Cong; diagdis1 HBW/JAUN) are NOT mapped here -- see follow-up file.

  # admreason (ZIM "Differential Diagnoses"; present in admissions + discharges)
  list(country = "ZIM", datasets = c("admissions", "discharges"),
       question_key = "admreason", action = "add_rows",
       rows = data.frame(
         raw_code = c(
           "O", "BA", "LowBirthWeight", "Low Birth Weight (1500-2499g)", "HBW",
           "FD", "TTN", "MA", "sHIE", "G", "VLBW", "GSch", "SEPS", "ExLBW",
           "Difficulty in breathing", "VPrem", "OM", "ExPrem", "Prematurity",
           "Mec", "TermRD", "Term with RD",
           "PremRDS", "PremRD", "Prematurity with RDS", "Prematurity with RD"),
         option_label = c(
           "Other (legacy O)", "Birth asphyxia / HIE (legacy BA)",
           "Low birth weight (legacy)", "Low birth weight 1500-2499g (legacy)",
           "High birth weight / macrosomia (legacy HBW)",
           "Feeding difficulty (legacy FD)",
           "Transient tachypnoea -> respiratory distress (legacy TTN)",
           "Meconium aspiration (legacy MA)", "Suspected HIE (legacy sHIE)",
           "Gastroschisis (legacy G)", "Very low birth weight -> LBW (legacy)",
           "Gastroschisis (legacy GSch)", "Sepsis suspected (legacy SEPS)",
           "Extremely low birth weight -> LBW (legacy)",
           "Respiratory distress (legacy free-text)",
           "Very premature -> Prem (legacy)", "Omphalocele (legacy OM)",
           "Extremely premature -> Prem (legacy)", "Prematurity (legacy free-text)",
           "Meconium exposure (legacy Mec)",
           "Term with respiratory distress -> DIB (legacy TermRD)",
           "Term with respiratory distress (legacy free-text)",
           "Premature with respiratory distress (legacy PremRDS)",
           "Premature with respiratory distress (legacy PremRD)",
           "Premature with respiratory distress (legacy free-text)",
           "Premature with respiratory distress (legacy free-text)"),
         canonical_code = c(
           "Oth", "HIE", "LBW", "LBW", "Mac",
           "DF", "DIB", "PMA", "HIE", "GSchis", "LBW", "GSchis", "NSep", "LBW",
           "DIB", "Prem", "Omph", "Prem", "Prem",
           "MecEx", "DIB", "DIB",
           "{Prem,DIB}", "{Prem,DIB}", "{Prem,DIB}", "{Prem,DIB}"),
         stringsAsFactors = FALSE
       )),

  # admreasonadd (ZIM "Additional Reasons for admission"; admissions).
  # RDS/FD/G map to current codes; brace-sets containing RDS auto-resolve once
  # RDS -> DIB is known (all other tokens are already canonical).  Mec and Cong
  # have no admreasonadd target and are left untouched (follow-up file).
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "admreasonadd", action = "add_rows",
       rows = data.frame(
         raw_code       = c("RDS", "FD", "G"),
         option_label   = c("Respiratory distress (legacy RDS)",
                            "Difficulty feeding (legacy FD)",
                            "Gastroschisis (legacy G)"),
         canonical_code = c("DIB", "DF", "GSchis"),
         stringsAsFactors = FALSE
       )),

  # diagdis1 (ZIM "Primary discharge diagnosis"; discharges + baseline).
  # HBW (no Mac option) and JAUN (physiological vs pathological unresolved) are
  # left untouched (follow-up file).
  list(country = "ZIM", datasets = c("discharges", "baseline"),
       question_key = "diagdis1", action = "add_rows",
       rows = data.frame(
         raw_code       = c("PR",   "BA",  "PRRDS",  "FD", "HIVXL",  "Ri",   "OCA",  "BI"),
         option_label   = c("Prematurity (legacy PR)", "Birth asphyxia / HIE (legacy BA)",
                            "Premature with respiratory distress (legacy PRRDS)",
                            "Feeding difficulty (legacy FD)",
                            "HIV exposed low risk (legacy HIVXL)",
                            "Sepsis risk factors (legacy Ri)",
                            "Other congenital abnormality (legacy OCA)",
                            "Birth injury / trauma (legacy BI)"),
         canonical_code = c("Prem", "HIE", "PremRD", "DF", "HIVLR", "Risk", "Cong", "BT"),
         stringsAsFactors = FALSE
       ))
)

# =============================================================================
# PII PATTERN DEFINITIONS (Tier 2)
# =============================================================================
# These patterns identify PII fields by column-name matching.
# They are the single source of truth for Tier 2 removal:
#   - Embedded in each dictionary workbook as the PII_Patterns sheet
#   - Read by Module 00a at runtime (replacing hardcoded constants)
#   - Matched against normalised column names (lowercase, no whitespace/underscores)
#
# To add a new pattern: add a row here and re-run this script.
# QUASI_ID_PATTERNS are flagged in the audit report but NOT removed.

PII_PATTERNS_DATA <- tibble::tribble(
  ~pattern,            ~pattern_type,  ~pii_category,   ~reason,
  ~countries,          ~examples,
  ~added_date,         ~notes,

  "name\\.value$",     "suffix_match", "personal_name",
    "Personal names (baby, mother, next of kin)",
    "MWI, ZIM",
    "babyfirstname.value, mothersurname.value, kinname.value",
    "2025-06-01",  NA_character_,

  "cell\\.value$",     "suffix_match", "phone_number",
    "Mobile/cell phone numbers",
    "MWI",
    "mothcell.value",
    "2025-06-01",  NA_character_,

  "phone\\.value$",    "suffix_match", "phone_number",
    "Landline phone number fields",
    "ZIM",
    "(various phone fields)",
    "2025-06-01",  NA_character_,

  "address\\.value$",  "suffix_match", "address",
    "Physical address fields",
    "ZIM",
    "matphysaddressdistrict.value",
    "2025-06-01",  NA_character_,

  "hcwid",             "contains",     "identifier",
    "Healthcare worker IDs at admission and discharge",
    "MWI, ZIM",
    "hcwid.value, hcwid.label, hcwiddis.value",
    "2025-06-01",  NA_character_,

  "hospnum",           "contains",     "identifier",
    "Hospital patient numbers",
    "ZIM",
    "mathospnum.value, babyhospnum.value",
    "2025-06-01",  NA_character_,

  "neotreeid",         "contains",     "identifier",
    "Internal Neotree patient identifier",
    "MWI, ZIM",
    "neotreeid.value",
    "2025-06-01",  NA_character_,

  "stuid",             "contains",     "identifier",
    "Student/study healthcare worker ID",
    "MWI",
    "stuid.value, stuid.label",
    "2025-06-01",  "Extended 2025-09-15 from stuid\\.value$ to catch .label variants",

  "uidbid\\.value$",   "suffix_match", "identifier",
    "Baby unique identifier",
    "MWI, ZIM",
    "uidbid.value",
    "2025-06-01",  NA_character_,

  "uiddc\\.value$",    "suffix_match", "identifier",
    "Discharge unique identifier",
    "MWI, ZIM",
    "uiddc.value",
    "2025-06-01",  NA_character_,

  "drid\\.value$",     "suffix_match", "identifier",
    "DR / practitioner identifier",
    "MWI, ZIM",
    "drid.value",
    "2025-06-01",  NA_character_
)

# Quasi-identifiers: flagged in audit report but NOT automatically removed.
# These have legitimate analytical uses but could contribute to re-identification.
# Reflected as pii_tier = 'quasi' in the Variables sheet.
QUASI_ID_PATTERNS <- c(
  "village", "district", "province",
  "tribe\\.value$", "ethnicity\\.value$", "religion\\.value$",
  "address"
)

# =============================================================================
# HELPERS
# =============================================================================

# Normalise a key name to a database-safe lowercase identifier
to_db_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  gsub("[^a-z0-9]", "", x)
}

# Convert CamelCase key name to snake_case harmonised variable name
to_harmonised <- function(x) {
  x <- gsub("([a-z0-9])([A-Z])", "\\1_\\2", as.character(x))
  x <- tolower(trimws(x))
  x <- gsub("[^a-z0-9_]", "_", x)
  x <- gsub("_+", "_", x)
  gsub("(^_|_$)", "", x)
}

# =============================================================================
# DATA LOADING
# =============================================================================

#' Load the metadata JSON and usage XLSX for one country
#'
#' @param country  "ZIM" or "MWI"
#' @return list(metadata = data.frame, usage = data.frame, opt_lookup = data.frame)
load_country_keys <- function(country) {
  country <- toupper(country)
  folder  <- COUNTRY_FOLDERS[[country]]
  if (is.null(folder))
    stop(sprintf("Unknown country '%s'. Add it to COUNTRY_FOLDERS.", country))

  md_path <- file.path(DOWNLOADED_KEYS_BASE, folder, "data-keys-metadata.json")
  us_path <- file.path(DOWNLOADED_KEYS_BASE, folder, "data-keys-usage.xlsx")

  if (!file.exists(md_path))
    stop(sprintf("Metadata JSON not found:\n  %s", md_path))
  if (!file.exists(us_path))
    stop(sprintf("Usage XLSX not found:\n  %s", us_path))

  # -- Metadata ----------------------------------------------------------------
  # fromJSON returns a data.frame with options as a list-column of character vectors
  md_raw <- fromJSON(md_path, simplifyDataFrame = TRUE)

  # Ensure options is always a list-column (it should be, but be defensive)
  if (!is.list(md_raw$options))
    md_raw$options <- as.list(md_raw$options)

  # Build option lookup: uniqueKey -> (name=raw_code, label=option_label)
  # trimws() is applied to both raw_code and option_label so that leading/trailing
  # whitespace in the web-editor export (e.g. " Stillbirth Mascerated") does not
  # prevent matching in Module 04's lbl_to_code lookup.
  opt_lookup <- md_raw %>%
    filter(dataType == "option", !isDeleted) %>%
    transmute(
      option_uuid  = uniqueKey,
      raw_code     = trimws(name),
      option_label = trimws(label)
    ) %>%
    distinct(option_uuid, .keep_all = TRUE)

  # -- Usage --------------------------------------------------------------------
  usage_raw <- readxl::read_excel(us_path)
  # Normalise column names: lowercase, strip all non-alphanumeric characters.
  # This is version-independent and replicates the behaviour the code expects:
  #   DataKeyUniqueKey -> datakeyuniquekey
  #   ScriptTitle      -> scripttitle
  #   Confidential     -> confidential
  # (janitor::clean_names() v2.x produces snake_case with underscores instead,
  #  which breaks downstream column references.)
  names(usage_raw) <- tolower(gsub("[^a-zA-Z0-9]", "", names(usage_raw)))

  list(metadata = md_raw, usage = usage_raw, opt_lookup = opt_lookup)
}

# =============================================================================
# MAIN FUNCTION: build_dictionary
# =============================================================================

#' Build one dictionary workbook for a country x dataset combination.
#'
#' @param country        "ZIM" or "MWI"
#' @param dataset        One of the DATASET_FILTERS keys (e.g. "admissions",
#'                       "discharges", "maternal_outcomes", "phc_admissions",
#'                       "phc_discharges", "combined_maternity_outcomes")
#' @param out_path       Full path for the output xlsx  (NULL = auto-named)
#' @param include_review Include the ReviewNeeded sheet (default TRUE)
#' @param keys           Pre-loaded country keys (NULL = load from disk)
#'
#' @return Invisibly: list(variables, value_maps, review_needed)
build_dictionary <- function(country         = "ZIM",
                             dataset         = "admissions",
                             out_path        = NULL,
                             include_review  = TRUE,
                             keys            = NULL) {

  country_up <- toupper(trimws(country))
  dataset_lc <- tolower(trimws(dataset))
  env_label  <- switch(country_up, ZIM = "Zimbabwe", MWI = "Malawi", country_up)

  dataset_regex <- DATASET_FILTERS[[dataset_lc]]
  if (is.null(dataset_regex))
    stop(sprintf("Unknown dataset '%s'. Choose: %s",
                 dataset_lc, paste(names(DATASET_FILTERS), collapse = ", ")))

  log_info("Building dictionary: %s x %s", country_up, dataset_lc)

  # -- Load keys (or reuse pre-loaded) -----------------------------------------
  if (is.null(keys)) keys <- load_country_keys(country_up)
  md_raw     <- keys$metadata
  usage_raw  <- keys$usage
  opt_lookup <- keys$opt_lookup

  # -- Filter usage to target dataset scripts -----------------------------------
  target_usage <- usage_raw %>%
    filter(str_detect(scripttitle, regex(dataset_regex, ignore_case = TRUE)))

  target_uuids <- unique(target_usage$datakeyuniquekey)

  if (length(target_uuids) == 0)
    stop(sprintf("No usage entries found for %s x %s (regex='%s')",
                 country_up, dataset_lc, dataset_regex))

  # Section label per key (semicolon-separated script titles)
  section_map <- target_usage %>%
    group_by(datakeyuniquekey) %>%
    summarise(section = paste(sort(unique(scripttitle)), collapse = "; "),
              .groups = "drop")

  # -- Filter metadata to target keys -------------------------------------------
  md_f <- md_raw %>%
    filter(
      !isDeleted,
      dataType != "option",          # options are values, not variables
      uniqueKey %in% target_uuids
    ) %>%
    left_join(section_map, by = c("uniqueKey" = "datakeyuniquekey"))

  if (nrow(md_f) == 0)
    stop(sprintf("No variables matched after filtering for %s x %s",
                 country_up, dataset_lc))

  # -- Deduplicate: one row per question_key (most recent publish date wins) ----
  vars_dedup <- md_f %>%
    mutate(question_key = to_db_name(name)) %>%
    filter(question_key != "") %>%
    group_by(question_key) %>%
    arrange(desc(publishDate), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup()

  log_info("  %d unique keys after dedup (from %d metadata rows)",
           nrow(vars_dedup), nrow(md_f))

  # -- Apply KEY_UUID_OVERRIDES --------------------------------------------------
  # For entries listed in KEY_UUID_OVERRIDES, replace the publishDate-selected row
  # with the explicitly specified UUID.  Only fires when country + dataset match.
  for (override_id in names(KEY_UUID_OVERRIDES)) {
    parts   <- strsplit(override_id, ":")[[1]]
    ov_ctry <- parts[1]
    ov_dset <- parts[2]
    ov_qkey <- parts[3]
    ov_uuid <- KEY_UUID_OVERRIDES[[override_id]]

    if (!identical(country_up, ov_ctry) || !identical(dataset_lc, ov_dset)) next

    override_row <- md_f %>%
      mutate(question_key = to_db_name(name)) %>%
      filter(uniqueKey == ov_uuid, question_key == ov_qkey)

    if (nrow(override_row) > 0) {
      vars_dedup <- vars_dedup %>%
        filter(question_key != ov_qkey) %>%
        bind_rows(override_row %>%
                    mutate(question_key = to_db_name(name)) %>%
                    slice(1))
      log_info("  UUID override applied: %s -> UUID %s ('%s')",
               ov_qkey, substr(ov_uuid, 1, 8), override_row$label[1])
    } else {
      log_warn("  UUID override NOT applied -- UUID not found in filtered metadata: %s x %s x %s -> %s",
               ov_ctry, ov_dset, ov_qkey, ov_uuid)
    }
  }

  # -- Build Variables sheet ----------------------------------------------------
  variables <- vars_dedup %>%
    mutate(
      environment              = env_label,
      dataset                  = paste0(country_up, "_", dataset_lc),
      raw_value_column         = paste0(question_key, ".value"),
      raw_label_column         = paste0(question_key, ".label"),
      variable_label           = label,
      raw_data_type            = dataType,
      r_type                   = unname(PIPELINE_TYPE_MAP[dataType]),
      harmonised_variable_name = to_harmonised(name),
      use_in_analysis          = case_when(
        dataType %in% c("text", "zw_edliz_summary_table",
                        "mwi_edliz_summary_table")         ~ FALSE,
        isDraft == TRUE                                    ~ FALSE,
        TRUE                                               ~ TRUE
      ),
      weight_unit   = if_else(question_key %in% WEIGHT_KEYS_GRAMS,
                              "grams", NA_character_),
      confidential  = confidential,          # from JSON (logical)
      record_id_role = case_when(
        question_key == "uid"                     ~ "record_uid",
        question_key == "facility"                ~ "record_facility",
        question_key == "uniquekey"               ~ "record_unique_key",
        question_key == "startedat"               ~ "record_start_timestamp",
        question_key == "completedat"             ~ "record_completion_timestamp",
        question_key == "ingestedat"              ~ "record_ingestion_timestamp",
        question_key %in% RECORD_ID_KEYS          ~ "record_id",
        TRUE                                      ~ NA_character_
      ),
      linkage_role = case_when(
        question_key == "uid"      ~ "primary_linkage_key",
        question_key == "facility" ~ "secondary_linkage_key",
        TRUE                       ~ NA_character_
      ),
      suggested_plausible_min  = NA_real_,
      suggested_plausible_max  = NA_real_,
      cleaning_note            = NA_character_,
      key_unique_key           = uniqueKey
    ) %>%
    select(
      environment, dataset, question_key,
      raw_value_column, raw_label_column,
      variable_label, raw_data_type, r_type, section,
      harmonised_variable_name, use_in_analysis,
      weight_unit, confidential,
      record_id_role, linkage_role,
      suggested_plausible_min, suggested_plausible_max,
      cleaning_note, key_unique_key
      # pii_tier, pii_category, pii_matching_pattern are added below
      # after the PII tier assignment block
    )

  # -- Inject legacy variables (fields absent from data-keys-metadata.json) -----
  # For each LEGACY_VARIABLES entry matching this country x dataset, add a row
  # to the Variables sheet.  Injection happens before user_ranges and MANUAL_RANGES
  # are applied so that both range sources can act on the injected rows.
  for (lv in LEGACY_VARIABLES) {
    if (!identical(country_up, lv$country)) next
    if (!dataset_lc %in% lv$datasets)        next
    if (lv$question_key %in% variables$question_key) {
      log_info("  Legacy variable '%s' already in Variables sheet -- skipping injection.",
               lv$question_key)
      next
    }
    legacy_row <- tibble::tibble(
      environment              = env_label,
      dataset                  = paste0(country_up, "_", dataset_lc),
      question_key             = lv$question_key,
      raw_value_column         = paste0(lv$question_key, ".value"),
      raw_label_column         = paste0(lv$question_key, ".label"),
      variable_label           = lv$label,
      raw_data_type            = lv$data_type,
      r_type                   = lv$r_type,
      section                  = "Legacy (absent from current data-keys-metadata.json)",
      harmonised_variable_name = to_harmonised(lv$question_key),
      use_in_analysis          = lv$use_in_analysis,
      weight_unit              = lv$weight_unit,
      confidential             = FALSE,
      record_id_role           = NA_character_,
      linkage_role             = NA_character_,
      suggested_plausible_min  = lv$plausible_min,
      suggested_plausible_max  = lv$plausible_max,
      cleaning_note            = lv$note,
      key_unique_key           = NA_character_
    )
    variables <- dplyr::bind_rows(variables, legacy_row)
    log_info("  Legacy variable injected: %s ('%s')", lv$question_key, lv$label)
  }

  # -- Inject derived variables (computed by Module 15; no raw .value column) ----
  # Documentation-only rows: raw_value_column is NA so 00_setup.r excludes them
  # from the cleaning feature lists (cfg$num etc.).  See DERIVED_VARIABLES above.
  for (dv in DERIVED_VARIABLES) {
    if (!identical(country_up, dv$country)) next
    if (!dataset_lc %in% dv$datasets)        next
    if (dv$question_key %in% variables$question_key) {
      log_info("  Derived variable '%s' already in Variables sheet -- skipping.",
               dv$question_key)
      next
    }
    derived_row <- tibble::tibble(
      environment              = env_label,
      dataset                  = paste0(country_up, "_", dataset_lc),
      question_key             = dv$question_key,
      raw_value_column         = NA_character_,
      raw_label_column         = NA_character_,
      variable_label           = dv$label,
      raw_data_type            = "derived",
      r_type                   = dv$r_type,
      section                  = "Derived (computed by cleaning pipeline Module 15)",
      harmonised_variable_name = dv$question_key,
      use_in_analysis          = dv$use_in_analysis,
      weight_unit              = dv$weight_unit,
      confidential             = FALSE,
      record_id_role           = NA_character_,
      linkage_role             = NA_character_,
      suggested_plausible_min  = dv$plausible_min,
      suggested_plausible_max  = dv$plausible_max,
      cleaning_note            = dv$note,
      key_unique_key           = NA_character_
    )
    variables <- dplyr::bind_rows(variables, derived_row)
    log_info("  Derived variable registered: %s ('%s')", dv$question_key, dv$label)
  }

  # -- Apply manual plausible ranges --------------------------------------------
  for (key in names(MANUAL_RANGES)) {
    rng <- MANUAL_RANGES[[key]]
    variables <- variables %>%
      mutate(
        suggested_plausible_min = if_else(
          question_key == !!key & is.na(suggested_plausible_min),
          rng[1], suggested_plausible_min),
        suggested_plausible_max = if_else(
          question_key == !!key & is.na(suggested_plausible_max),
          rng[2], suggested_plausible_max)
      )
  }

  # -- Apply user-defined plausible ranges (user_ranges.xlsx) -------------------
  # Reads 00_build_dictionary/user_ranges.xlsx.  The workbook contains one sheet
  # per dataset (e.g. "Admissions", "Discharges", "Neolab").  The sheet for the
  # current dataset is looked up via USER_RANGES_SHEET_MAP.  Row 1 is a banner
  # (skipped via skip = 1 on the header row); row 2 is the header; row 3 is a
  # note about inclusive bounds (skipped because question_key will be blank);
  # rows 4+ are data rows.
  # User ranges are applied AFTER MANUAL_RANGES and OVERRIDE them (no is.na()
  # guard), so the user can adjust any range.
  # Values outside the range are set to NA by Module 11 and coded -8 by Module 16.

  USER_RANGES_SHEET_MAP <- c(
    admissions                  = "Admissions",
    discharges                  = "Discharges",
    maternal_outcomes           = "Maternal_outcomes",
    phc_admissions              = "PHC_admissions",
    phc_discharges              = "PHC_discharges",
    neolab                      = "Neolab",
    infections                  = "Infections",
    baseline                    = "Baseline",
    twenty_8_day_follow_up      = "Follow_up",
    combined_maternity_outcomes = "Comb_maternity",
    dhis2_maternal_outcomes     = "DHIS2_maternal",
    maternity_completeness      = "Maternity_completeness"
  )

  user_ranges_path <- file.path(SCRIPT_DIR, "user_ranges.xlsx")
  if (file.exists(user_ranges_path)) {
    target_sheet <- USER_RANGES_SHEET_MAP[dataset_lc]
    available_sheets <- tryCatch(readxl::excel_sheets(user_ranges_path), error = function(e) character(0))

    if (!is.na(target_sheet) && target_sheet %in% available_sheets) {
      user_ranges <- tryCatch(
        readxl::read_excel(user_ranges_path, sheet = target_sheet, skip = 1,
                           col_types = "text", .name_repair = "unique"),
        error = function(e) {
          message(sprintf("[user_ranges] Could not read sheet '%s': %s", target_sheet, e$message))
          NULL
        }
      )
      if (!is.null(user_ranges) && "question_key" %in% names(user_ranges)) {
        # Drop blank rows (banner note row has no question_key)
        user_ranges <- user_ranges[
          !is.na(user_ranges$question_key) &
          nchar(trimws(user_ranges$question_key)) > 0,
        ]
        if (nrow(user_ranges) > 0) {
          n_applied <- 0L
          for (i in seq_len(nrow(user_ranges))) {
            key <- trimws(user_ranges$question_key[i])
            if (is.na(key) || nchar(key) == 0) next
            mn  <- if ("suggested_plausible_min" %in% names(user_ranges))
                     suppressWarnings(as.numeric(user_ranges$suggested_plausible_min[i]))
                   else NA_real_
            mx  <- if ("suggested_plausible_max" %in% names(user_ranges))
                     suppressWarnings(as.numeric(user_ranges$suggested_plausible_max[i]))
                   else NA_real_
            if (is.na(mn) && is.na(mx)) next   # no range defined for this row
            if (any(variables$question_key == key)) {
              variables <- variables %>%
                mutate(
                  suggested_plausible_min = if_else(
                    question_key == !!key, mn, suggested_plausible_min),
                  suggested_plausible_max = if_else(
                    question_key == !!key, mx, suggested_plausible_max)
                )
              n_applied <- n_applied + 1L
            }
          }
          message(sprintf(
            "[user_ranges] Sheet '%s': applied %d / %d user range(s).",
            target_sheet, n_applied, nrow(user_ranges)
          ))
        } else {
          message(sprintf("[user_ranges] Sheet '%s' contains no data rows -- skipping.", target_sheet))
        }
      } else {
        message(sprintf("[user_ranges] Sheet '%s': 'question_key' column not found -- skipping.", target_sheet))
      }
    } else {
      message(sprintf(
        "[user_ranges] No sheet found for dataset '%s' in user_ranges.xlsx -- skipping.",
        dataset_lc
      ))
    }
  } else {
    message(sprintf("[user_ranges] user_ranges.xlsx not found at %s -- skipping.", user_ranges_path))
  }

  # -- Assign PII tiers to Variables sheet -------------------------------------
  # Adds three new columns: pii_tier, pii_category, pii_matching_pattern.
  # Tier 1 = dictionary confidential flag; Tier 2 = pattern-matched;
  # 'quasi' = flagged but not removed.  NA = no PII classification.

  variables <- variables %>%
    mutate(
      pii_tier             = NA_character_,
      pii_category         = NA_character_,
      pii_matching_pattern = NA_character_
    )

  # Tier 1: confidential flag already in dictionary (NA treated as FALSE)
  variables <- variables %>%
    mutate(
      pii_tier     = if_else(!is.na(confidential) & confidential == TRUE,
                             "1", pii_tier),
      pii_category = if_else(!is.na(confidential) & confidential == TRUE,
                             "direct_identifier", pii_category)
    )

  # Tier 2: pattern-based matching against normalised question_key
  for (i in seq_len(nrow(PII_PATTERNS_DATA))) {
    pat_i     <- PII_PATTERNS_DATA$pattern[i]
    pii_cat_i <- PII_PATTERNS_DATA$pii_category[i]
    matches_i <- grepl(pat_i, variables$question_key, ignore.case = TRUE, perl = TRUE)
    variables <- variables %>%
      mutate(
        pii_tier             = if_else(matches_i & is.na(pii_tier),
                                       "2", pii_tier),
        pii_category         = if_else(matches_i & is.na(pii_category),
                                       pii_cat_i, pii_category),
        pii_matching_pattern = if_else(matches_i & is.na(pii_matching_pattern),
                                       pat_i, pii_matching_pattern)
      )
  }

  # Quasi-identifiers: flagged but not auto-removed
  for (qpat in QUASI_ID_PATTERNS) {
    matches_q <- grepl(qpat, variables$question_key, ignore.case = TRUE, perl = TRUE)
    variables <- variables %>%
      mutate(pii_tier = if_else(matches_q & is.na(pii_tier), "quasi", pii_tier))
  }

  n_pii_1   <- sum(variables$pii_tier == "1",     na.rm = TRUE)
  n_pii_2   <- sum(variables$pii_tier == "2",     na.rm = TRUE)
  n_quasi   <- sum(variables$pii_tier == "quasi", na.rm = TRUE)
  log_info("  PII tiers assigned: tier1=%d | tier2=%d | quasi=%d",
           n_pii_1, n_pii_2, n_quasi)

  # -- Build ValueMaps sheet -----------------------------------------------------
  # Expand the list-column of option UUIDs, then look up code + label
  value_maps <- vars_dedup %>%
    transmute(
      question_key = to_db_name(name),
      option_uuids = options          # list-column of character vectors
    ) %>%
    filter(lengths(option_uuids) > 0) %>%
    tidyr::unnest_longer(option_uuids,
                         values_to   = "option_uuid",
                         indices_include = FALSE) %>%
    left_join(opt_lookup, by = "option_uuid") %>%
    filter(!is.na(raw_code)) %>%
    # Only keep rows whose question_key is in our Variables sheet
    filter(question_key %in% variables$question_key) %>%
    group_by(question_key) %>%
    mutate(option_order = row_number()) %>%
    ungroup() %>%
    transmute(
      question_key,
      raw_code,
      option_label,
      option_order,
      option_uuid,
      canonical_code = raw_code      # default: canonical = raw; edit manually if needed
    ) %>%
    # Deduplicate on (question_key, option_label) rather than (question_key, raw_code).
    # Using raw_code as the dedup key would silently drop label variants that share
    # a code (e.g. "Stillbirth Macerated" and "Stillbirth Mascerated" both -> STBM).
    # Keeping both label rows means Module 04's lbl_to_code map can match either
    # spelling in the raw data.
    distinct(question_key, option_label, .keep_all = TRUE) %>%
    arrange(question_key, option_order)

  # -- Augment ValueMaps with options from ALL data-key versions ----------------
  # vars_dedup keeps only the LATEST version of each question_key, so option
  # codes that existed only in EARLIER versions of a data key (e.g. fontanelle
  # "Flat", resus intervention codes, ttv dose codes) are absent from value_maps
  # above and would be wrongly flagged as non-canonical in historical data.
  # Here we append the UNION of option codes across EVERY non-deleted version of
  # each target data key in the full metadata.  This is decision-free: it only
  # adds codes the web editor itself defined (in some version) as valid options
  # for that variable.  Legacy rows are appended AFTER the current-version rows
  # (so display order is preserved) with canonical_code = raw_code; any
  # VALUEMAP_PATCHES still apply afterwards and can override these.
  value_maps_allver <- md_raw %>%
    filter(!isDeleted, dataType != "option") %>%
    mutate(question_key = to_db_name(name)) %>%
    filter(question_key != "", question_key %in% variables$question_key) %>%
    transmute(question_key, option_uuids = options) %>%
    filter(lengths(option_uuids) > 0) %>%
    tidyr::unnest_longer(option_uuids,
                         values_to       = "option_uuid",
                         indices_include = FALSE) %>%
    left_join(opt_lookup, by = "option_uuid") %>%
    filter(!is.na(raw_code), raw_code != "") %>%
    mutate(option_label = ifelse(is.na(option_label) | option_label == "",
                                 raw_code, option_label)) %>%
    distinct(question_key, raw_code, .keep_all = TRUE)

  legacy_rows <- value_maps_allver %>%
    anti_join(value_maps %>% distinct(question_key, raw_code),
              by = c("question_key", "raw_code")) %>%
    anti_join(value_maps %>% distinct(question_key, option_label),
              by = c("question_key", "option_label")) %>%
    distinct(question_key, raw_code, .keep_all = TRUE)

  if (nrow(legacy_rows) > 0) {
    order_base <- value_maps %>%
      group_by(question_key) %>%
      summarise(max_order = suppressWarnings(max(option_order, na.rm = TRUE)),
                .groups = "drop") %>%
      mutate(max_order = ifelse(is.finite(max_order), max_order, 0L))
    legacy_rows <- legacy_rows %>%
      left_join(order_base, by = "question_key") %>%
      mutate(max_order = ifelse(is.na(max_order), 0L, max_order)) %>%
      group_by(question_key) %>%
      mutate(option_order = max_order + row_number()) %>%
      ungroup() %>%
      transmute(
        question_key,
        raw_code,
        option_label,
        option_order,
        option_uuid,
        canonical_code = raw_code
      )
    value_maps <- dplyr::bind_rows(value_maps, legacy_rows) %>%
      arrange(question_key, option_order)
    log_info("  ValueMaps: +%d legacy option(s) from earlier data-key versions across %d key(s).",
             nrow(legacy_rows), n_distinct(legacy_rows$question_key))
  }

  log_info("  ValueMaps: %d rows | %d unique keys",
           nrow(value_maps), n_distinct(value_maps$question_key))

  # -- Apply VARIABLE_PATCHES ---------------------------------------------------
  # Corrections to Variables sheet rows: PII flags and r_type reclassifications.
  # Run after PII-tier assignment so patches can override the tier assignment
  # that was driven by the (incorrect) confidential flag in the JSON export.
  n_var_patches <- 0L
  for (vp in VARIABLE_PATCHES) {
    if (!identical(country_up, vp$country))  next
    if (!dataset_lc %in% vp$datasets)        next
    qk <- vp$question_key
    if (!qk %in% variables$question_key) {
      log_info("  VARIABLE_PATCH skip (not found): %s [%s x %s]", qk, country_up, dataset_lc)
      next
    }
    for (col in names(vp$changes)) {
      variables[[col]][variables$question_key == qk] <- vp$changes[[col]]
    }
    n_var_patches <- n_var_patches + 1L
    log_info("  VARIABLE_PATCH: %s -- set %s", qk,
             paste(names(vp$changes), "=",
                   sapply(vp$changes, function(v) ifelse(is.na(v), "NA", as.character(v))),
                   collapse = ", "))
  }
  if (n_var_patches > 0)
    log_info("  VARIABLE_PATCHES applied: %d", n_var_patches)

  # -- Apply VALUEMAP_PATCHES ---------------------------------------------------
  # Corrections to ValueMaps sheet: add rows, update canonical codes, or remove
  # duplicate raw_code rows.  All actions are idempotent (safe to re-run).
  n_vm_patches <- 0L
  for (vmp in VALUEMAP_PATCHES) {
    if (!identical(country_up, vmp$country)) next
    if (!dataset_lc %in% vmp$datasets)       next
    qk <- vmp$question_key

    if (vmp$action == "add_rows") {
      existing_labels <- value_maps$option_label[value_maps$question_key == qk]
      rows_to_add <- vmp$rows[!vmp$rows$option_label %in% existing_labels, , drop = FALSE]
      if (nrow(rows_to_add) > 0) {
        max_order <- if (qk %in% value_maps$question_key)
          max(value_maps$option_order[value_maps$question_key == qk], na.rm = TRUE)
        else 0L
        new_rows <- data.frame(
          question_key   = qk,
          raw_code       = rows_to_add$raw_code,
          option_label   = rows_to_add$option_label,
          option_order   = seq(max_order + 1L, max_order + nrow(rows_to_add)),
          option_uuid    = NA_character_,
          canonical_code = rows_to_add$canonical_code,
          stringsAsFactors = FALSE
        )
        value_maps <- dplyr::bind_rows(value_maps, new_rows)
        n_vm_patches <- n_vm_patches + 1L
        log_info("  VALUEMAP_PATCH add_rows: %s -- %d row(s) added.", qk, nrow(new_rows))
      } else {
        log_info("  VALUEMAP_PATCH add_rows: %s -- all rows already present, skipping.", qk)
      }

    } else if (vmp$action == "update_canonical") {
      for (rc in names(vmp$updates)) {
        new_canon <- vmp$updates[[rc]]
        idx <- value_maps$question_key == qk & value_maps$raw_code == rc
        if (any(idx, na.rm = TRUE)) {
          value_maps$canonical_code[idx] <- new_canon
          n_vm_patches <- n_vm_patches + 1L
          log_info("  VALUEMAP_PATCH update_canonical: %s [%s] -> %s", qk, rc, new_canon)
        } else {
          log_info("  VALUEMAP_PATCH update_canonical: %s [%s] not found -- skipping.", qk, rc)
        }
      }

    } else if (vmp$action == "remove_duplicate_raw_code") {
      rc        <- vmp$raw_code
      keep_lbl  <- vmp$keep_label
      dup_mask  <- value_maps$question_key == qk & value_maps$raw_code == rc
      n_dups    <- sum(dup_mask, na.rm = TRUE)
      if (n_dups > 1L) {
        remove_mask <- dup_mask & value_maps$option_label != keep_lbl
        n_removed   <- sum(remove_mask, na.rm = TRUE)
        value_maps  <- value_maps[!remove_mask, , drop = FALSE]
        n_vm_patches <- n_vm_patches + 1L
        log_info("  VALUEMAP_PATCH remove_duplicate_raw_code: %s [%s] -- %d row(s) removed.",
                 qk, rc, n_removed)
      } else {
        log_info("  VALUEMAP_PATCH remove_duplicate_raw_code: %s [%s] -- no duplicates, skipping.",
                 qk, rc)
      }

    } else {
      log_warn("  VALUEMAP_PATCH unknown action '%s' for %s -- skipping.", vmp$action, qk)
    }
  }
  if (n_vm_patches > 0)
    log_info("  VALUEMAP_PATCHES applied: %d action(s).", n_vm_patches)

  # -- Build ReviewNeeded sheet --------------------------------------------------
  review_needed <- variables %>%
    filter(
      (r_type == "categorical" & !question_key %in% value_maps$question_key) |
      (r_type == "numeric"     &  is.na(suggested_plausible_min) &
                                   is.na(suggested_plausible_max)) |
      is.na(r_type)
    ) %>%
    mutate(review_reason = case_when(
      r_type == "categorical" & !question_key %in% value_maps$question_key ~
        "Categorical with no value map entries",
      r_type == "numeric" & is.na(suggested_plausible_min) ~
        "Numeric without plausible range",
      is.na(r_type) ~
        "Unknown dataType (not in PIPELINE_TYPE_MAP)",
      TRUE ~ "Other"
    ))

  log_info("  ReviewNeeded: %d items", nrow(review_needed))

  # -- Write workbook ------------------------------------------------------------
  if (is.null(out_path))
    out_path <- file.path(OUTPUT_DIR,
                          sprintf("dictionary_%s_%s.xlsx",
                                  tolower(country_up), dataset_lc))

  # PII_Patterns sheet: the master reference for all Tier 2 patterns.
  # This is the same PII_PATTERNS_DATA constant defined at the top of the script,
  # embedded here so each workbook is self-contained.
  sheets <- list(
    Variables    = variables,
    ValueMaps    = value_maps,
    PII_Patterns = PII_PATTERNS_DATA
  )
  if (include_review) sheets[["ReviewNeeded"]] <- review_needed

  writexl::write_xlsx(sheets, path = out_path)

  log_info("Written: %s  (%d vars | %d value-map rows | %d review items)",
           basename(out_path), nrow(variables),
           nrow(value_maps), nrow(review_needed))

  invisible(list(variables    = variables,
                 value_maps   = value_maps,
                 review_needed = review_needed))
}

# =============================================================================
# BUILD ALL DICTIONARIES
# =============================================================================
# Standard (both countries): 6 dictionaries
#   ZIM x admissions, discharges, maternal_outcomes
#   MWI x admissions, discharges, maternal_outcomes
#
# Extended (Malawi PHC + Combined Maternity + individual maternal sources):
#   MWI x phc_admissions, phc_discharges
#   MWI x combined_maternity_outcomes  - superset (all 3 maternal source files combined)
#   MWI x dhis2_maternal_outcomes      - DHIS2-linked maternal scripts only
#   MWI x maternity_completeness       - NOT built (no dedicated script in MWI web-editor;
#                                        pipeline falls back to maternal_outcomes dictionary)
#
# Extended (Zimbabwe PHC -- built only if PHC scripts exist in ZIM keys):
#   ZIM x phc_admissions, phc_discharges
#
# "joined_admissions_discharges" is not dictionary-built; it is produced at
# analysis time by joining the cleaned admissions and discharges outputs.
# =============================================================================
cat("\n=== Building Neotree v8 Data Dictionaries from DOWNLOADED keys ===\n\n")

# Country -> list of datasets to attempt
BUILD_PLAN <- list(
  ZIM = c("admissions", "discharges", "maternal_outcomes",
          "phc_admissions", "phc_discharges",
          "neolab",
          # Zimbabwe-specific longitudinal & follow-up forms
          "baseline", "infections", "twenty_8_day_follow_up"),
  MWI = c("admissions", "discharges", "maternal_outcomes",
          "phc_admissions", "phc_discharges",
          "combined_maternity_outcomes",
          "dhis2_maternal_outcomes",
          # maternity_completeness: no dedicated Neotree script exists (data was
          # introduced manually from paper records). The dictionary is built using
          # maternal outcomes scripts as the closest available approximation.
          "maternity_completeness",
          "neolab")
)

errors     <- character()
successes  <- character()

for (cty in names(BUILD_PLAN)) {

  # Load country keys once, reuse for all datasets
  cat(sprintf("Loading data keys for %s...\n", cty))
  country_keys <- tryCatch(
    load_country_keys(cty),
    error = function(e) { message("  [ERROR] ", e$message); NULL }
  )
  if (is.null(country_keys)) {
    errors <- c(errors, sprintf("%s: could not load data keys", cty))
    next
  }

  for (ds in BUILD_PLAN[[cty]]) {
    tryCatch({
      build_dictionary(country = cty, dataset = ds, keys = country_keys)
      successes <<- c(successes, sprintf("%s x %s", cty, ds))
    },
    error = function(e) {
      msg <- sprintf("%s x %s: %s", cty, ds, e$message)
      cat(sprintf("  [WARN] %s\n", msg))
      errors <<- c(errors, msg)
    })
  }
}

n_total <- sum(lengths(BUILD_PLAN))
cat(sprintf("\n=== Done: %d/%d dictionaries written successfully ===\n\n",
            length(successes), n_total))

if (length(errors) > 0) {
  cat(sprintf("%d combination(s) could not be built (no matching scripts found is normal\n",
              length(errors)))
  cat("for PHC datasets if that country's web-editor keys contain no PHC scripts):\n")
  cat(paste(" -", errors, collapse = "\n"), "\n\n")
}

cat("Next steps:\n")
cat("  1. Enrich (scripts):  source('00_build_dictionary/00c_enrich_dictionary_from_scripts.r')\n")
cat("     Adds display_label, optional, skip_condition, valuemap_check to each dictionary.\n")
cat("     Requires script JSONs in neotree_scripts/zim-scripts/ and mwi-scripts/.\n\n")
cat("  2. Enrich (public):   source('00_build_dictionary/00e_enrich_from_public_dictionary.r')\n")
cat("     Adds public_meaning, public_dependency, old_variable_name, timeline_of_change, etc.\n")
cat("     from og_dictionaries/Public_data_dictionary_2024.xlsx.  Documentation only --\n")
cat("     does not change ValueMaps, canonical codes or cleaning behaviour.\n\n")
cat("  3. User dictionary:   source('00_build_dictionary/00d_build_user_dictionary.r')\n")
cat("     Builds the researcher-facing user_dictionaries/neotree_user_dict_{zim,mwi}.xlsx.\n")
cat("     Reads the *_enriched.xlsx dicts, so run it AFTER 00c and 00e.  (Reference only --\n")
cat("     not read by the cleaning pipeline at runtime.)\n\n")
cat("  4. Validate:          source('00_build_dictionary/validate_dictionaries.r')\n\n")
cat("  5. Run the pipeline:  source('run_pipeline.r')  (or use run_all.r for batch mode)\n\n")
cat("Optional: open the ReviewNeeded sheet in any dictionaries/dictionary_*.xlsx to see\n")
cat("fields that may benefit from manual annotation before running the pipeline.\n\n")
