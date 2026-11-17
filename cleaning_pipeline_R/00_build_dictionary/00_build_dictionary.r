# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 00_build: Build the Unified Data Dictionary
# =============================================================================
#
# PURPOSE:
#   Builds one dictionary Excel workbook per country x dataset combination
#   from the Neotree web-editor data-key exports (metadata JSON + usage XLSX).
#
# METHOD:
#   For each country x dataset in BUILD_PLAN, the usage file is filtered to the
#   scripts whose title matches the dataset's regex in DATASET_FILTERS, and the
#   metadata is reduced to one row per question_key (most recent publishDate
#   wins, subject to KEY_UUID_OVERRIDES).  Legacy and derived variables,
#   plausible ranges (MANUAL_RANGES, then user_ranges.xlsx), PII tiers and the
#   VARIABLE_PATCHES / VALUEMAP_PATCHES corrections are then applied.
#
#   Sheets in each workbook:
#     Variables    - one row per unique key, annotated for the pipeline
#     ValueMaps    - one row per allowed option code with its display label
#     PII_Patterns - column-name patterns used for Tier 2 PII removal
#     ReviewNeeded - rows flagged for manual review, with one of these reasons:
#       "Categorical with no value map entries"
#          a categorical field with no option values, so its codes cannot be
#          validated against an allow-list
#       "Numeric without plausible range"
#          a numeric field with no min/max (set one in MANUAL_RANGES or
#          user_ranges.xlsx)
#       "Unknown dataType (not in PIPELINE_TYPE_MAP)"
#          the web-editor dataType has no entry in PIPELINE_TYPE_MAP
#     ReviewNeeded is informational; the pipeline runs with unresolved items.
#
#   With RUN_FOLLOW_ON_STEPS = TRUE the script then runs, each in its own R
#   process, 00c_enrich_dictionary_from_scripts.r and
#   00e_enrich_from_public_dictionary.r, removes staff names from every
#   workbook in dictionaries/, runs 00d_build_user_dictionary.r and checks the
#   user dictionaries in the same way.  Staff names are removed as follows:
#     - script titles listed in TITLE_REPLACEMENTS_FILE are replaced as soon
#       as the data keys are read, before anything is written;
#     - answer options of staff fields are not written to the base
#       dictionaries;
#     - any ValueMaps row of a staff field (STAFF_KEY_PATTERN) left in a
#       dictionary is removed;
#     - in the user dictionaries, the "Values / Codes" cell of a staff field is
#       replaced by STAFF_VALUES_NOTE;
#     - any other occurrence of a staff name or code taken from the answer
#       options of staff fields in the data keys and scripts is replaced by
#       STAFF_TEXT_PLACEHOLDER.  Names of two or more words are matched in any
#       letter case; single words and codes only in their exact case.  Header
#       rows are not changed, and strings that are also used outside staff
#       fields (for example "Other", or the word "Name" in a question) are
#       left unchanged.
#   The run stops with an error if a staff name, a staff code or a listed
#   title is still found anywhere in a workbook file afterwards, including text
#   kept in the file but no longer shown in any cell.
#
# INPUTS:
#   neotree_data_keys/downloaded/neotree_data_keys_zimbabwe/data-keys-metadata.json
#   neotree_data_keys/downloaded/neotree_data_keys_zimbabwe/data-keys-usage.xlsx
#   neotree_data_keys/downloaded/neotree_data_keys_malawi/data-keys-metadata.json
#   neotree_data_keys/downloaded/neotree_data_keys_malawi/data-keys-usage.xlsx
#   Each file name may carry a prefix ending in "-" or "_", for example
#   mwi-data-keys-usage.xlsx; a folder must hold one file of each kind.
#   00_build_dictionary/user_ranges.xlsx (optional)
#   neotree_scripts/zim-scripts/*.json, neotree_scripts/mwi-scripts/*.json
#   00_build_dictionary/private/script_title_replacements.tsv (optional)
#   The data keys and the scripts are downloaded from the Neotree web editors
#   (https://webeditor.neotree.org/ and https://zim-webeditor.neotree.org:10243/)
#   with a Neotree account.  They contain the names of health workers and are
#   not part of the published repository.
#
# OUTPUTS:
#   dictionaries/dictionary_<country>_<dataset>.xlsx for every entry in
#   BUILD_PLAN.  A combination that cannot be built is reported and skipped.
#   With RUN_FOLLOW_ON_STEPS = TRUE also dictionaries/dictionary_*_enriched.xlsx
#   and user_dictionaries/neotree_user_dict_{zim,mwi}.xlsx, all without staff
#   names.
#
# USAGE:
#   source("00_build_dictionary/00_build_dictionary.r")
#   # or:
#   Rscript 00_build_dictionary/00_build_dictionary.r
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
# folder name on case-sensitive filesystems.
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

# Run 00c, 00e and 00d after the base dictionaries are built, then remove staff
# names from every workbook (see the header).  FALSE builds the base
# dictionaries only and does not remove staff names.
RUN_FOLLOW_ON_STEPS <- TRUE

