# =============================================================================
# NEOTREE CLEANING PIPELINE -- PRE-PIPELINE SETUP SCRIPT  (step 2 of 2)
# Module 00c: Enrich Data Dictionary from Neotree Script JSONs
# =============================================================================
#
# PURPOSE:
#   Reads the dictionary .xlsx workbooks produced by 00_build_dictionary_v8.r
#   (step 1) and adds four new columns to the Variables sheet of each workbook
#   by cross-referencing the Neotree script metadata JSONs in neotree_scripts/:
#
#     display_label  -- human-readable field label shown in the Neotree app
#     optional       -- whether the field is optional (TRUE / FALSE / NA when
#                      inconsistent across scripts for the same key)
#     skip_condition -- raw condition expression(s) controlling field visibility
#                      (blank when the field is always shown)
#     valuemap_check -- TRUE when the script's coded options differ from the
#                      dictionary's ValueMaps sheet; FALSE when they match;
#                      NA when comparison is not possible (e.g. free-text field)
#
# PREREQUISITES:
#   00_build_dictionary_v8.r must have been run first to create the .xlsx files
#   in dictionaries/.
#
# HOW TO RUN:
#   # From the pipeline root directory (cleaning_pipeline_4DSH/):
#   source("00_build_dictionary/00c_enrich_dictionary_from_scripts.r")
#   # or:
#   Rscript 00_build_dictionary/00c_enrich_dictionary_from_scripts.r
#
# WHEN TO RE-RUN:
#   Re-run whenever:
#     - new Neotree script JSONs are downloaded to neotree_scripts/
#     - existing script JSONs are updated (e.g. after a script republication)
#   The script is safe to re-run at any time; it only updates the four
#   enrichment columns and leaves all other dictionary content untouched.
#
# SCRIPT-TO-DICTIONARY MATCHING:
#   Raw Firebase-style script IDs recorded in data rows do not match the
#   UUID-style IDs in the downloaded JSON files.  Matching is therefore done
#   by country + dataset using FACILITY_SCRIPT_MAP (defined below).
#   If new hospitals are added or scripts are replaced, update that map.
#
# NOTE ON FORMATTING:
#   New columns are appended to (or refreshed in) the Variables sheet using
#   targeted cell writes, leaving all pre-existing columns and styles intact.
#
# STANDALONE:
#   This script has NO dependencies on the cleaning pipeline.  It uses only
#   base R, jsonlite, and openxlsx.
# =============================================================================

# -----------------------------------------------------------------------------
# Run-from-anywhere: anchor the working directory to the pipeline root so every
# relative path below resolves regardless of where the script was launched
# (Rscript, source(), RStudio "Source", or the R console).  This file lives in
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

# -- USER CONFIG ---------------------------------------------------------------
# TRUE  => overwrite the existing dictionary files in place (recommended).
# FALSE => save enriched copies as dictionary_*_enriched.xlsx alongside the
#          originals (useful for inspection before committing changes).
OVERWRITE_IN_PLACE <- FALSE

# Root of the downloaded Neotree script JSON files (relative to pipeline root).
# Should contain zim-scripts/ and mwi-scripts/ subdirectories.
NEOTREE_SCRIPTS_BASE <- "neotree_scripts"

# Directory containing the dictionary .xlsx files produced by
# 00_build_dictionary_v8.r (relative to pipeline root).
DICT_DIR <- "dictionaries"
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(jsonlite) # fromJSON()
  library(openxlsx) # loadWorkbook(), read.xlsx(), writeData(), saveWorkbook()
})

# Null-coalescing operator used throughout this script
`%||%` <- function(a, b) if (!is.null(a)) a else b


# =============================================================================
# SECTION 1 -- FACILITY -> SCRIPT UUID MAPPING
# =============================================================================
# Maps (country, dataset, facility) -> script UUID from the downloaded JSONs.
#
# NOTE: This map mirrors the one in
#   16_na_reason_coding/helpers/03_facility_script_map.r
# If scripts are updated or new hospitals are added, update BOTH files.

