# =============================================================================
# NEOTREE CLEANING PIPELINE -- PRE-PIPELINE SETUP SCRIPT  (step 3 of 3)
# Module 00d: Build Researcher User Dictionary
# =============================================================================
#
# PURPOSE:
#   Generates a clean, researcher-facing data dictionary derived primarily from
#   the Neotree script JSON metadata, supplemented by the pipeline cleaning
#   dictionaries for data types, plausible ranges, harmonised variable names,
#   and exclusion flags.
#
#   NOTE (2026-06): The legacy, hand-maintained og_dictionaries dependency has
#   been removed. All content now derives solely from the web-editor downloads
#   (data keys + Neotree script JSON) and the pipeline cleaning dictionaries
#   built from them. og_dictionaries/ is no longer read by this script.
#
#   Outputs:
#     - One Excel workbook per country (ZIM, MWI) containing:
#         About        -- generated date and reference to NA Codes sheet
#         <Dataset>    -- one sheet per dataset (Admissions, Discharges, etc.)
#         Master       -- all unique variables across datasets, in screen order
#         NA Codes     -- two-section legend:
#                         (1) numeric sentinel codes -6 to -9 with Priority column
#                         (2) raw string codes from data collectors (NK, UNK, NR, etc.)
#                         + footer note on when each type appears and how to filter
#
#   Output files produced (example for ZIM):
#     user_dictionaries/neotree_user_dict_zim.xlsx
#
# COLUMNS IN EACH SHEET:
#   Description      Human-readable field label from Neotree script / pipeline dict
#   Variable Name    Harmonised column name (or question_key if none assigned)
#   Type             Numeric / Boolean / Categorical / Text / Date-time
#   Values / Codes   Range for numerics; code=label pairs for categorical/boolean
#   NA Codes         Which NA sentinel values may appear for this variable
#   Available also in  Other datasets (same country) that also contain this field
#
# PRIMARY SOURCES (in priority order):
#   1. Neotree script JSON metadata  -- field labels, screen sections, ordering,
#                                       skip conditions, option codes/labels
#   2. Pipeline cleaning dictionaries -- r_type, plausible ranges, harmonised
#                                       names, pii_tier, use_in_analysis flags,
#                                       pipeline ValueMaps (curated option codes),
#                                       display_label (from 00c enrichment)
#
# VARIABLE EXCLUSIONS:
#   pii_tier == "1"        -- column removed entirely from cleaned data
#   use_in_analysis == FALSE -- column not included in pipeline output
#
# HOW TO RUN:
#   # From the pipeline root (cleaning_pipeline_4DSH/):
#   source("00_build_dictionary/00d_build_user_dictionary.r")
#   # or:
#   Rscript 00_build_dictionary/00d_build_user_dictionary.r
#
# WHEN TO RE-RUN:
#   - New Neotree scripts are downloaded to neotree_scripts/
#   - Pipeline dictionaries are updated (00_build_dictionary_v8.r re-run)
#
# STANDALONE: No pipeline dependencies. Requires: openxlsx, jsonlite.
# =============================================================================

# =============================================================================
# SECTION 0 -- USER CONFIG
# =============================================================================
# All paths relative to the pipeline root (cleaning_pipeline_4DSH/).

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

NEOTREE_SCRIPTS_BASE <- "neotree_scripts"          # zim-scripts/ mwi-scripts/
DICT_DIR             <- "dictionaries"             # pipeline cleaning dicts
OUTPUT_DIR           <- "user_dictionaries"        # output folder (created if absent)

# Use *_enriched.xlsx pipeline dicts when available (adds display_label,
# skip_condition from 00c).  Falls back to base *.xlsx if not found.
USE_ENRICHED_DICT    <- TRUE

# Derived variables computed by the cleaning pipeline (Module 15).  They are
# absent from the Neotree script JSONs, so the JSON-driven consensus order does
# not include them; they are surfaced into the user dictionary explicitly from
# the pipeline cleaning dictionaries' Variables sheet (where 00_build_dictionary
# registers them via DERIVED_VARIABLES).  See cleaning_pipeline readme.md.
DERIVED_KEYS <- c("birthweight_g", "admission_weight_g", "discharge_weight_g")

# =============================================================================
# SECTION 1 -- PACKAGES & NULL-COALESCING OPERATOR
# =============================================================================
suppressPackageStartupMessages({
  library(openxlsx)
  library(jsonlite)
})

# Returns a only if it is non-NULL and meaningful; else b.
# Safe for list values: skips the is.na() check for lists (which would return
# a multi-element logical vector and trigger "condition has length > 1").
`%||%` <- function(a, b) {
  if (is.null(a)) return(b)
  if (is.list(a)) {
    if (length(a) == 0L) return(b)
    return(a)      # non-empty list: return as-is
  }
  if (length(a) == 0L) return(b)
  a1 <- a[[1L]]
  if (isTRUE(is.na(a1))) return(b)
  if (is.character(a1) && !nzchar(trimws(a1))) return(b)
  a
}

# Safely extract a single character scalar from a JSON field (which may be
# NULL, NA, empty, or occasionally a length->1 vector from jsonlite).
chr1 <- function(x, default = "") {
  if (is.null(x) || is.list(x) || length(x) == 0L) return(default)
  v <- trimws(as.character(x[[1L]]))
  if (is.na(v) || !nzchar(v)) return(default)
  v
}

# =============================================================================
# SECTION 2 -- FACILITY -> SCRIPT UUID MAP
# =============================================================================
# Mirrors 16_na_reason_coding/helpers/03_facility_script_map.r and
# 00c_enrich_dictionary_from_scripts.r.
# IMPORTANT: update all three files when Neotree scripts change.