# Staff fields (STAFF_KEY_PATTERN, STAFF_VALUES_NOTE, is_staff_key()): question
# keys whose answer options are names or codes of health workers.
source(file.path(SCRIPT_DIR, "staff_fields.r"))
NEOTREE_SCRIPTS_DIR     <- "neotree_scripts"
USER_DICT_DIR           <- "user_dictionaries"
TITLE_REPLACEMENTS_FILE <- file.path(SCRIPT_DIR, "private", "script_title_replacements.tsv")
STAFF_TEXT_PLACEHOLDER  <- "[staff]"
# Answer options never treated as staff names, whatever the field.
STAFF_GENERIC_OPTIONS   <- c("other", "oth", "none", "unknown", "not known",
                             "n/a", "na", "not applicable", "student", "yes", "no")

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
  # maternity_completeness has no dedicated Neotree script; the regex matches
  # the maternal outcomes scripts.
  maternity_completeness      = "Maternal",
  # Neolab (blood culture): matches only titles starting "NeoLab - Zim" or
  # "NeoLab - Malawi".
  neolab                      = "^NeoLab - (Zim|Malawi)",
  # Zimbabwe-specific extended forms.
  baseline                    = "Baseline|Retrospective",
  # infections: matches script titles containing "Infection" or "NeoInfect".
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
# Ranges are set only for variables whose definition gives hard limits.
# Continuous physiological measures (weight, gestation, temperature, heart
# rate, etc.) have no range here.
#   apgar1/5/10     - Apgar scale is 0-10.
#   satsair/satso2  - oxygen saturation is a percentage (0-100).
#   dischsats       - SpO2 at discharge, a percentage (0-100).
#   thompscore      - Thompson HIE scale has a maximum of 22.
MANUAL_RANGES <- list(
  apgar1           = c(0,     10),
  apgar5           = c(0,     10),
  apgar10          = c(0,     10),
  satsair          = c(0,    100),
  satso2           = c(0,    100),
  dischsats        = c(0,    100),
  thompscore       = c(0,     22),
  # Neolab (blood culture) ranges.
  #   bcreturntime - hours from specimen collection to result; 0 to 1440 (60 days).
  #   poshours     - hours from incubation start to positivity signal; 0 to 120 (5 days).
  #   timespent    - hours for the laboratory procedure or consultation; 0 to 72 (3 days).
  #   episode      - sequential episode counter; lower bound 1, no upper bound
  #                  (NA_real_ leaves suggested_plausible_max as NA).
  bcreturntime     = c(0,         1440),
  poshours         = c(0,          120),
  timespent        = c(0,           72),
  episode          = c(1,     NA_real_)
)

# Explicit UUID overrides for specific country x dataset x question_key combinations.
#
# Needed when two different clinical fields share the same question_key (their
# names reduce to the same string in to_db_name()) and both appear in the same
# dataset's scripts, so the publishDate-based dedup could select the wrong one.
#
# In the MWI maternity scripts a birth-outcome field ("Birth Outcome") and a
# neonatal discharge-outcome field ("Outcome") both produce question_key =
# "neotreeoutcome".  The overrides select the birth-outcome field for the
# maternity dictionaries listed below.
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
# Fields absent from the current data-keys-metadata.json web-editor export that
# appear in raw data.  Each entry adds a Variables row so the pipeline modules
# process the column.
#
# Each list entry defines:
#   country         - uppercase country code ("ZIM" or "MWI")
#   datasets        - character vector of dataset_lc values to inject into
#   question_key    - lowercase field key (no spaces or special characters)
#   label           - variable label
#   data_type       - raw_data_type (web-editor convention, e.g. "number")
#   r_type          - pipeline r_type ("numeric", "boolean", etc.)
#   weight_unit     - "grams" if a weight field; NA_character_ otherwise
#   use_in_analysis - TRUE / FALSE
#   plausible_min   - suggested_plausible_min (NA_real_ for no lower bound)
#   plausible_max   - suggested_plausible_max (NA_real_ for no upper bound)
#   note            - cleaning_note stored in the Variables sheet
#
# Entries are injected after the JSON-driven Variables sheet is built and
# before MANUAL_RANGES and user_ranges.xlsx are applied.  An entry is skipped
# if the question_key is already present in the Variables sheet.
# =============================================================================

LEGACY_VARIABLES <- list(

  # aw -- Admission Weight (g)
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
      "Legacy field from earlier Neotree ZIM admission scripts. ",
      "Absent from data-keys-metadata.json. ",
      "Registered in LEGACY_VARIABLES so that Module 09 ",
      "coerces 'None' strings to NA and validates the numeric range."
    )
  ),

  # bsmmol -- Blood Sugar (mmol/L)
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
      "Legacy field from earlier Neotree ZIM admission scripts; ",
      "older equivalent of bloodsugarmmol. ",
      "Absent from data-keys-metadata.json. ",
      "Registered in LEGACY_VARIABLES so that Module 09 ",
      "coerces 'None' strings to NA and validates the numeric range."
    )
  ),

  # hivtestresult -- HIV Test Result (ValueMaps supplied by VALUEMAP_PATCHES)
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
      "Present in the data but absent from data-keys-metadata.json. ",
      "Registered in LEGACY_VARIABLES so that Module 04 applies value cleaning. ",
      "ValueMaps (R/Positive->R, NR/Negative->NR, U/Unknown->U) added via VALUEMAP_PATCHES."
    )
  ),

  # facilityname -- Name of Facility (MWI phc_discharges)
  # The raw script field key is "Facility".  It is registered as "facilityname"
  # because the standardised raw column would otherwise collide with the
  # reserved system "facility" key column.  cfg$reserved_column_renames in
  # 00_setup.r renames the raw Facility.value/.label columns to
  # facilityname.value/.label; this question_key must match that rename target
  # exactly.
  list(
    country         = "MWI",
    datasets        = c("phc_discharges"),
    question_key    = "facilityname",
    label           = "Name of Facility",
    data_type       = "dropdown",
    r_type          = "categorical",
    weight_unit     = NA_character_,
    use_in_analysis = TRUE,
    plausible_min   = NA_real_,
    plausible_max   = NA_real_,
    note = paste0(
      "Raw script field key is 'Facility'; absent from data-keys-metadata.json ",
      "for phc_discharges although present in the data. ",
      "Registered as 'facilityname' (not 'facility') because the raw column ",
      "collides with the reserved system 'facility' key column after suffix ",
      "stripping; see cfg$reserved_column_renames in 00_setup.r, which renames ",
      "Facility.value/.label to facilityname.value/.label in Module 01 before ",
      "Module 07's duplicate-column logic can discard it in favour of the ",
      "always-populated system column. Registered in LEGACY_VARIABLES. ",
      "ValueMaps (KRH->Kabudula Community Hospital, LH->Lumbadzi Health Center) ",
      "added via VALUEMAP_PATCHES."
    )
  )

)