FACILITY_SCRIPT_MAP <- list(
  ZIM = list(
    admissions = list(
      SMCH = "e7da1901-f1c3-43ca-abf9-a7cd01c922b0", # Sally Mugabe CH Admission
      CPH  = "0ccf5891-1672-4aa0-8d92-796c22d283d7", # Chinhoyi Provincial Hospital Admission
      BPH  = "40eefcd8-42c1-4c4f-9b5d-3f391e1438d0", # Bindura Hospital Admission
      PGH  = "683d8b08-1e6d-4694-87b3-c3d8b9dc557b" # Parirenyatwa Group of Hospitals Admission
    ),
    discharges = list(
      SMCH = "6e774101-841c-4388-ad11-033ff7028daa", # Sally Mugabe CH Discharge
      CPH  = "a0372aa9-f53d-4038-b5c0-62b4d4327b87", # Chinhoyi Provincial Hospital Discharge
      BPH  = "6364caaa-7899-47b9-975e-f05151e4e13c", # Bindura Hospital Discharge
      PGH  = "aea9db53-b185-46c1-84cf-9243f87cc246" # Parirenyatwa Group of Hospitals Discharge
    ),
    maternal_outcomes = list(
      SMCH = "9df77822-b8ff-43e6-8c3a-c455e9cf4a02", # SMCH Maternal Outcomes
      CPH  = "fd81a5ac-cece-487c-8737-c98cfd046be1", # Chinhoyi Maternity Outcome
      BPH  = "4e69e777-f680-4615-9bbe-fad81d85d6cd" # Bindura Hospital Maternal Outcomes
    ),
    # Neolab (blood culture) -- "NeoLab - Zim"
    # "NeoLab - Test 1" (611abfa9) is an identical test copy and is excluded.
    # "xNeolab" (c076e5ab) is an older script with different key names and is excluded.
    neolab = list(
      SMCH = "2f771883-c473-488c-9d1e-9e054eaa93bb" # NeoLab - Zim
    ),
    # 28-day follow-up
    twenty_8_day_follow_up = list(
      SMCH = "9de01fe4-e18c-4051-83f6-90efa3354e13", # 28 Day Follow Up Form (SMCH)
      CPH  = "b3701e8c-61e3-457d-b96f-150c9603e4b2"  # 28 Day Follow Up Form (CPH)
    ),
    # Baseline data collection
    baseline = list(
      CPH  = "b3354f32-dd63-4a40-9c3d-5645581d39c7", # Chinhoyi Baseline
      BPH  = "047db8ad-f921-4d14-b4b1-ed500d0df805"  # Bindura Baseline Data Collection
    )
  ),
  MWI = list(
    admissions = list(
      KCH = "c04f628d-3d1a-46f1-8d9a-14c203a45463", # Neotree Admission (KCH)
      KDH = "fa11721e-b8d9-4884-9d6e-dbe586eefb48" # Kasungu District Hospital Neotree Admission
    ),
    discharges = list(
      KCH = "d02ca53d-d4bc-41a3-83dd-9dc29f3f83b4", # NeoDischarge (KCH)
      KDH = "388f5990-1a25-46ed-bb27-49a71cde88ad" # Kasungu District Hospital Neotree Discharge
    ),
    maternal_outcomes = list(
      KCH_retro = "1630f7ea-1e2d-45e6-ba0a-01f16de5b456", # Maternal Outcomes (Retrospective Data)
      KCH_dhis2 = "f1e2757a-e12c-47f5-8949-007bbb883c75" # DHIS2 Mat Outcomes (Retro Data)
    ),
    # Neolab (blood culture) -- "NeoLab - Malawi"
    neolab = list(
      KCH = "a5085256-3514-4be3-bf40-56074cd92e3f" # NeoLab - Malawi
    )
  )
)

# normalise_dataset_name: map pipeline dataset aliases to the keys above
normalise_dataset_name <- function(dataset) {
  d <- tolower(trimws(dataset))
  if (d %in% c(
    "combined_maternity_outcomes", "dhis2_maternal_outcomes",
    "maternal_outcomes", "maternity_completeness"
  )) {
    return("maternal_outcomes")
  }
  # "infections" is the pipeline dataset name for blood-culture / NeoLab data
  if (d == "infections") return("neolab")
  d
}