FACILITY_SCRIPT_MAP <- list(
  ZIM = list(
    admissions = list(
      SMCH = "e7da1901-f1c3-43ca-abf9-a7cd01c922b0",
      CPH  = "0ccf5891-1672-4aa0-8d92-796c22d283d7",
      BPH  = "40eefcd8-42c1-4c4f-9b5d-3f391e1438d0",
      PGH  = "683d8b08-1e6d-4694-87b3-c3d8b9dc557b"
    ),
    discharges = list(
      SMCH = "6e774101-841c-4388-ad11-033ff7028daa",
      CPH  = "a0372aa9-f53d-4038-b5c0-62b4d4327b87",
      BPH  = "6364caaa-7899-47b9-975e-f05151e4e13c",
      PGH  = "aea9db53-b185-46c1-84cf-9243f87cc246"
    ),
    maternal_outcomes = list(
      SMCH = "9df77822-b8ff-43e6-8c3a-c455e9cf4a02",
      CPH  = "fd81a5ac-cece-487c-8737-c98cfd046be1",
      BPH  = "4e69e777-f680-4615-9bbe-fad81d85d6cd"
    ),
    # Neolab (blood culture) -- primary production script: "NeoLab - Zim"
    # "NeoLab - Test 1" (611abfa9) is an identical test copy; not listed here
    # to avoid duplicating field entries.  "xNeolab" (c076e5ab) is an older
    # script with different key names and is excluded deliberately.
    neolab = list(SMCH = "2f771883-c473-488c-9d1e-9e054eaa93bb"),
    # 28-day follow-up
    twenty_8_day_follow_up = list(
      SMCH = "9de01fe4-e18c-4051-83f6-90efa3354e13",  # 28 Day Follow Up Form (SMCH)
      CPH  = "b3701e8c-61e3-457d-b96f-150c9603e4b2"   # 28 Day Follow Up Form (CPH)
    ),
    # Baseline data collection
    baseline = list(
      CPH  = "b3354f32-dd63-4a40-9c3d-5645581d39c7",  # Chinhoyi Baseline
      BPH  = "047db8ad-f921-4d14-b4b1-ed500d0df805"   # Bindura Baseline Data Collection
    )
  ),
  MWI = list(
    admissions = list(
      KCH = "c04f628d-3d1a-46f1-8d9a-14c203a45463",
      KDH = "fa11721e-b8d9-4884-9d6e-dbe586eefb48"
    ),
    discharges = list(
      KCH = "d02ca53d-d4bc-41a3-83dd-9dc29f3f83b4",
      KDH = "388f5990-1a25-46ed-bb27-49a71cde88ad"
    ),
    maternal_outcomes = list(
      KCH = "1630f7ea-1e2d-45e6-ba0a-01f16de5b456"
    ),
    combined_maternity_outcomes = list(
      KCH = "1630f7ea-1e2d-45e6-ba0a-01f16de5b456"
    ),
    dhis2_maternal_outcomes = list(
      KCH_dhis2 = "f1e2757a-e12c-47f5-8949-007bbb883c75"
    ),
    phc_admissions = list(PHC = "88e3dfc6-218c-4d72-8d24-190acc31a77f"),  # Generic PHC Admission (Bua)
    phc_discharges = list(
      PHC  = "11c3eac9-456f-4dbf-9580-14908e4be942",  # Generic PHC Discharge (Bua)
      PHC2 = "465d856a-848f-4026-aff5-f1bdea5c2425"   # NeoDischarge (PHC)
    ),
    # maternity_completeness: no dedicated script; use maternal outcomes as approximation
    maternity_completeness = list(KCH = "1630f7ea-1e2d-45e6-ba0a-01f16de5b456"),
    # Neolab (blood culture) -- "NeoLab - Malawi"
    neolab = list(KCH = "a5085256-3514-4be3-bf40-56074cd92e3f")
  )
)

PHC_ADMISSION_KW <- c("PHC", "Primary Health", "Primary health")
PHC_DISCHARGE_KW <- c("PHC Discharge", "PHC discharge", "PHC Generic Discharge")

# =============================================================================
# SECTION 3 -- SCRIPT INDEX & PARSING
# =============================================================================

#' Scan neotree_scripts/ subdirectories and index JSON files by scriptId.
#' Returns a named list: scriptId -> list(path, country, title)
build_script_index <- function(scripts_base) {
  index <- list()
  if (!dir.exists(scripts_base)) {
    warning(sprintf("neotree_scripts directory not found: %s", scripts_base))
    return(index)
  }
  for (country_dir in list.dirs(scripts_base, recursive = FALSE, full.names = TRUE)) {
    country <- toupper(sub("-scripts$", "", basename(country_dir), ignore.case = TRUE))
    jsons   <- list.files(country_dir, pattern = "\\.json$", full.names = TRUE,
                          recursive = FALSE)
    for (p in jsons) {
      tryCatch({
        raw  <- fromJSON(p, simplifyVector = FALSE)
        scr  <- if (is.list(raw) && length(raw) > 0L && is.list(raw[[1L]])) raw[[1L]] else raw
        sid  <- chr1(scr$scriptId)
        if (nzchar(sid)) {
          ttl <- chr1(scr$title)
          index[[sid]] <- list(path    = p,
                               country = country,
                               title   = if (nzchar(ttl)) ttl else basename(p))
        }
      }, error = function(e) NULL)
    }
  }
  index
}

#' Return ordered script UUIDs for a country/dataset combination.
#' The first UUID in the returned vector is treated as the primary (reference)
#' script; subsequent UUIDs supplement it for cross-hospital coverage.
get_script_ids_for_dataset <- function(country, dataset, script_index) {
  ctry  <- toupper(trimws(country))
  ds    <- tolower(trimws(dataset))

  # Normalise dataset key to map keys
  ds_key <- ds
  if (grepl("phc_admission",            ds)) ds_key <- "phc_admissions"
  if (grepl("phc_discharge",            ds)) ds_key <- "phc_discharges"
  if (grepl("combined_maternity",       ds)) ds_key <- "combined_maternity_outcomes"
  if (grepl("dhis2_maternal",           ds)) ds_key <- "dhis2_maternal_outcomes"
  # "infections" is the pipeline dataset name for blood-culture / NeoLab data
  if (ds == "infections")                    ds_key <- "neolab"
  # "maternity_completeness" has no dedicated script; use maternal outcomes scripts
  if (ds == "maternity_completeness")        ds_key <- "maternity_completeness"

  ids <- character(0)
  map <- FACILITY_SCRIPT_MAP[[ctry]]
  if (!is.null(map)) {
    ds_map <- map[[ds_key]]
    if (!is.null(ds_map)) ids <- unname(unlist(ds_map))
  }

  # PHC fallback: title keyword search
  if (length(ids) == 0 && ds_key == "phc_admissions") {
    for (sid in names(script_index)) {
      si <- script_index[[sid]]
      if (si$country == ctry &&
          any(sapply(PHC_ADMISSION_KW, grepl, si$title, ignore.case = TRUE)))
        ids <- c(ids, sid)
    }
  }
  if (length(ids) == 0 && ds_key == "phc_discharges") {
    for (sid in names(script_index)) {
      si <- script_index[[sid]]
      if (si$country == ctry &&
          any(sapply(PHC_DISCHARGE_KW, grepl, si$title, ignore.case = TRUE)))
        ids <- c(ids, sid)
    }
  }

  unique(ids[ids %in% names(script_index)])
}