# =============================================================================
# DERIVED VARIABLES (computed by the cleaning pipeline; not present in raw data)
# =============================================================================
# Columns created by the cleaning pipeline (Modules 11, 14 and 15).  They have
# no raw .value / .label column and are registered here so they are documented
# in the per-table dictionaries and in the user dictionary (00d).
#
# raw_value_column is NA for these rows, so 00_setup.r excludes them from the
# cleaning feature lists (cfg$num etc. require a non-NA raw_value_column).
#
# Weight columns:
#   birthweight_g      coalesce(birthweight, bwt, bwtdis)
#   admission_weight_g admissionweight
#   discharge_weight_g dischweight
#
# Each entry has: country / datasets / question_key / label / r_type /
# weight_unit / use_in_analysis / plausible_min / plausible_max / note.
# Injection is skipped if the question_key is already present in the
# Variables sheet.
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
  ),

  # ---------------------------------------------------------------------------
  # Maternal age (Modules 11 and 15).  The injector sets section =
  # "Derived (computed by cleaning pipeline Module 15)" for every derived row;
  # the originating module is stated in each note.
  # ---------------------------------------------------------------------------

  # mat_age_years_combined -- canonical maternal age in years
  list(
    country = "MWI",
    datasets = c("admissions", "discharges", "phc_admissions", "phc_discharges",
                 "combined_maternity_outcomes", "dhis2_maternal_outcomes",
                 "joined_admissions_discharges"),
    question_key = "mat_age_years_combined",
    label = "Maternal age (years) -- canonical (derived)",
    r_type = "numeric", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = 9, plausible_max = 60,
    note = paste0(
      "Derived canonical maternal age in years. Cleaning pipeline Module 15 ",
      "computes coalesce(matageyrs, mat_age_date_years): the manually entered ",
      "whole-year field wins, falling back to the value derived from matagedate ",
      "(auto-calculated from DOB, stored in HOURS, converted to years and ",
      "range-filtered in Module 11). Both inputs are already range-clean (9-60), ",
      "so this is a lossless coalesce plus a provenance label. Emitted only where ",
      "at least one source column is present. Rows where both sources are present ",
      "and disagree by more than 1 year are counted and logged, never overwritten ",
      "-- see the per-run report 15b_maternal_age_summary.txt. Provenance is in ",
      "mat_age_source. Originals retained. Not a raw field; no .value column.")
  ),
  list(
    country = "ZIM",
    datasets = c("admissions", "baseline", "maternal_outcomes",
                 "joined_admissions_discharges"),
    question_key = "mat_age_years_combined",
    label = "Maternal age (years) -- canonical (derived)",
    r_type = "numeric", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = 9, plausible_max = 60,
    note = paste0(
      "Derived canonical maternal age in years. Cleaning pipeline Module 15 ",
      "computes coalesce(matageyrs, mat_age_date_years). ZIM captures matageyrs ",
      "only (matagedate is a Malawi maternity-form field), so in ZIM data this ",
      "column always equals matageyrs and mat_age_source is always 'matageyrs'; ",
      "the shared derivation keeps the two countries on one schema. Emitted only ",
      "where a source column is present. Originals retained. Not a raw field; ",
      "no .value column.")
  ),

  # mat_age_source -- provenance label for mat_age_years_combined
  list(
    country = "MWI",
    datasets = c("admissions", "discharges", "phc_admissions", "phc_discharges",
                 "combined_maternity_outcomes", "dhis2_maternal_outcomes",
                 "joined_admissions_discharges"),
    question_key = "mat_age_source",
    label = "Maternal age -- source of the derived value (provenance)",
    r_type = "categorical", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = NA, plausible_max = NA,
    note = paste0(
      "Provenance label for mat_age_years_combined, emitted alongside it by ",
      "Module 15. One of: 'matageyrs' (manually entered whole years, the ",
      "priority source), 'matagedate_derived' (converted from the ",
      "auto-calculated DOB field in Module 11), or 'none' (neither source ",
      "populated on that row). Use it to restrict an analysis to manually ",
      "entered ages, or to quantify reliance on the derived fallback. Not a raw ",
      "field; no .value column.")
  ),
  list(
    country = "ZIM",
    datasets = c("admissions", "baseline", "maternal_outcomes",
                 "joined_admissions_discharges"),
    question_key = "mat_age_source",
    label = "Maternal age -- source of the derived value (provenance)",
    r_type = "categorical", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = NA, plausible_max = NA,
    note = paste0(
      "Provenance label for mat_age_years_combined, emitted alongside it by ",
      "Module 15. In ZIM data this is 'matageyrs' wherever an age is present and ",
      "'none' otherwise, because matagedate is a Malawi maternity-form field; the ",
      "'matagedate_derived' level exists for schema parity with MWI. Not a raw ",
      "field; no .value column.")
  ),

  # antenatalcare_source / antenatalcare_category -- ANC recovered from labels
  list(
    country = "MWI",
    datasets = c("admissions"),
    question_key = "antenatalcare_source",
    label = "Antenatal care visits -- source of the value (provenance)",
    r_type = "categorical", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = NA, plausible_max = NA,
    note = paste0(
      "Written by **Module 05** (not Module 15). In some form versions the ",
      "answer to the antenatal care question is stored only in the label ",
      "column and the value column is empty. Module 05 reads the number of ",
      "visits from the label (label-to-value rule in 00_setup.r). One of: ",
      "'raw_numeric_value' (a valid whole number in the value column), ",
      "'raw_exact_label' (a count read from a label such as '3 ANC visits', or ",
      "'None' read as 0), 'raw_range_label' ('More than 4 ANC visits' or 'More ",
      "than 8 ANC visits': no count, category only) or 'unresolved' (no usable ",
      "answer: 'Not sure', 'ANC visits' with no number, question text or ",
      "empty). Not a raw field; no .value column.")
  ),
  list(
    country = "MWI",
    datasets = c("admissions"),
    question_key = "antenatalcare_category",
    label = "Antenatal care visits -- category (derived)",
    r_type = "categorical", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = NA, plausible_max = NA,
    note = paste0(
      "Derived by Module 15 from the final antenatalcare count: 'none' (0 ",
      "visits), '1_3' (1 to 3 visits) or 'ge4' (4 or more visits). A row with ",
      "no count whose antenatalcare_source is 'raw_range_label' is 'ge4'. The ",
      "visit count is never imputed from the category. Missing where the ",
      "answer is unknown. Not a raw field; no .value column.")
  ),

  # hepbdate_date -- Hepatitis B test date split out of the mixed column hepbdate
  list(
    country = "MWI",
    datasets = c("admissions", "phc_admissions", "joined_admissions_discharges"),
    question_key = "hepbdate_date",
    label = "Hepatitis B test date (derived from hepbdate)",
    r_type = "datetime", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = NA, plausible_max = NA,
    note = paste0(
      "Produced by **Module 14** (not Module 15). The app key HepBdate carries ",
      "two questions: the date 'Hepatitis B Test Date' (KCH), and, in the ",
      "Kabudula and PHC scripts, first the yes/no question 'Is Date of ",
      "Hepatitis B same as Date of HIV Test?' with the date asked only when the ",
      "answer is No. The raw column therefore mixes Y/N answers and dates. ",
      "hepbdate keeps the Y/N answers; hepbdate_date holds the dates. Where ",
      "hepbdate is Y, hepbdate_date is empty: the test date is then the HIV ",
      "test date, which is a separate, confidential field. Not a raw field; ",
      "no .value column.")
  ),

  # mat_age_date_years -- years converted from the auto-calculated matagedate
  list(
    country = "MWI",
    datasets = c("combined_maternity_outcomes", "dhis2_maternal_outcomes"),
    question_key = "mat_age_date_years",
    label = "Maternal age (years) from auto-calculated DOB field (derived)",
    r_type = "numeric", weight_unit = NA_character_, use_in_analysis = TRUE,
    plausible_min = 9, plausible_max = 60,
    note = paste0(
      "Produced by **Module 11** (not Module 15) as round(matagedate / 8766), ",
      "where 8766 = 365.25 x 24: matagedate is auto-calculated from the mother's ",
      "date of birth and stored in HOURS, not years. The same 9-60 plausibility ",
      "filter applied to matageyrs is applied here, with out-of-range values set ",
      "to NA and counted in the Module 11 report; raw matagedate is left ",
      "untouched. MWI maternity forms only -- ZIM does not capture matagedate. ",
      "This is an intermediate: prefer mat_age_years_combined for analysis, and ",
      "use this column only to inspect the auto-calculated source directly. Not ",
      "a raw field; no .value column.")
  )

)