# =============================================================================
# SECTION 2 -- HELPER FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# build_script_index()
#
# Scans zim-scripts/ and mwi-scripts/ and returns a data.frame with one row
# per JSON file: script_id | title | hospital | path | country
# -----------------------------------------------------------------------------
build_script_index <- function(scripts_base) {
  subdirs <- list(
    ZIM = file.path(scripts_base, "zim-scripts"),
    MWI = file.path(scripts_base, "mwi-scripts")
  )

  all_rows <- list()

  for (ctry in names(subdirs)) {
    dir_path <- subdirs[[ctry]]
    if (!dir.exists(dir_path)) {
      message(sprintf("[00c]   Scripts subdir not found, skipping: %s", dir_path))
      next
    }
    json_files <- list.files(dir_path, pattern = "\\.json$", full.names = TRUE)

    for (fp in json_files) {
      obj <- tryCatch(
        fromJSON(fp, simplifyDataFrame = FALSE),
        error = function(e) {
          message(sprintf(
            "[00c]   Cannot parse JSON: %s  (%s)",
            basename(fp), conditionMessage(e)
          ))
          NULL
        }
      )
      if (is.null(obj)) next

      # Neotree scripts are exported as a single-element JSON array: [{...}].
      # Unwrap the outer array if present.
      if (is.list(obj) && !("scriptId" %in% names(obj)) && length(obj) >= 1L) {
        obj <- obj[[1L]]
      }

      all_rows[[length(all_rows) + 1L]] <- data.frame(
        script_id = obj$scriptId %||% NA_character_,
        title = obj$title %||% NA_character_,
        hospital = obj$hospitalName %||% NA_character_,
        path = fp,
        country = ctry,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(all_rows) == 0L) {
    return(data.frame(
      script_id = character(0), title    = character(0),
      hospital  = character(0), path     = character(0),
      country   = character(0),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, all_rows)
}


# -----------------------------------------------------------------------------
# get_script_ids_for_dict()
#
# Returns the script UUIDs whose fields are relevant to a given (country,
# dataset) dictionary, drawing from:
#   1. FACILITY_SCRIPT_MAP  -- facility-specific production scripts
#   2. Generic PHC scripts found by title keyword (for phc_* datasets)
# -----------------------------------------------------------------------------
get_script_ids_for_dict <- function(country, dataset, script_index) {
  ds <- normalise_dataset_name(dataset)
  ctry <- toupper(country)

  # Facility map entries for this country + normalised dataset
  map_ds <- FACILITY_SCRIPT_MAP[[ctry]][[ds]]
  ids <- if (!is.null(map_ds)) unlist(map_ds, use.names = FALSE) else character(0)

  # PHC datasets: supplement with any Generic PHC scripts found by title keyword
  if (grepl("phc", dataset, ignore.case = TRUE) && nrow(script_index) > 0L) {
    type_pat <- if (grepl("admis", dataset, ignore.case = TRUE)) "admis" else "disch"
    phc_rows <- script_index[
      script_index$country == ctry &
        grepl("PHC|primary.*health", script_index$title, ignore.case = TRUE) &
        grepl(type_pat, script_index$title, ignore.case = TRUE),
    ]
    if (nrow(phc_rows) > 0L) ids <- c(ids, phc_rows$script_id)
  }

  unique(ids[!is.na(ids) & nzchar(trimws(ids))])
}


# -----------------------------------------------------------------------------
# parse_script_fields()
#
# Parses every screen -> field from a single script JSON and returns a
# data.frame with one row per field occurrence:
#
#   key | display_label | optional | skip_condition | options_str
#
# skip_condition combines the screen-level and field-level condition
# expressions.  If both are present and distinct, they are joined with AND.
# If they are identical (Neotree sometimes duplicates them), only one is kept.
#
# options_str encodes the field's answer options as "val1|label1;val2|label2;"
# for later comparison against the dictionary ValueMaps sheet.
# -----------------------------------------------------------------------------
parse_script_fields <- function(json_path) {
  obj <- tryCatch(
    fromJSON(json_path, simplifyDataFrame = FALSE),
    error = function(e) NULL
  )
  if (is.null(obj)) {
    return(NULL)
  }
  if (is.list(obj) && !("screens" %in% names(obj)) && length(obj) >= 1L) {
    obj <- obj[[1L]]
  }

  screens <- obj$screens
  if (is.null(screens) || length(screens) == 0L) {
    return(NULL)
  }

  all_rows <- vector("list", 512L)
  n <- 0L

  for (scr in screens) {
    scr_cond <- trimws(scr$condition %||% "")

    for (fld in scr$fields %||% list()) {
      fld_key <- trimws(fld$key %||% "")
      if (!nzchar(fld_key)) next

      fld_cond <- trimws(fld$condition %||% "")

      # Combine conditions; deduplicate when screen and field share the same
      # expression (Neotree sometimes stores the same condition at both levels)
      skip_cond <- if (nzchar(fld_cond) && nzchar(scr_cond) && fld_cond != scr_cond) {
        paste0("(", scr_cond, ") AND (", fld_cond, ")")
      } else if (nzchar(fld_cond)) {
        fld_cond
      } else {
        scr_cond
      }

      opts <- fld$options %||% list()
      opts_str <- if (length(opts) > 0L) {
        paste(
          vapply(
            opts, function(o) {
              paste0(
                trimws(o$value %||% ""), "|",
                trimws(o$valueLabel %||% "")
              )
            },
            character(1L)
          ),
          collapse = ";"
        )
      } else {
        ""
      }

      n <- n + 1L
      all_rows[[n]] <- data.frame(
        key = fld_key,
        display_label = trimws(fld$label %||% ""),
        optional = as.logical(fld$optional %||% NA),
        skip_condition = skip_cond,
        options_str = opts_str,
        stringsAsFactors = FALSE
      )
    }
  }

  if (n == 0L) {
    return(NULL)
  }
  do.call(rbind, all_rows[seq_len(n)])
}


# -----------------------------------------------------------------------------
# consolidate_field_info()
#
# Aggregates field metadata for one question_key across multiple scripts.
# Returns a one-row data.frame with the modal (most common) values.
#
#   display_label  -- most frequently occurring non-empty label
#   optional       -- single value when all scripts agree; NA when they differ
#   skip_condition -- most frequently occurring non-empty expression
#   options_str    -- most frequently occurring non-empty value (for valuemap_check)
# -----------------------------------------------------------------------------
consolidate_field_info <- function(field_rows) {
  mode_str <- function(v) {
    v <- v[nzchar(v)]
    if (length(v) == 0L) {
      return(NA_character_)
    }
    names(sort(table(v), decreasing = TRUE))[[1L]]
  }

  labels <- field_rows$display_label
  opt_vals <- unique(na.omit(field_rows$optional))

  data.frame(
    display_label = mode_str(labels),
    optional = if (length(opt_vals) == 1L) opt_vals[[1L]] else NA,
    skip_condition = {
      s <- mode_str(field_rows$skip_condition)
      if (is.na(s)) "" else s
    },
    options_str = {
      s <- mode_str(field_rows$options_str)
      if (is.na(s)) "" else s
    },
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# check_valuemap()
#
# Compares a script field's coded answer options against the corresponding
# dictionary ValueMaps rows for the same question_key.
#
# Returns TRUE (sets differ -- worth reviewing), FALSE (sets match),
# or NA (comparison not possible, e.g. free-text / numeric field).
# -----------------------------------------------------------------------------
check_valuemap <- function(question_key, options_str, dict_valuemaps) {
  dict_rows <- dict_valuemaps[dict_valuemaps$question_key == question_key, ]
  has_dict <- nrow(dict_rows) > 0L
  has_script <- nzchar(trimws(options_str))

  if (!has_dict && !has_script) {
    return(NA)
  }
  if (!has_script) {
    return(NA)
  } # nothing to compare

  # Parse coded values from "val|label;val|label;..."
  parts <- strsplit(trimws(options_str), ";", fixed = TRUE)[[1L]]
  parts <- parts[nzchar(trimws(parts))]
  script_codes <- trimws(vapply(
    strsplit(parts, "|", fixed = TRUE), `[[`, character(1L), 1L
  ))
  script_codes <- script_codes[nzchar(script_codes)]

  if (!has_dict) {
    return(TRUE)
  } # script has options but dictionary has none

  dict_codes <- trimws(as.character(dict_rows$raw_code))
  dict_codes <- dict_codes[nzchar(dict_codes)]

  !setequal(script_codes, dict_codes)
}


# =============================================================================
# SECTION 3 -- MAIN ENRICHMENT LOOP
# =============================================================================

message("[00c] Neotree Dictionary Enrichment from Script JSONs")
message(sprintf("[00c]   Scripts dir : %s", NEOTREE_SCRIPTS_BASE))
message(sprintf("[00c]   Dict dir    : %s", DICT_DIR))
message("")

# Locate dictionary files
if (!dir.exists(DICT_DIR)) {
  stop(sprintf(
    "[00c] Dictionary directory not found: %s\n",
    "       Run 00_build_dictionary_v8.r first to generate the .xlsx files."
  ))
}

if (!dir.exists(NEOTREE_SCRIPTS_BASE)) {
  stop(sprintf(
    "[00c] Neotree scripts directory not found: %s\n%s",
    NEOTREE_SCRIPTS_BASE,
    "       Download the script JSONs from the Neotree web editor first."
  ))
}

# Build index of all script JSONs
message("[00c] Building script index...")
script_index <- build_script_index(NEOTREE_SCRIPTS_BASE)

if (nrow(script_index) == 0L) {
  stop("[00c] No script JSONs found in neotree_scripts/. Enrichment cannot proceed.")
}

message(sprintf(
  "[00c] Found %d script JSON(s) across %d country dir(s).",
  nrow(script_index), length(unique(script_index$country))
))

# Locate dictionary files (exclude any _enriched copies from prior runs)
dict_files <- sort(list.files(
  DICT_DIR,
  pattern    = "^dictionary_.*\\.xlsx$",
  full.names = TRUE
))
dict_files <- dict_files[!grepl("_enriched\\.xlsx$", dict_files)]

if (length(dict_files) == 0L) {
  stop(sprintf(
    "[00c] No dictionary .xlsx files found in '%s'.\n       Run 00_build_dictionary_v8.r first.",
    DICT_DIR
  ))
}

message(sprintf("[00c] Enriching %d dictionary file(s)...\n", length(dict_files)))

for (dict_path in dict_files) {
  dict_name <- basename(dict_path)
  message(sprintf("[00c] -- %s", dict_name))

  # ---- 1. Parse country + dataset from filename ----------------------------
  # Pattern: dictionary_<country>_<dataset>.xlsx
  stem <- sub("\\.xlsx$", "", sub("^dictionary_", "", dict_name))
  parts <- strsplit(stem, "_")[[1L]]

  if (length(parts) < 2L) {
    message("[00c]    Skipping -- cannot parse country/dataset from filename.")
    next
  }

  country <- toupper(parts[[1L]])
  dataset <- paste(parts[-1L], collapse = "_")
  message(sprintf("[00c]    Country: %s | Dataset: %s", country, dataset))

  # ---- 2. Identify relevant script UUIDs ----------------------------------
  script_ids <- get_script_ids_for_dict(country, dataset, script_index)

  if (length(script_ids) == 0L) {
    message("[00c]    No matching scripts in FACILITY_SCRIPT_MAP -- skipping.")
    next
  }

  script_paths <- script_index$path[script_index$script_id %in% script_ids]

  if (length(script_paths) == 0L) {
    message("[00c]    Script UUIDs resolved but no JSON files matched -- skipping.")
    next
  }
  message(sprintf("[00c]    Matched %d script JSON(s).", length(script_paths)))

  # ---- 3. Parse fields from all relevant scripts --------------------------
  field_list <- Filter(Negate(is.null), lapply(script_paths, parse_script_fields))

  if (length(field_list) == 0L) {
    message("[00c]    No fields could be parsed from scripts -- skipping.")
    next
  }

  all_fields <- do.call(rbind, field_list)

  # Normalise field keys to lowercase to match dictionary question_key format.
  # Script JSON keys use the original camelCase  (e.g. "Org1", "BCResult")
  # while the pipeline dictionary stores lowercase keys ("org1", "bcresult").
  # Without this step, match() in step 7 always returns NA and no variables
  # are enriched.
  all_fields$key <- tolower(all_fields$key)

  message(sprintf(
    "[00c]    Parsed %d field occurrence(s) across %d script(s).",
    nrow(all_fields), length(field_list)
  ))

  # ---- 4. Load dictionary workbook ----------------------------------------
  wb <- tryCatch(
    loadWorkbook(dict_path),
    error = function(e) {
      message(sprintf("[00c]    Cannot load workbook: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(wb)) next

  vars_df <- tryCatch(
    read.xlsx(wb, sheet = "Variables"),
    error = function(e) {
      message(sprintf("[00c]    Cannot read Variables sheet: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(vars_df) || nrow(vars_df) == 0L || !"question_key" %in% names(vars_df)) {
    message("[00c]    Variables sheet is missing or has no question_key column -- skipping.")
    next
  }

  maps_df <- tryCatch(
    read.xlsx(wb, sheet = "ValueMaps"),
    error = function(e) {
      data.frame(
        question_key = character(0), raw_code = character(0),
        stringsAsFactors = FALSE
      )
    }
  )

  # ---- 5. Consolidate field info per unique question_key ------------------
  unique_keys <- unique(all_fields$key)

  cons_df <- do.call(rbind, lapply(unique_keys, function(k) {
    res <- consolidate_field_info(all_fields[all_fields$key == k, ])
    res$question_key <- k
    res
  }))
  # cons_df columns: question_key | display_label | optional | skip_condition | options_str

  # ---- 6. Initialise enrichment columns in vars_df (preserve on re-run) ---
  new_col_names <- c("display_label", "optional", "skip_condition", "valuemap_check")
  for (col in new_col_names) {
    if (!col %in% colnames(vars_df)) vars_df[[col]] <- NA
  }

  # ---- 7. Fill enrichment columns -----------------------------------------
  matched <- 0L
  for (i in seq_len(nrow(vars_df))) {
    qk <- vars_df$question_key[[i]]
    idx <- match(qk, cons_df$question_key)
    if (is.na(idx)) next

    fi <- cons_df[idx, ]
    vars_df$display_label[[i]] <- fi$display_label
    vars_df$optional[[i]] <- fi$optional
    vars_df$skip_condition[[i]] <- fi$skip_condition
    vars_df$valuemap_check[[i]] <- check_valuemap(qk, fi$options_str, maps_df)
    matched <- matched + 1L
  }

  n_not_found <- nrow(vars_df) - matched
  n_flagged <- sum(vars_df$valuemap_check %in% TRUE)
  message(sprintf(
    "[00c]    Enriched %d / %d variables (%d not found in scripts).",
    matched, nrow(vars_df), n_not_found
  ))
  if (n_flagged > 0L) {
    message(sprintf(
      "[00c]    valuemap_check: %d variable(s) flagged with option mismatches.",
      n_flagged
    ))
  }

  # ---- 8. Write enrichment columns back to workbook -----------------------
  # Targeted cell writes: only the four new columns are touched; all existing
  # columns and their styles are left undisturbed.  Re-runs safely refresh.
  cur_headers <- names(read.xlsx(wb, sheet = "Variables"))

  for (col_name in new_col_names) {
    if (col_name %in% cur_headers) {
      col_idx <- which(cur_headers == col_name)[[1L]]
    } else {
      col_idx <- length(cur_headers) + 1L
      # Write the new column header into row 1
      writeData(wb,
        sheet = "Variables",
        x = col_name,
        startRow = 1L,
        startCol = col_idx,
        colNames = FALSE
      )
      cur_headers <- c(cur_headers, col_name)
    }
    # Write column values (row 2 onwards, below the header)
    writeData(wb,
      sheet = "Variables",
      x = data.frame(v = vars_df[[col_name]], stringsAsFactors = FALSE),
      startRow = 2L,
      startCol = col_idx,
      colNames = FALSE
    )
  }

  # ---- 9. Save ------------------------------------------------------------
  out_path <- if (OVERWRITE_IN_PLACE) {
    dict_path
  } else {
    sub("\\.xlsx$", "_enriched.xlsx", dict_path)
  }

  tryCatch(
    saveWorkbook(wb, out_path, overwrite = TRUE),
    error = function(e) message(sprintf("[00c]    ERROR saving workbook: %s", conditionMessage(e)))
  )
  message(sprintf("[00c]    Saved: %s", basename(out_path)))
}

message("\n[00c] Dictionary enrichment complete.")