#' Parse a single JSON script file into a data.frame of fields.
#' Returns: question_key | screen_title | screen_idx | field_idx |
#'          json_label | skip_condition | optional | json_options_str
parse_script_fields_ordered <- function(json_path) {
  tryCatch({
    raw    <- fromJSON(json_path, simplifyVector = FALSE)
    script <- if (is.list(raw) && length(raw) > 0L && is.list(raw[[1L]])) raw[[1L]] else raw

    # Safely retrieve screens: must be a non-empty list
    screens <- script$screens
    if (!is.list(screens) || length(screens) == 0L) return(NULL)
    rows <- list()

    for (s_idx in seq_along(screens)) {
      scr <- screens[[s_idx]]
      if (!is.list(scr)) next

      scr_title <- chr1(scr$title)
      if (!nzchar(scr_title)) scr_title <- chr1(scr$ref)
      if (!nzchar(scr_title)) scr_title <- sprintf("Screen %d", s_idx)
      scr_cond  <- chr1(scr$condition)

      # Safely retrieve fields: must be a list
      fields <- scr$fields
      if (!is.list(fields) || length(fields) == 0L) next

      for (f_idx in seq_along(fields)) {
        fld     <- fields[[f_idx]]
        if (!is.list(fld)) next
        fld_key <- tolower(chr1(fld$key))
        if (!nzchar(fld_key)) next

        fld_cond  <- chr1(fld$condition)
        skip_cond <- if (nzchar(fld_cond) && nzchar(scr_cond) && fld_cond != scr_cond) {
          paste0("(", scr_cond, ") AND (", fld_cond, ")")
        } else if (nzchar(fld_cond)) {
          fld_cond
        } else {
          scr_cond
        }

        # Encode JSON options as "CODE=Label; CODE=Label" string
        opts     <- fld$options
        opts_str <- if (is.list(opts) && length(opts) > 0L) {
          paste(sapply(opts, function(o) {
            sprintf("%s=%s", chr1(o$value), chr1(o$valueLabel))
          }), collapse = "; ")
        } else ""

        rows[[length(rows) + 1L]] <- data.frame(
          question_key     = fld_key,
          screen_title     = scr_title,
          screen_idx       = s_idx,
          field_idx        = f_idx,
          json_label       = chr1(fld$label),
          skip_condition   = skip_cond,
          optional         = isTRUE(fld$optional),
          json_options_str = opts_str,
          stringsAsFactors = FALSE
        )
      }
    }

    if (length(rows) == 0L) return(NULL)
    do.call(rbind, rows)

  }, error = function(e) {
    message(sprintf("    Warning: could not parse %s: %s",
                    basename(json_path), conditionMessage(e)))
    NULL
  })
}