# =============================================================================
# POST-BUILD PATCHES
# =============================================================================
# Applied inside build_dictionary() after the main Variables and ValueMaps
# sheets are assembled and before the workbook is written:
#   VARIABLE_PATCHES   -- column-level corrections to the Variables sheet
#   VALUEMAP_PATCHES   -- add rows, update canonical codes, or remove
#                         duplicate rows in the ValueMaps sheet
#
# An entry is skipped when the target question_key is not present in the
# relevant sheet.
# =============================================================================

# -- VARIABLE_PATCHES ----------------------------------------------------------
# Each entry: country, datasets (vector), question_key, changes (named list).
# 'changes' maps column names to new values; NA_character_ clears a column.

VARIABLE_PATCHES <- list(

  # -- PII classification overrides ---------------------------------------------
  # Clinical-outcome HIV-related fields flagged confidential=TRUE in the MWI
  # web-editor JSON.  Module 00a drops every confidential=TRUE column; these
  # entries clear the flag and the PII tier so the columns are kept.

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
  # These fields use the yesno web-editor dataType, which PIPELINE_TYPE_MAP
  # maps to "boolean".  ZIM dictionaries classify them as "categorical".
  # Module 12 (boolean) outputs TRUE/FALSE; Module 13 (categorical) outputs
  # Y/N/U character codes.  Reclassifying to categorical gives both countries
  # the same output format.

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

  # MWI phc_discharges: facilityname ValueMaps (field injected via LEGACY_VARIABLES).
  # One row per option: Module 04 matches raw values against option_label as
  # well as raw_code, so the short code and the full facility name resolve to
  # the same canonical code.
  list(country = "MWI", datasets = c("phc_discharges"),
       question_key = "facilityname", action = "add_rows",
       rows = data.frame(
         raw_code       = c("KRH",                          "LH"),
         option_label   = c("Kabudula Community Hospital",   "Lumbadzi Health Center"),
         canonical_code = c("KRH",                           "LH"),
         stringsAsFactors = FALSE
       )),

  # ZIM admissions: hivtestresult ValueMaps (field injected via LEGACY_VARIABLES).
  # Long labels "Positive"/"Negative" map to the canonical codes R/NR/U used
  # for MWI.
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

  # MWI: lengthhaart has raw_code 3rdTrim on two option rows.  The row labelled
  # "3rd Trimester more than 1 month before delivery" is kept.
  list(country = "MWI", datasets = c("admissions", "discharges"),
       question_key = "lengthhaart", action = "remove_duplicate_raw_code",
       raw_code   = "3rdTrim",
       keep_label = "3rd Trimester more than 1 month before delivery"),

  # ===========================================================================
  # Legacy categorical values from older Neotree form versions, mapped to the
  # current canonical code of each field.  Each row adds an alias raw_code for
  # an existing canonical option.
  # ===========================================================================

  # -- Section 1: coding-scheme / direction -----------------------------------

  # inorout: legacy Yes/true = Inborn (In); legacy No/false = Outborn (Out).
  # The field's canonical set is {In,Out}, so explicit aliases are required.
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

  # modedelivery: numeric codes 1-7 (1=SVD, 2=Vacuum, 3=Forceps, 4=Elective CS,
  # 5=Emergency CS, 6=Breech, 7=Induced Vaginal Delivery).  Text labels are
  # recoded to numeric by harmonise_modedelivery() in Module 04.  This entry
  # registers "1" (SVD) as a canonical code.
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

  # admittedfrom: ER = "External Referral", kept as its own canonical option
  # (distinct from AE/Cas).
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

  # -- Section 3: legacy Yes/No on fields with coded scales ------------------

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

  # matsymptoms: N = None (Norm); O = Other (Oth).
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "matsymptoms", action = "add_rows",
       rows = data.frame(
         raw_code       = c("N",    "O"),
         option_label   = c("None (legacy N)", "Other (legacy O)"),
         canonical_code = c("Norm", "Oth"),
         stringsAsFactors = FALSE
       )),

  # matcomorbidities: N = None (Norm); O = Other (Oth).
  list(country = "ZIM", datasets = c("admissions"),
       question_key = "matcomorbidities", action = "add_rows",
       rows = data.frame(
         raw_code       = c("N",    "O"),
         option_label   = c("None (legacy N)", "Other (legacy O)"),
         canonical_code = c("Norm", "Oth"),
         stringsAsFactors = FALSE
       )),

  # receivedantenatalcare (Pregnancy Booking Status): Y/Yes = Booked (Bkd);
  # N/No = Unbooked (Ubkd).
  list(country = "ZIM", datasets = c("admissions", "baseline"),
       question_key = "receivedantenatalcare", action = "add_rows",
       rows = data.frame(
         raw_code       = c("Y",   "Yes", "N",    "No"),
         option_label   = c("Booked (legacy Y)", "Booked (legacy Yes)", "Unbooked (legacy N)", "Unbooked (legacy No)"),
         canonical_code = c("Bkd", "Bkd", "Ubkd", "Ubkd"),
         stringsAsFactors = FALSE
       )),

  # cadredis (Type of Health Care Worker): 'NO' / 'NO - Nursing Officer' maps
  # to N (Nurse).
  list(country = "MWI", datasets = c("discharges"),
       question_key = "cadredis", action = "add_rows",
       rows = data.frame(
         raw_code       = c("NO",             "NO - Nursing Officer"),
         option_label   = c("Nursing Officer (legacy NO)", "Nursing Officer (legacy long form)"),
         canonical_code = c("N",              "N"),
         stringsAsFactors = FALSE
       )),

  # -- Section 4: legacy diagnosis / admission-reason codes --------------------
  # Each mapping targets a code in the field's current canonical set.
  # Multi-diagnosis legacy tokens map to a brace multi-select of current codes
  # (e.g. PremRDS -> {Prem,DIB}).  Legacy codes with no current target are not
  # mapped.

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
# These patterns identify PII fields by column-name matching:
#   - Embedded in each dictionary workbook as the PII_Patterns sheet
#   - Read by Module 00a at runtime
#   - Matched against normalised column names (lowercase, no whitespace/underscores)
#
# QUASI_ID_PATTERNS are flagged in the audit report but not removed.

PII_PATTERNS_DATA <- tibble::tribble(
  ~pattern,            ~pattern_type,  ~pii_category,   ~reason,
  ~countries,          ~examples,
  ~added_date,         ~notes,

  "name\\.value$",     "suffix_match", "personal_name",
    "Personal names (baby, mother, next of kin)",
    "MWI, ZIM",
    "babyfirstname.value, mothersurname.value, kinname.value",
    NA_character_,  NA_character_,

  "cell\\.value$",     "suffix_match", "phone_number",
    "Mobile/cell phone numbers",
    "MWI",
    "mothcell.value",
    NA_character_,  NA_character_,

  "phone\\.value$",    "suffix_match", "phone_number",
    "Landline phone number fields",
    "ZIM",
    "(various phone fields)",
    NA_character_,  NA_character_,

  "address\\.value$",  "suffix_match", "address",
    "Physical address fields",
    "ZIM",
    "matphysaddressdistrict.value",
    NA_character_,  NA_character_,

  "hcwid",             "contains",     "identifier",
    "Healthcare worker IDs at admission and discharge",
    "MWI, ZIM",
    "hcwid.value, hcwid.label, hcwiddis.value",
    NA_character_,  NA_character_,

  "hospnum",           "contains",     "identifier",
    "Hospital patient numbers",
    "ZIM",
    "mathospnum.value, babyhospnum.value",
    NA_character_,  NA_character_,

  "neotreeid",         "contains",     "identifier",
    "Internal Neotree patient identifier",
    "MWI, ZIM",
    "neotreeid.value",
    NA_character_,  NA_character_,

  "stuid",             "contains",     "identifier",
    "Student/study healthcare worker ID",
    "MWI",
    "stuid.value, stuid.label",
    NA_character_,  "Matches both the .value and the .label column",

  "uidbid\\.value$",   "suffix_match", "identifier",
    "Baby unique identifier",
    "MWI, ZIM",
    "uidbid.value",
    NA_character_,  NA_character_,

  "uiddc\\.value$",    "suffix_match", "identifier",
    "Discharge unique identifier",
    "MWI, ZIM",
    "uiddc.value",
    NA_character_,  NA_character_,

  "drid\\.value$",     "suffix_match", "identifier",
    "DR / practitioner identifier",
    "MWI, ZIM",
    "drid.value",
    NA_character_,  NA_character_,

  "^(firm|concall|hcwsigdis|dataentryname(other)?)\\.(value|label)(discharge)?$", "exact_match", "staff_identifier",
    "Consultant on call, discharge signature, person entering the data (identify a member of staff)",
    "MWI, ZIM",
    "firm.value, concall.value, hcwsigdis.value, dataentryname.label, dataentrynameother.value",
    NA_character_,
    "The same pattern is in PII_FALLBACK_PATTERNS_DEFAULT (00_setup.r).",

  "^(mother|moth|mat|mum)s?(dob|dateofbirth)\\.(value|label)$", "exact_match", "date_of_birth",
    "Mother's date of birth (keeps motherdobyn, the yes/no question)",
    "ZIM",
    "motherdob.value, motherdob.label",
    NA_character_,
    paste("The field has no dictionary entry, so it is removed by name pattern.",
          "The same pattern is in PII_FALLBACK_PATTERNS_DEFAULT (00_setup.r).")
)