#' Consolidate field info across multiple scripts (modal values per question_key).
#' Returns a data.frame sorted by consensus screen_idx, field_idx.
build_consensus_order <- function(script_ids, script_index) {
  all_rows <- lapply(script_ids, function(sid) {
    info <- script_index[[sid]]
    if (is.null(info)) return(NULL)
    parse_script_fields_ordered(info$path)
  })
  all_rows <- Filter(Negate(is.null), all_rows)
  if (length(all_rows) == 0) return(NULL)

  combined <- do.call(rbind, all_rows)

  agg <- lapply(split(combined, combined$question_key), function(rows) {
    # Modal screen title
    scr_titles <- rows$screen_title[nzchar(rows$screen_title)]
    modal_scr  <- if (length(scr_titles) == 0) "Other" else {
      tt <- table(scr_titles); names(tt)[which.max(tt)]
    }
    # Modal screen_idx for that title
    modal_scr_idx <- min(rows$screen_idx[rows$screen_title == modal_scr], na.rm = TRUE)

    # Best json_label (first non-empty)
    labels <- rows$json_label[nzchar(trimws(rows$json_label))]
    best_label <- if (length(labels) == 0) NA_character_ else labels[1]

    # Best skip_condition (first non-empty)
    skips <- rows$skip_condition[nzchar(trimws(rows$skip_condition))]
    best_skip <- if (length(skips) == 0) NA_character_ else skips[1]

    # Best json_options_str (most detailed non-empty)
    opts <- rows$json_options_str[nzchar(trimws(rows$json_options_str))]
    best_opts <- if (length(opts) == 0) "" else opts[nchar(opts) == max(nchar(opts))][1]

    data.frame(
      question_key     = rows$question_key[1],
      screen_title     = modal_scr,
      screen_idx       = modal_scr_idx,
      field_idx        = min(rows$field_idx),
      json_label       = best_label,
      skip_condition   = best_skip,
      optional         = any(rows$optional, na.rm = TRUE),
      json_options_str = best_opts,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, agg)
  result[order(result$screen_idx, result$field_idx), ]
}

# =============================================================================
# SECTION 5 -- PIPELINE DICTIONARY METADATA LOOKUP
# =============================================================================

#' Load pipeline cleaning dictionary for a country/dataset.
#' Returns list(vars_df, maps_df) or NULL if not found.
#' Prefers *_enriched.xlsx; falls back to base *.xlsx.
load_pipeline_dict <- function(country, dataset, dict_dir, use_enriched = TRUE) {
  ctry_lc <- tolower(trimws(country))
  ds_lc   <- tolower(trimws(dataset))

  enr_path  <- file.path(dict_dir,
                         sprintf("dictionary_%s_%s_enriched.xlsx", ctry_lc, ds_lc))
  base_path <- file.path(dict_dir,
                         sprintf("dictionary_%s_%s.xlsx",          ctry_lc, ds_lc))

  path <- if (use_enriched && file.exists(enr_path)) enr_path else base_path
  if (!file.exists(path)) return(NULL)

  vars <- tryCatch(read.xlsx(path, sheet = "Variables"), error = function(e) NULL)
  maps <- tryCatch(read.xlsx(path, sheet = "ValueMaps"),  error = function(e) NULL)

  if (is.null(vars)) return(NULL)
  list(vars = vars, maps = maps)
}

#' Build a quick-lookup list from the pipeline Variables data.frame.
#' Returns a named list: question_key -> named list of column values.
build_pipeline_meta_lookup <- function(vars_df) {
  meta_cols <- c("r_type", "suggested_plausible_min", "suggested_plausible_max",
                 "harmonised_variable_name", "pii_tier", "use_in_analysis",
                 "record_id_role", "linkage_role", "weight_unit",
                 "display_label", "skip_condition", "variable_label")
  present   <- intersect(meta_cols, names(vars_df))

  lookup <- list()
  for (i in seq_len(nrow(vars_df))) {
    row <- as.list(vars_df[i, present, drop = FALSE])
    lookup[[tolower(trimws(vars_df$question_key[i]))]] <- row
  }
  lookup
}

#' Check if a variable should be excluded from the user dictionary.
is_excluded <- function(meta) {
  if (is.null(meta)) return(FALSE)
  pii_tier <- as.character(meta$pii_tier %||% "")
  if (!is.na(pii_tier) && nzchar(pii_tier) && pii_tier == "1") return(TRUE)
  ua <- meta$use_in_analysis
  if (!is.null(ua) && !is.na(ua)) {
    ua_val <- suppressWarnings(as.logical(ua))
    if (isFALSE(ua_val)) return(TRUE)
  }
  FALSE
}

# =============================================================================
# SECTION 6 -- VALUE STRING & NA CODE BUILDERS
# =============================================================================

#' Produce the "Values / Codes" string for one variable.
build_values_string <- function(question_key, r_type, meta, maps_df, json_options_str) {
  rtype <- tolower(trimws(r_type %||% ""))

  if (rtype == "numeric") {
    pmin <- suppressWarnings(as.numeric(meta$suggested_plausible_min))
    pmax <- suppressWarnings(as.numeric(meta$suggested_plausible_max))
    if (!is.na(pmin) && !is.na(pmax))  return(sprintf("Range: %g to %g", pmin, pmax))
    if (!is.na(pmin))                  return(sprintf("Range: >= %g", pmin))
    if (!is.na(pmax))                  return(sprintf("Range: <= %g", pmax))
    return("Numeric value")
  }
  if (rtype == "datetime") return("Date / time value")
  if (rtype == "object")   return("Free text")

  # Boolean / Categorical: try pipeline ValueMaps first, then JSON options
  if (!is.null(maps_df) && nrow(maps_df) > 0) {
    opts <- maps_df[tolower(trimws(maps_df$question_key)) == question_key, , drop = FALSE]
    if (nrow(opts) > 0) {
      if ("option_order" %in% names(opts)) {
        ord  <- suppressWarnings(as.numeric(opts$option_order))
        opts <- opts[order(ord, na.last = TRUE), ]
      }
      codes  <- as.character(opts$raw_code %||% opts$canonical_code)
      labels <- as.character(opts$option_label)
      # Deduplicate: keep first occurrence of each code (multiple hospitals may
      # have the same code with slightly different label wording)
      seen   <- character(0)
      keep   <- logical(length(codes))
      for (k in seq_along(codes)) {
        if (!codes[k] %in% seen) { keep[k] <- TRUE; seen <- c(seen, codes[k]) }
      }
      return(paste(sprintf("%s = %s", codes[keep], labels[keep]), collapse = "\n"))
    }
  }

  # Fallback: parse JSON options string
  if (nzchar(trimws(json_options_str %||% ""))) {
    parts <- strsplit(json_options_str, "; ", fixed = TRUE)[[1]]
    lines <- sapply(parts, function(p) {
      kv <- strsplit(p, "=", fixed = TRUE)[[1]]
      if (length(kv) >= 2) sprintf("%s = %s", trimws(kv[1]), trimws(paste(kv[-1], collapse = "=")))
      else p
    })
    return(paste(lines, collapse = "\n"))
  }

  if (rtype == "boolean") return("true / false")
  ""
}

#' Produce the "NA Codes" string for one variable.
build_na_codes_string <- function(r_type, pii_tier, skip_condition) {
  rtype    <- tolower(trimws(r_type      %||% ""))
  pii      <- as.character(pii_tier     %||% "")
  skip_cnd <- as.character(skip_condition %||% "")

  codes <- "-9 (unknown / missing)"  # always applicable

  if (rtype %in% c("numeric", "boolean", "categorical", "datetime")) {
    codes <- paste(codes, "-8 (invalid / out of range)", sep = "\n")
  }
  if (!is.na(skip_cnd) && nzchar(trimws(skip_cnd))) {
    codes <- paste(codes, "-7 (not applicable, skip logic)", sep = "\n")
  }
  if (!is.na(pii) && nzchar(pii) && pii != "1" && rtype == "object") {
    codes <- paste(codes, "-6 (redacted, PII)", sep = "\n")
  }
  codes
}

#' Human-readable type label.
readable_type <- function(r_type) {
  switch(tolower(trimws(r_type %||% "")),
    numeric     = "Numeric",
    boolean     = "Boolean",
    categorical = "Categorical",
    object      = "Text",
    datetime    = "Date/time",
    ""
  )
}

# =============================================================================
# SECTION 7 -- DATASET CONFIGURATION
# =============================================================================

DATASET_CONFIGS <- list(
  # Each entry has:
  #   key   -- pipeline dataset key (used to load dictionaries and match scripts)
  #   label -- human-readable display label used in console output, section
  #             headers, and the "Available also in" cross-reference column
  #   sheet -- (optional) Excel tab name; defaults to label when absent.
  #             Set explicitly when the tab name must differ from the display
  #             label, e.g. for compatibility with downstream scripts that read
  #             the workbook by sheet name.
  ZIM = list(
    list(key = "admissions",              label = "Admissions"),
    list(key = "discharges",              label = "Discharges"),
    list(key = "maternal_outcomes",       label = "Maternal Outcomes"),
    list(key = "neolab",                  label = "Neolab"),
    list(key = "infections",              label = "Infections"),
    list(key = "baseline",                label = "Baseline"),
    list(key = "twenty_8_day_follow_up",  label = "28-Day Follow-Up")
    # ZIM PHC not yet included -- no PHC data collected for Zimbabwe
  ),
  MWI = list(
    list(key = "admissions",                  label = "Admissions"),
    list(key = "discharges",                  label = "Discharges"),
    list(key = "maternal_outcomes",           label = "Maternal Outcomes"),
    list(key = "phc_admissions",              label = "PHC Admissions"),
    list(key = "phc_discharges",              label = "PHC Discharges"),
    # sheet = "combined_maternity_outcomes" keeps the tab name compatible with
    # run_subsample_user_dict.R (which reads the sheet by that exact name),
    # while label = "Combined Maternity" is used for display.
    list(key   = "combined_maternity_outcomes",
         label = "Combined Maternity",
         sheet = "combined_maternity_outcomes"),
    list(key = "dhis2_maternal_outcomes",     label = "DHIS2 Maternal"),
    list(key = "maternity_completeness",      label = "Maternity Completeness"),
    list(key = "neolab",                      label = "Neolab")
  )
)

# =============================================================================
# SECTION 8 -- BUILD USER ROWS FOR ONE DATASET
# =============================================================================

#' Build the researcher-facing rows for one country/dataset.
#'
#' @param consensus      Output of build_consensus_order() -- field list from JSON
#' @param pipeline_meta  Named list from build_pipeline_meta_lookup()
#' @param maps_df        Pipeline ValueMaps data.frame (or NULL)
#' @param dataset_label  Human-readable sheet label (e.g. "Admissions")
#' @param avail_index    Named list: question_key -> vector of dataset labels
#'
#' @return data.frame with columns:
#'   section | description | variable_name | type |
#'   values_and_codes | na_codes | available_in
build_user_rows <- function(consensus, pipeline_meta,
                            maps_df, dataset_label, avail_index) {

  if (is.null(consensus) || nrow(consensus) == 0) return(NULL)

  # Apply pipeline exclusions & enrich each row
  output_rows <- list()

  for (i in seq_len(nrow(consensus))) {
    row  <- as.list(consensus[i, ])
    qkey <- row$question_key  # already lowercase
    meta <- pipeline_meta[[qkey]]

    # --- Exclusion filters ---------------------------------------------------
    if (is_excluded(meta)) next

    # --- Field metadata with fallback priority -------------------------------
    # Description: display_label (00c enrichment) > json_label >
    #              pipeline variable_label > qkey
    json_lbl <- trimws(as.character(row$json_label %||% ""))
    pipe_lbl <- trimws(as.character(meta$variable_label %||% ""))
    # Enriched dict's display_label (from 00c) takes highest priority
    enr_lbl  <- trimws(as.character(meta$display_label %||% ""))
    description <- if (nzchar(enr_lbl))  enr_lbl  else
                   if (nzchar(json_lbl)) json_lbl  else
                   if (nzchar(pipe_lbl)) pipe_lbl  else qkey

    # Variable name: harmonised name > question_key
    hvn  <- trimws(as.character(meta$harmonised_variable_name %||% ""))
    var_name <- if (nzchar(hvn)) hvn else qkey

    # Type
    r_type    <- as.character(meta$r_type %||% "")
    type_str  <- readable_type(r_type)

    # Skip condition: enriched dict's skip_condition > JSON skip_condition
    pipe_skip <- trimws(as.character(meta$skip_condition %||% ""))
    json_skip <- trimws(as.character(row$skip_condition  %||% ""))
    skip_cond <- if (nzchar(pipe_skip)) pipe_skip else if (nzchar(json_skip)) json_skip else ""

    # PII tier (for NA code logic)
    pii_tier  <- as.character(meta$pii_tier %||% "")

    # Values string
    val_str <- build_values_string(qkey, r_type, meta, maps_df,
                                   row$json_options_str %||% "")

    # NA codes
    na_str  <- build_na_codes_string(r_type, pii_tier, skip_cond)

    # Available in (other datasets)
    other_ds <- setdiff(avail_index[[qkey]], dataset_label)
    avail_str <- if (length(other_ds) == 0) "" else
                 paste(other_ds, collapse = ", ")

    # Section: admin override, then JSON screen_title
    is_admin <- {
      rid <- as.character(meta$record_id_role %||% "")
      lnk <- as.character(meta$linkage_role   %||% "")
      (!is.na(rid) && nzchar(rid)) || (!is.na(lnk) && nzchar(lnk))
    }
    section <- if (is_admin) "Administrative / System" else {
      trimws(row$screen_title %||% "Other")
    }
    if (!nzchar(section)) section <- "Other"

    output_rows[[length(output_rows) + 1L]] <- data.frame(
      section          = section,
      screen_idx       = if (is_admin) -1L else as.integer(row$screen_idx %||% 9999L),
      field_idx        = as.integer(row$field_idx %||% 9999L),
      description      = description,
      variable_name    = var_name,
      type             = type_str,
      values_and_codes = val_str,
      na_codes         = na_str,
      available_in     = avail_str,
      stringsAsFactors = FALSE
    )
  }

  # --- Append derived variables (computed by the cleaning pipeline; absent ----
  #     from the Neotree script JSONs, so the consensus loop above skips them).
  #     Pulled from the pipeline dictionary Variables sheet via pipeline_meta.
  already <- if (length(output_rows) > 0)
    vapply(output_rows, function(r) as.character(r$variable_name), character(1)) else character(0)
  dk_field <- 0L
  for (dk in DERIVED_KEYS) {
    meta <- pipeline_meta[[dk]]
    if (is.null(meta)) next            # not registered for this dataset
    if (is_excluded(meta)) next
    hvn      <- trimws(as.character(meta$harmonised_variable_name %||% ""))
    var_name <- if (nzchar(hvn)) hvn else dk
    if (var_name %in% already || dk %in% already) next
    dk_field <- dk_field + 1L
    r_type   <- as.character(meta$r_type %||% "")
    other_ds <- setdiff(avail_index[[dk]], dataset_label)
    output_rows[[length(output_rows) + 1L]] <- data.frame(
      section          = "Derived variables (computed by the cleaning pipeline)",
      screen_idx       = 99998L,                 # sort after all script-form screens
      field_idx        = dk_field,
      description      = trimws(as.character(meta$variable_label %||% dk)),
      variable_name    = var_name,
      type             = readable_type(r_type),
      values_and_codes = "",
      na_codes         = build_na_codes_string(r_type, as.character(meta$pii_tier %||% ""), ""),
      available_in     = if (length(other_ds) == 0) "" else paste(other_ds, collapse = ", "),
      stringsAsFactors = FALSE
    )
  }

  if (length(output_rows) == 0) return(NULL)
  result <- do.call(rbind, output_rows)
  result[order(result$screen_idx, result$field_idx), ]
}

# =============================================================================
# SECTION 9 -- EXCEL WORKBOOK HELPERS
# =============================================================================

# Column definitions ----------------------------------------------------------
DISPLAY_COL_NAMES  <- c("Description", "Variable Name", "Type",
                         "Values / Codes", "NA Codes", "Available also in")
DISPLAY_COL_WIDTHS <- c(40, 28, 12, 46, 34, 25)
DATA_COLS          <- c("description", "variable_name", "type",
                         "values_and_codes", "na_codes", "available_in")

# Styles (constructor functions — called per-use to avoid object mutation) -----
.sty_header <- function() createStyle(
  fontName = "Calibri", fontSize = 11, fontColour = "white",
  fgFill = "#2F5496", halign = "LEFT", valign = "CENTER",
  textDecoration = "bold", wrapText = TRUE
)
.sty_section <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fontColour = "#1F3864",
  fgFill = "#D9E1F2", halign = "LEFT", valign = "CENTER",
  textDecoration = "bold", wrapText = FALSE
)
.sty_data <- function() createStyle(
  fontName = "Calibri", fontSize = 10,
  halign = "LEFT", valign = "TOP", wrapText = TRUE
)
.sty_mono <- function() createStyle(
  fontName = "Courier New", fontSize = 10,
  halign = "LEFT", valign = "TOP", wrapText = TRUE
)
.sty_data_alt <- function() createStyle(
  fontName = "Calibri", fontSize = 10, fgFill = "#FAFAFA",
  halign = "LEFT", valign = "TOP", wrapText = TRUE
)
.sty_mono_alt <- function() createStyle(
  fontName = "Courier New", fontSize = 10, fgFill = "#FAFAFA",
  halign = "LEFT", valign = "TOP", wrapText = TRUE
)

#' Add one dataset sheet to the workbook.
add_dataset_sheet <- function(wb, sheet_name, user_rows) {
  addWorksheet(wb, sheet_name)

  # Header row
  hdr <- as.data.frame(t(DISPLAY_COL_NAMES), stringsAsFactors = FALSE)
  writeData(wb, sheet_name, x = hdr,
            startRow = 1, startCol = 1, colNames = FALSE)
  addStyle(wb, sheet_name, .sty_header(),
           rows = 1, cols = seq_along(DISPLAY_COL_NAMES), gridExpand = TRUE)
  setRowHeights(wb, sheet_name, rows = 1, heights = 26)

  if (is.null(user_rows) || nrow(user_rows) == 0) {
    setColWidths(wb, sheet_name, cols = seq_along(DISPLAY_COL_NAMES),
                 widths = DISPLAY_COL_WIDTHS)
    return(invisible(wb))
  }

  # Build ordered section list
  all_secs <- unique(user_rows$section)
  fixed_first <- intersect(c("Administrative / System"), all_secs)
  fixed_last  <- intersect(c("Other"), all_secs)
  middle      <- setdiff(all_secs, c(fixed_first, fixed_last))
  section_order <- c(fixed_first, middle, fixed_last)

  current_row <- 2L
  alt_toggle  <- FALSE  # for subtle row-striping within sections

  for (sec in section_order) {
    sec_rows <- user_rows[user_rows$section == sec, DATA_COLS, drop = FALSE]
    if (nrow(sec_rows) == 0) next

    # Section header
    mergeCells(wb, sheet_name,
               cols = seq_along(DISPLAY_COL_NAMES), rows = current_row)
    writeData(wb, sheet_name, x = sec,
              startRow = current_row, startCol = 1, colNames = FALSE)
    addStyle(wb, sheet_name, .sty_section(),
             rows = current_row, cols = seq_along(DISPLAY_COL_NAMES),
             gridExpand = TRUE)
    setRowHeights(wb, sheet_name, rows = current_row, heights = 17)
    current_row <- current_row + 1L
    alt_toggle  <- FALSE

    # Data rows
    writeData(wb, sheet_name, x = sec_rows,
              startRow = current_row, startCol = 1, colNames = FALSE)

    for (r_off in seq_len(nrow(sec_rows))) {
      r_abs   <- current_row + r_off - 1L
      ds_style <- if (alt_toggle) .sty_data_alt() else .sty_data()
      mn_style <- if (alt_toggle) .sty_mono_alt() else .sty_mono()
      alt_toggle <- !alt_toggle

      addStyle(wb, sheet_name, ds_style,
               rows = r_abs, cols = c(1, 3, 4, 5, 6), gridExpand = TRUE)
      addStyle(wb, sheet_name, mn_style,
               rows = r_abs, cols = 2, gridExpand = TRUE)

      # Approximate row height from content line count
      # Include values_and_codes, na_codes, and available_in (all can be multi-line)
      n_lines <- max(
        lengths(regmatches(sec_rows$values_and_codes[r_off],
                           gregexpr("\n", sec_rows$values_and_codes[r_off]))),
        lengths(regmatches(sec_rows$na_codes[r_off],
                           gregexpr("\n", sec_rows$na_codes[r_off]))),
        lengths(regmatches(sec_rows$available_in[r_off],
                           gregexpr("\n", sec_rows$available_in[r_off]))),
        0L
      ) + 1L
      setRowHeights(wb, sheet_name, rows = r_abs, heights = max(20L, n_lines * 15L))
    }

    current_row <- current_row + nrow(sec_rows)
  }

  freezePane(wb, sheet_name, firstRow = TRUE)
  setColWidths(wb, sheet_name, cols = seq_along(DISPLAY_COL_NAMES),
               widths = DISPLAY_COL_WIDTHS)
  invisible(wb)
}

#' Add the NA Codes legend sheet.
#' Two sections:
#'   1. Numeric sentinel codes (-6 to -9) used in cleaned / na_coded data files,
#'      with a Priority column indicating the hierarchy when multiple codes apply.
#'   2. String codes entered by data collectors in the raw Neotree form
#'      (NK, UNK, NR, REFUSED, etc.).
#' A footer note explains when each type appears and how to filter correctly.
add_na_legend_sheet <- function(wb) {
  sh <- "NA Codes"
  addWorksheet(wb, sh)
  setColWidths(wb, sh, cols = 1:3, widths = c(14, 62, 26))

  sty_note <- createStyle(
    fontName = "Calibri", fontSize = 10, fontColour = "#595959",
    wrapText = TRUE, valign = "top"
  )
  sty_code_num <- createStyle(
    fontName = "Courier New", fontSize = 10, fontColour = "#1F3864",
    halign = "center", valign = "top", wrapText = FALSE,
    textDecoration = "bold"
  )
  sty_priority <- createStyle(
    fontName = "Calibri", fontSize = 9, fontColour = "#767676",
    halign = "center", valign = "top", wrapText = FALSE
  )

  cur_row <- 1L

  # ── Column header ─────────────────────────────────────────────────────────
  writeData(wb, sh,
    x = data.frame(Code = "NA Code", Meaning = "Meaning / Context",
                   Notes = "Applies to / Priority",
                   stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, sh, .sty_header(), rows = cur_row, cols = 1:3, gridExpand = TRUE)
  setRowHeights(wb, sh, rows = cur_row, heights = 20)
  cur_row <- cur_row + 1L

  # ── Section 1: Numeric sentinel codes ─────────────────────────────────────
  writeData(wb, sh,
    x = data.frame(
      V1 = "Numeric codes — used in cleaned data files (replace all missing values)",
      V2 = "", V3 = "", stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, sh, .sty_section(), rows = cur_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, sh, cols = 1:3, rows = cur_row)
  setRowHeights(wb, sh, rows = cur_row, heights = 18)
  cur_row <- cur_row + 1L

  num_codes <- data.frame(
    Code = c("-6", "-7", "-8", "-9"),
    Meaning = c(
      "REDACTED — Value existed in the raw data but was removed because it matched a PII pattern (phone number, e-mail address, hospital ID, free-text containing identifying information, etc.).",
      "NOT APPLICABLE — The field was never shown to the data collector. The form's skip logic determined the field was not relevant for this patient or record type (e.g. discharge fields hidden for a Brought-In-Dead admission).",
      "INVALID / REMOVED — A value was present in the raw data but was removed by the cleaning pipeline (unrecognised code, failed type coercion, or out-of-range value based on clinically plausible limits).",
      "UNKNOWN — The raw cell was empty or contained a recognised missing-value placeholder (blank, nan, none, null, n/a, NK, UNK, NR, etc.)."
    ),
    Priority = c(
      "Priority 1 (highest)",
      "Priority 2",
      "Priority 3",
      "Priority 4 (default)"
    ),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(num_codes))) {
    writeData(wb, sh,
      x = data.frame(
        Code     = num_codes$Code[i],
        Meaning  = num_codes$Meaning[i],
        Priority = num_codes$Priority[i],
        stringsAsFactors = FALSE),
      startRow = cur_row, colNames = FALSE)
    addStyle(wb, sh, sty_code_num, rows = cur_row, cols = 1)
    addStyle(wb, sh, .sty_data(),  rows = cur_row, cols = 2)
    addStyle(wb, sh, sty_priority, rows = cur_row, cols = 3)
    setRowHeights(wb, sh, rows = cur_row, heights = 46)
    cur_row <- cur_row + 1L
  }

  cur_row <- cur_row + 1L  # blank separator row

  # ── Section 2: Raw string codes ───────────────────────────────────────────
  writeData(wb, sh,
    x = data.frame(
      V1 = "String codes — entered by data collectors in the raw Neotree form",
      V2 = "", V3 = "", stringsAsFactors = FALSE),
    startRow = cur_row, colNames = FALSE)
  addStyle(wb, sh, .sty_section(), rows = cur_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, sh, cols = 1:3, rows = cur_row)
  setRowHeights(wb, sh, rows = cur_row, heights = 18)
  cur_row <- cur_row + 1L

  str_codes <- data.frame(
    Code = c(
      "NK", "UNK", "NR", "REFUSED", "NE", "NA",
      "NOT_DONE", "PENDING", "UNKNOWN", "OTHER"
    ),
    Meaning = c(
      "Not Known — information was not available at time of entry",
      "Unknown — synonymous with NK; used in some field versions",
      "Not Recorded — field was seen but left blank intentionally",
      "Patient or carer refused to provide the information",
      "Not Examined — the examination or procedure was not performed",
      "Not Applicable — the field does not apply to this patient / record type",
      "Procedure or test was not done",
      "Result is pending (used in neolab records)",
      "General unknown — used in dropdown fields with no other option",
      "Other — a value outside the standard coded list; free-text may accompany"
    ),
    AppliesToField = c(
      "General", "General", "General", "General",
      "Clinical fields", "General", "Lab / procedure fields",
      "Lab fields", "Categorical fields", "Categorical fields"
    ),
    stringsAsFactors = FALSE
  )
  writeData(wb, sh, x = str_codes, startRow = cur_row, colNames = FALSE)
  addStyle(wb, sh, .sty_data(),
    rows = cur_row:(cur_row + nrow(str_codes) - 1L), cols = 1:3, gridExpand = TRUE)
  setRowHeights(wb, sh,
    rows = cur_row:(cur_row + nrow(str_codes) - 1L), heights = 22)
  cur_row <- cur_row + nrow(str_codes)

  # ── Footer note ───────────────────────────────────────────────────────────
  note_row <- cur_row + 1L
  writeData(wb, sh,
    x = data.frame(V = paste0(
      "Note: In cleaned data files all missing values are replaced by the ",
      "numeric codes above (-6 to -9). The string codes in Section 2 appear ",
      "only in pre-cleaning / raw files. When filtering data, exclude both ",
      "blank cells AND the relevant numeric NA codes. The 'NA Codes' column ",
      "in each dataset sheet indicates which numeric codes may apply to each variable."
    ), stringsAsFactors = FALSE),
    startRow = note_row, startCol = 1, colNames = FALSE)
  addStyle(wb, sh, sty_note, rows = note_row, cols = 1:3, gridExpand = TRUE)
  mergeCells(wb, sh, cols = 1:3, rows = note_row)
  setRowHeights(wb, sh, rows = note_row, heights = 60)

  freezePane(wb, sh, firstRow = TRUE)
  invisible(wb)
}

# =============================================================================
# SECTION 10 -- MAIN PROCESSING LOOP
# =============================================================================

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
message(sprintf("\nNeotree User Dictionary Generator"))
message(sprintf("Output dir: %s", OUTPUT_DIR))

# Build JSON script index once
script_index <- build_script_index(NEOTREE_SCRIPTS_BASE)
message(sprintf("Script index: %d scripts indexed.", length(script_index)))

for (country in c("ZIM", "MWI")) {
  country_full <- if (country == "ZIM") "Zimbabwe" else "Malawi"
  country_lc   <- tolower(country)
  message(sprintf("\n=== %s ===", country_full))

  ds_configs <- DATASET_CONFIGS[[country]]

  # -- First pass: collect all question_keys per dataset for available_in index
  avail_index   <- list()   # question_key -> vector of dataset labels
  loaded_cache  <- list()   # dataset_key -> list(consensus, pipeline_meta, maps_df)

  for (ds_cfg in ds_configs) {
    # JSON consensus order
    script_ids <- get_script_ids_for_dataset(country, ds_cfg$key, script_index)
    consensus  <- if (length(script_ids) > 0)
                    build_consensus_order(script_ids, script_index) else NULL

    # Pipeline dict
    pipe_dict <- load_pipeline_dict(country, ds_cfg$key, DICT_DIR, USE_ENRICHED_DICT)
    pipe_meta <- if (!is.null(pipe_dict)) build_pipeline_meta_lookup(pipe_dict$vars) else list()
    maps_df   <- if (!is.null(pipe_dict)) pipe_dict$maps else NULL

    # Determine which keys are in this dataset (JSON keys, excluding pipeline exclusions)
    if (!is.null(consensus)) {
      for (qkey in consensus$question_key) {
        if (!is_excluded(pipe_meta[[qkey]])) {
          avail_index[[qkey]] <- c(avail_index[[qkey]], ds_cfg$label)
        }
      }
    }

    # Derived variables (absent from JSON consensus) -- register them in the
    # availability index wherever the pipeline dictionary defines them.
    for (dk in DERIVED_KEYS) {
      if (!is.null(pipe_meta[[dk]]) && !is_excluded(pipe_meta[[dk]])) {
        avail_index[[dk]] <- c(avail_index[[dk]], ds_cfg$label)
      }
    }

    loaded_cache[[ds_cfg$key]] <- list(
      consensus  = consensus,
      pipe_meta  = pipe_meta,
      maps_df    = maps_df,
      script_ids = script_ids
    )
  }

  # -- Create Excel workbook --------------------------------------------------
  wb <- createWorkbook()

  # About / cover sheet  (title + generated date + reference to NA Codes sheet)
  addWorksheet(wb, "About")
  about_lines <- data.frame(
    Content = c(
      sprintf("Neotree Data Dictionary -- %s", country_full),
      sprintf("Generated: %s", format(Sys.Date(), "%d %B %Y")),
      "",
      "This dictionary describes all variables available in the Neotree cleaned dataset.",
      "One sheet per data source is provided (Admissions, Discharges, Maternal Outcomes, etc.).",
      "The Master sheet lists all unique variables across all datasets.",
      "",
      "See the 'NA Codes' sheet for a full legend of missing-value sentinel codes (-6 to -9)",
      "and raw string codes (NK, UNK, NR, etc.) entered by data collectors in the Neotree app."
    ),
    stringsAsFactors = FALSE
  )
  writeData(wb, "About", about_lines, colNames = FALSE)
  addStyle(wb, "About",
           createStyle(fontSize = 14, textDecoration = "bold",
                       fontColour = "#1F3864"),
           rows = 1, cols = 1)
  addStyle(wb, "About",
           createStyle(halign = "LEFT", wrapText = TRUE),
           rows = 2:nrow(about_lines), cols = 1, gridExpand = TRUE)
  setColWidths(wb, "About", cols = 1, widths = 85)

  add_na_legend_sheet(wb)

  # -- Per-dataset processing -------------------------------------------------
  master_rows  <- list()      # for Master sheet
  master_seen  <- character(0)

  for (ds_cfg in ds_configs) {
    message(sprintf("  [%s] ", ds_cfg$label), appendLF = FALSE)
    cache <- loaded_cache[[ds_cfg$key]]

    if (is.null(cache$consensus)) {
      message("no JSON scripts matched -- skipped")
      next
    }

    user_rows <- build_user_rows(
      consensus     = cache$consensus,
      pipeline_meta = cache$pipe_meta,
      maps_df       = cache$maps_df,
      dataset_label = ds_cfg$label,
      avail_index   = avail_index
    )

    if (is.null(user_rows) || nrow(user_rows) == 0) {
      message("0 rows after filtering -- skipped")
      next
    }

    n_secs <- length(unique(user_rows$section))
    message(sprintf("%d rows | %d sections | %d script(s)",
                    nrow(user_rows), n_secs, length(cache$script_ids)))

    # Excel sheet -- use ds_cfg$sheet if set (tab name may differ from display label)
    tab_name <- ds_cfg$sheet %||% ds_cfg$label
    add_dataset_sheet(wb, tab_name, user_rows)

    # Master: collect unique variable names (by variable_name, first occurrence)
    for (j in seq_len(nrow(user_rows))) {
      vn <- user_rows$variable_name[j]
      if (!vn %in% master_seen) {
        master_seen  <- c(master_seen, vn)
        master_rows[[length(master_rows) + 1L]] <- user_rows[j, ]
      }
    }
  }

  # -- Master sheet -----------------------------------------------------------
  if (length(master_rows) > 0) {
    master_df <- do.call(rbind, master_rows)
    master_df <- master_df[order(master_df$screen_idx, master_df$field_idx), ]
    message(sprintf("  [Master] %d unique variables", nrow(master_df)))
    add_dataset_sheet(wb, "Master", master_df)
  }

  # -- Save Excel -------------------------------------------------------------
  wb_path <- file.path(OUTPUT_DIR, sprintf("neotree_user_dict_%s.xlsx", country_lc))
  saveWorkbook(wb, wb_path, overwrite = TRUE)
  message(sprintf("  Saved: %s", wb_path))
}

message(sprintf("\nDone. Outputs written to: %s/", OUTPUT_DIR))