# Quasi-identifiers: flagged in the audit report but not removed.
# Recorded as pii_tier = 'quasi' in the Variables sheet.
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

# Path of one data-key export file in a country folder.  The name may carry a
# prefix ending in "-" or "_" (for example mwi-data-keys-usage.xlsx).  Returns NA
# when the folder has no such file and stops when it has more than one.
find_key_file <- function(folder, name) {
  dir  <- file.path(DOWNLOADED_KEYS_BASE, folder)
  hits <- list.files(dir, full.names = TRUE)
  b    <- basename(hits)
  hits <- hits[b == name | endsWith(b, paste0("-", name)) | endsWith(b, paste0("_", name))]
  if (length(hits) > 1L)
    stop(sprintf("More than one %s in %s:\n  %s", name, dir,
                 paste(basename(hits), collapse = "\n  ")))
  if (!length(hits)) return(NA_character_)
  hits
}

# Script titles to replace (TITLE_REPLACEMENTS_FILE), longest first.
read_title_replacements <- function() {
  if (!file.exists(TITLE_REPLACEMENTS_FILE)) return(data.frame(original_title = character(0),
                                                               published_title = character(0)))
  tr <- utils::read.delim(TITLE_REPLACEMENTS_FILE, sep = "\t", quote = "", colClasses = "character",
                          encoding = "UTF-8", na.strings = character(0))
  tr <- tr[nzchar(tr$original_title), c("original_title", "published_title")]
  tr[order(-nchar(tr$original_title)), ]
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

  md_path <- find_key_file(folder, "data-keys-metadata.json")
  us_path <- find_key_file(folder, "data-keys-usage.xlsx")

  if (is.na(md_path))
    stop(sprintf("data-keys-metadata.json (with or without a prefix) not found in:\n  %s",
                 file.path(DOWNLOADED_KEYS_BASE, folder)))
  if (is.na(us_path))
    stop(sprintf("data-keys-usage.xlsx (with or without a prefix) not found in:\n  %s",
                 file.path(DOWNLOADED_KEYS_BASE, folder)))

  # -- Metadata ----------------------------------------------------------------
  # fromJSON returns a data.frame with options as a list-column of character vectors
  md_raw <- fromJSON(md_path, simplifyDataFrame = TRUE)

  # Ensure options is always a list-column (it should be, but be defensive)
  if (!is.list(md_raw$options))
    md_raw$options <- as.list(md_raw$options)

  # Build option lookup: uniqueKey -> (name=raw_code, label=option_label).
  # trimws() is applied to both so that leading/trailing whitespace in the
  # export does not prevent matching in Module 04.
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
  # Normalise column names: lowercase, strip all non-alphanumeric characters
  # (DataKeyUniqueKey -> datakeyuniquekey, ScriptTitle -> scripttitle).
  names(usage_raw) <- tolower(gsub("[^a-zA-Z0-9]", "", names(usage_raw)))

  # Script titles that contain a person's name are replaced here, before any
  # dictionary is written.
  titles <- read_title_replacements()
  if (nrow(titles) && "scripttitle" %in% names(usage_raw)) {
    st <- as.character(usage_raw$scripttitle)
    for (k in seq_len(nrow(titles))) {
      hit <- !is.na(st) & grepl(titles$original_title[k], st, fixed = TRUE)
      st[hit] <- gsub(titles$original_title[k], titles$published_title[k], st[hit], fixed = TRUE)
    }
    usage_raw$scripttitle <- st
  }

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

  # -- Inject derived variables (no raw .value column) ---------------------------
  # raw_value_column is NA so 00_setup.r excludes these rows from the cleaning
  # feature lists (cfg$num etc.).  See DERIVED_VARIABLES above.
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
  # User ranges are applied after MANUAL_RANGES and override them (no is.na()
  # guard).

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
  # Adds three columns: pii_tier, pii_category, pii_matching_pattern.
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
    # Deduplicate on (question_key, option_label) rather than (question_key,
    # raw_code), so label variants that share a code are all kept and Module 04
    # can match any of them.
    distinct(question_key, option_label, .keep_all = TRUE) %>%
    arrange(question_key, option_order)

  # -- Augment ValueMaps with options from all data-key versions ----------------
  # vars_dedup keeps only the latest version of each question_key.  This step
  # appends the union of option codes across every non-deleted version of each
  # target data key, so codes defined only in earlier versions are recognised.
  # The added rows follow the current-version rows, with canonical_code =
  # raw_code; VALUEMAP_PATCHES are applied afterwards and can override them.
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
  # Run after PII-tier assignment so patches can override the tier derived from
  # the confidential flag in the JSON export.
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
  # duplicate raw_code rows.
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

  # PII_Patterns sheet: PII_PATTERNS_DATA, embedded so each workbook is
  # self-contained.
  sheets <- list(
    Variables    = variables,
    ValueMaps    = value_maps,
    PII_Patterns = PII_PATTERNS_DATA
  )
  if (include_review) sheets[["ReviewNeeded"]] <- review_needed

  # Answer options of staff fields are not written (see STAFF_KEY_PATTERN).
  if (isTRUE(RUN_FOLLOW_ON_STEPS) && "question_key" %in% names(sheets$ValueMaps)) {
    sheets$ValueMaps <- sheets$ValueMaps[!grepl(STAFF_KEY_PATTERN, sheets$ValueMaps$question_key,
                                                ignore.case = TRUE), , drop = FALSE]
  }
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
# Builds every country x dataset combination listed in BUILD_PLAN.
# "joined_admissions_discharges" has no dictionary of its own; it is produced
# by joining the cleaned admissions and discharges outputs.
# =============================================================================
cat("\n=== Building Neotree Data Dictionaries from DOWNLOADED keys ===\n\n")

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
          # maternity_completeness: no dedicated Neotree script; built from the
          # maternal outcomes scripts.
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

# =============================================================================
# Follow-on steps and removal of staff names
# =============================================================================

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Answer options (codes and labels) of staff fields in the data keys and the
# scripts, without the strings that are also used outside staff fields.
collect_staff_strings <- function() {
  staff  <- character(0)
  other  <- character(0)
  is_staff_key <- function(k) is.character(k) && length(k) == 1 &&
    grepl(STAFF_KEY_PATTERN, k, ignore.case = TRUE)   # raw keys only

  for (folder in unlist(COUNTRY_FOLDERS)) {
    md_path <- find_key_file(folder, "data-keys-metadata.json")
    if (is.na(md_path)) next
    md <- jsonlite::fromJSON(md_path, simplifyVector = FALSE)
    ids <- vapply(md, function(e) as.character(e$uuid %||% e$uniqueKey %||% NA), character(1))
    names(md) <- ids
    staff_option_ids <- character(0)
    for (e in md) {
      if (is_staff_key(e$name)) {
        staff_option_ids <- c(staff_option_ids, unlist(e$options))
      }
    }
    for (e in md) {
      txt <- c(as.character(e$name %||% character(0)), as.character(e$label %||% character(0)))
      if (as.character(e$uuid %||% "") %in% staff_option_ids ||
          as.character(e$uniqueKey %||% "") %in% staff_option_ids) {
        staff <- c(staff, txt)
      } else if (!is_staff_key(e$name)) {
        other <- c(other, txt)
      }
    }
  }

  walk_scripts <- function(o) {
    if (is.list(o)) {
      if (is_staff_key(o$key)) {
        for (opt in c(o$options, o$items)) {
          if (is.list(opt)) staff <<- c(staff, unlist(opt[c("value", "valueLabel", "label", "key")]))
        }
        return(invisible(NULL))
      }
      if (!is.null(o$key) && is.character(o$key)) {
        for (opt in c(o$options, o$items)) {
          if (is.list(opt)) other <<- c(other, unlist(opt[c("value", "valueLabel", "label", "key")]))
        }
        other <<- c(other, as.character(o$label %||% character(0)))
      }
      for (x in o) walk_scripts(x)
    }
    invisible(NULL)
  }
  for (f in list.files(NEOTREE_SCRIPTS_DIR, pattern = "\\.json$", recursive = TRUE, full.names = TRUE)) {
    walk_scripts(tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  }

  staff <- unique(trimws(as.character(staff)))
  other <- unique(trimws(as.character(other)))
  other_words <- unique(unlist(strsplit(other, "[^A-Za-z0-9_]+")))
  other <- tolower(other)
  staff <- staff[nchar(staff) >= 3 & grepl("[A-Za-z]", staff)]
  staff <- staff[!tolower(staff) %in% c(other, STAFF_GENERIC_OPTIONS)]
  staff <- staff[order(-nchar(staff))]
  multi <- grepl("\\s", staff)
  # A single word that also occurs in text outside staff fields is an ordinary
  # word there (for example "Name"); it is not treated as a staff name.
  single <- staff[!multi]
  single <- single[!single %in% other_words]
  list(multi = staff[multi], single = single)
}

# Whole-word patterns, one per block of strings.  Letters, digits and "_"
# count as word characters, so identifiers such as column names are not split.
staff_patterns <- function(strings, ignore_case, block = 300L) {
  if (!length(strings)) return(character(0))
  esc <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", strings)
  idx <- split(seq_along(esc), ceiling(seq_along(esc) / block))
  vapply(idx, function(i) paste0(if (ignore_case) "(?i)" else "", "(?<![A-Za-z0-9_])(",
                                 paste(esc[i], collapse = "|"), ")(?![A-Za-z0-9_])"),
         character(1))
}

# openxlsx returns some text with XML entities; this restores the plain text.
xml_unescape <- function(x) {
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  gsub("&amp;", "&", x, fixed = TRUE)
}


# Removes staff names from one workbook; returns the number of cells changed.
scrub_workbook <- function(path, patterns, titles) {
  wb <- openxlsx::loadWorkbook(path)
  n_changed <- 0L
  for (sh in names(wb)) {
    df <- openxlsx::read.xlsx(wb, sheet = sh, colNames = FALSE, skipEmptyRows = FALSE,
                              skipEmptyCols = FALSE, detectDates = FALSE)
    if (is.null(df) || !nrow(df)) next
    header <- as.character(unlist(df[1, ]))

    # ValueMaps: drop the rows of staff fields
    if (sh == "ValueMaps" && "question_key" %in% header) {
      qk <- as.character(df[[which(header == "question_key")[1]]])
      drop <- which(seq_along(qk) > 1 & grepl(STAFF_KEY_PATTERN, qk, ignore.case = TRUE))
      if (length(drop)) {
        vm <- openxlsx::read.xlsx(wb, sheet = sh, colNames = TRUE, check.names = FALSE,
                                  skipEmptyRows = FALSE, detectDates = FALSE)
        n_old <- nrow(vm)
        vm <- vm[-(drop - 1L), , drop = FALSE]
        for (cn in names(vm)) if (is.character(vm[[cn]])) vm[[cn]] <- xml_unescape(vm[[cn]])
        openxlsx::deleteData(wb, sheet = sh, cols = seq_len(ncol(df)), rows = 2:(n_old + 1L),
                             gridExpand = TRUE)
        if (nrow(vm)) openxlsx::writeData(wb, sheet = sh, x = vm, startRow = 2, colNames = FALSE)
        n_changed <- n_changed + length(drop)
        df <- openxlsx::read.xlsx(wb, sheet = sh, colNames = FALSE, skipEmptyRows = FALSE,
                                  skipEmptyCols = FALSE, detectDates = FALSE)
      }
    }

    # User dictionaries: no value list for staff fields
    vcol <- which(header == "Values / Codes"); ncol_v <- which(header == "Variable Name")
    if (length(vcol) && length(ncol_v)) {
      vn <- as.character(df[[ncol_v[1]]])
      # user dictionaries use harmonised names, e.g. hcwsig_dis for hcwsigdis
      vn_key <- gsub("_", "", sub("(\\.value|\\.label)$", "", vn))
      rows <- which(seq_along(vn) > 1 & grepl(STAFF_KEY_PATTERN, vn_key, ignore.case = TRUE))
      for (r in rows) {
        if (!identical(xml_unescape(as.character(df[r, vcol[1]])), STAFF_VALUES_NOTE)) {
          openxlsx::writeData(wb, sheet = sh, x = STAFF_VALUES_NOTE, startCol = vcol[1], startRow = r)
          df[r, vcol[1]] <- STAFF_VALUES_NOTE
          n_changed <- n_changed + 1L
        }
      }
    }

    # Titles and remaining staff names in any text cell
    for (j in seq_along(df)) {
      if (!is.character(df[[j]])) next
      x <- xml_unescape(df[[j]])
      x[1] <- NA_character_                 # header row is never changed
      new <- x
      for (k in seq_len(nrow(titles))) {
        hit <- !is.na(new) & grepl(titles$original_title[k], new, fixed = TRUE)
        if (any(hit)) new[hit] <- gsub(titles$original_title[k], titles$published_title[k], new[hit], fixed = TRUE)
      }
      # section holds a sorted list of script titles; keep it sorted
      if (identical(header[j], "section")) {
        re <- which(!is.na(new) & new != x)
        new[re] <- vapply(strsplit(new[re], "; ", fixed = TRUE),
                          function(t) paste(sort(unique(t)), collapse = "; "), character(1))
      }
      for (p in patterns) {
        hit <- !is.na(new) & grepl(p, new, perl = TRUE)
        if (any(hit)) new[hit] <- gsub(p, STAFF_TEXT_PLACEHOLDER, new[hit], perl = TRUE)
      }
      changed <- which(!is.na(new) & new != x)
      for (r in changed) openxlsx::writeData(wb, sheet = sh, x = new[r], startCol = j, startRow = r)
      n_changed <- n_changed + length(changed)
    }
  }
  if (n_changed > 0L) openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  n_changed
}

# Counts staff names, staff codes and listed titles left anywhere in one
# workbook file, including text that no cell shows any more.
count_staff_left <- function(path, patterns, titles) {
  td <- tempfile("xlsxcheck_"); on.exit(unlink(td, recursive = TRUE), add = TRUE)
  utils::unzip(path, exdir = td)
  n <- 0L
  for (f in list.files(td, pattern = "\\.xml$", recursive = TRUE, full.names = TRUE)) {
    txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    txt <- xml_unescape(gsub("<[^>]+>", "\n", txt))
    lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
    lines <- lines[nzchar(trimws(lines))]
    if (!length(lines)) next
    for (p in patterns) n <- n + sum(grepl(p, lines, perl = TRUE))
    for (t in titles$original_title) n <- n + sum(grepl(t, lines, fixed = TRUE))
  }
  n
}

if (isTRUE(RUN_FOLLOW_ON_STEPS)) {
  rscript <- file.path(R.home("bin"), "Rscript")
  run_step <- function(step) {
    cat(sprintf("\n=== Running %s ===\n", step))
    status <- system2(rscript, shQuote(file.path(SCRIPT_DIR, step)))
    if (!identical(as.integer(status), 0L)) stop(sprintf("%s ended with status %s.", step, status))
  }
  run_step("00c_enrich_dictionary_from_scripts.r")
  run_step("00e_enrich_from_public_dictionary.r")

  cat("\n=== Removing staff names ===\n")
  staff_strings <- collect_staff_strings()
  patterns      <- c(staff_patterns(staff_strings$multi, ignore_case = TRUE),
                     staff_patterns(staff_strings$single, ignore_case = FALSE))
  titles        <- read_title_replacements()
  cat(sprintf("Staff names and codes found in the data keys and scripts: %d\n",
              length(staff_strings$multi) + length(staff_strings$single)))
  cat(sprintf("Script titles listed for replacement                    : %d\n", nrow(titles)))

  # The dictionaries are cleaned before the user dictionaries are built from
  # them, so that no staff name is ever written to a user dictionary.  Base
  # workbooks come first, so each enriched copy stays newer than its base.
  dicts <- list.files(OUTPUT_DIR, pattern = "^dictionary_.*\\.xlsx$", full.names = TRUE)
  dicts <- dicts[order(grepl("_enriched\\.xlsx$", dicts))]
  n_cells <- 0L
  for (b in dicts) n_cells <- n_cells + scrub_workbook(b, patterns, titles)

  run_step("00d_build_user_dictionary.r")
  users <- list.files(USER_DICT_DIR, pattern = "\\.xlsx$", full.names = TRUE)
  for (b in users) n_cells <- n_cells + scrub_workbook(b, patterns, titles)
  books <- c(dicts, users)
  cat(sprintf("Cells changed: %d in %d workbook(s)\n", n_cells, length(books)))

  left <- vapply(books, count_staff_left, integer(1), patterns = patterns, titles = titles)
  if (any(left > 0)) {
    stop(sprintf("Staff names still found after removal: %s",
                 paste(sprintf("%s (%d)", basename(books[left > 0]), left[left > 0]), collapse = ", ")))
  }
  cat("Check passed: no staff name, staff code or listed title remains in any file.\n\n")
  cat("Optional next step: source('00_build_dictionary/validate_dictionaries.r')\n")
  cat("Then run the pipeline: source('run_pipeline.r') or run_all.r for batch mode.\n\n")
} else {
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
}
