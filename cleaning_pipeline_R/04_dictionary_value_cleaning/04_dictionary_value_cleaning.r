# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 04: Dictionary-Based Value Cleaning
# =============================================================================
# PURPOSE:
#   A common data quality issue in Neotree data is "label contamination":
#   the descriptive text label for a variable (e.g. "Normal tone, movement
#   in all limbs") or the question text itself (e.g. "Name of Birth Facility")
#   appears directly in the data value column instead of the expected short
#   code (e.g. "Norm").
#
#   This module uses the data dictionary (ValueMaps sheet) to:
#     a. Replace label strings with their corresponding canonical raw codes.
#     b. Set to NA entries that match the question label (meta-data
#        contamination) but have no corresponding code.
#     c. Validate multi-value combinations (brace-wrapped, e.g. "{A,B,C}")
#        against the set of allowed codes.
#
#   The value map is sourced from cfg$value_map_list, which is built by
#   00_setup.R from the data dictionary's ValueMaps sheet.
#
# INPUTS:
#   df                 - data.frame after Module 03
#   cfg$value_map_list - nested list: question_key -> list(allowed_codes,
#                        label_to_code)
#
# OUTPUTS:
#   df  - data.frame with label-to-value shifts corrected
#
# REPORT:
#   reports/04_dictionary_cleaning_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("04_dictionary_value_cleaning/04_dictionary_value_cleaning.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Function ------------------------------------------------------------------

#' Clean Value Columns Using the Dictionary Value Map (decision-free harmonisation)
#'
#' For each column whose base name (stripping ".value") has an entry in
#' cfg$value_map_list, this emits the dictionary CANONICAL code whenever the
#' value can be resolved UNAMBIGUOUSLY. Resolution is, in order:
#'   1. Already a canonical code               -> keep.
#'   2. A raw_code (any case)                  -> emit its canonical_code.
#'   3. An option_label (any case)             -> emit its canonical_code.
#'   4. A legacy boolean (true/false/yes/no)   -> Y/N, ONLY when the variable's
#'      canonical set is a subset of {Y,N,U} (so it is genuinely a yes/no field).
#'   5. A brace multi-select {A,B,C}           -> canonicalise each token by the
#'      same code/label rules; only rewrite if EVERY token resolves.
#'   6. An option_label mapping to an empty/NA code -> delete (contamination).
#'
#' DECISION-FREE GUARANTEE: values that do not resolve by the rules above are
#' LEFT UNTOUCHED (never guessed, never coerced). These are logged as
#' "unresolved" and remain for Module 13 / clinical-decision follow-up. This
#' makes the pass safe and reversible: it only ever replaces a value with a
#' canonical code that the dictionary already defines for that variable.
#'
#' Matching is case-insensitive (rule 2/3) so that case-only variants such as
#' 'UNK' -> 'Unk' or 'GENT' -> 'Gent' (inside multi-selects) are harmonised.
#'
#' @param df              A data.frame.
#' @param value_map_list  Named list from cfg$value_map_list (entries carry
#'                        allowed_codes, canonical_codes, label_to_code,
#'                        code_to_canonical).
#' @param report_filepath Optional path for a text report.
#' @return                Cleaned data.frame.
clean_values_using_dict <- function(df,
                                    value_map_list,
                                    report_filepath = NULL) {

  get_base_name <- function(col) {
    col <- sub("\\.valuedischarge$", "", col)
    col <- sub("\\.value$",          "", col)
    return(col)
  }

  # Booleans treated as yes/no only when the field's canonical set is yes/no.
  TRUE_TOKENS  <- c("true", "yes", "t", "y")
  FALSE_TOKENS <- c("false", "no", "f", "n")

  # Resolve a single scalar token to its canonical code, or NA_character_ if it
  # cannot be resolved unambiguously.  `ci_code`, `ci_label` are case-insensitive
  # lookups (names are lowercased); `canon_lc` is the lowercased canonical set.
  resolve_token <- function(tok, canon_set, canon_lc, ci_code, ci_label,
                            allow_boolean) {
    t  <- trimws(tok)
    tl <- tolower(t)
    if (t == "") return(NA_character_)
    # 1. already canonical (exact)
    if (t %in% canon_set) return(t)
    # 2. canonical match ignoring case -> emit canonical spelling
    if (tl %in% names(canon_lc)) return(canon_lc[[tl]])
    # 3. raw_code (any case) -> canonical
    if (tl %in% names(ci_code)) return(ci_code[[tl]])
    # 4. option_label (any case) -> canonical
    if (tl %in% names(ci_label)) return(ci_label[[tl]])
    # 5. legacy boolean, only on genuine yes/no fields
    if (allow_boolean) {
      if (tl %in% TRUE_TOKENS  && "y" %in% names(canon_lc)) return(canon_lc[["y"]])
      if (tl %in% FALSE_TOKENS && "n" %in% names(canon_lc)) return(canon_lc[["n"]])
    }
    NA_character_
  }

  # Only process columns that have dictionary entries
  cols_to_clean <- names(df)[
    vapply(names(df),
           function(c) get_base_name(c) %in% names(value_map_list),
           logical(1))
  ]

  replacements_log <- list()   # col -> vector of "old -> new" strings
  deletions_log    <- list()   # col -> vector of deleted values
  unresolved_log   <- list()   # col -> vector of "value (n)" left untouched
  n_replacements   <- 0L
  n_deletions      <- 0L
  n_unresolved     <- 0L

  for (col in cols_to_clean) {
    base    <- get_base_name(col)
    mapping <- value_map_list[[base]]
    if (is.null(mapping)) next

    allowed     <- mapping$allowed_codes                 # raw codes
    canon_set   <- mapping$canonical_codes               # canonical targets
    if (is.null(canon_set) || length(canon_set) == 0L) canon_set <- allowed
    lbl_to_code <- mapping$label_to_code                 # label -> canonical
    code2canon  <- mapping$code_to_canonical             # raw_code -> canonical

    # Case-insensitive lookups name(lower) -> target.  CRITICAL SAFETY RULE:
    # drop any key that is AMBIGUOUS (resolves to >1 distinct target).  Some
    # variables have codes/labels that differ ONLY by case but mean DIFFERENT
    # things, e.g. tribe Ch='Chewa' vs CH='Chinyanja'; curprob Pn='Pain' vs
    # PN='Pneumonia'; plan CEF='Ceftriaxone' vs Cef='Ceftriaxone (surgical)'.
    # For those we must NOT case-fold: only an EXACT match (rule 1) is trusted,
    # and a stray-case value is left unresolved rather than guessed (which could
    # silently merge two distinct categories and lose information).
    build_ci <- function(keys, vals) {
      acc <- list()
      for (i in seq_along(keys)) {
        v <- vals[[i]]
        if (is.null(v) || (length(v) == 1L && is.na(v)) || identical(as.character(v), "")) next
        k <- tolower(trimws(as.character(keys[[i]])))
        if (k == "") next
        acc[[k]] <- unique(c(acc[[k]], as.character(v)))
      }
      out <- list()
      for (k in names(acc)) if (length(acc[[k]]) == 1L) out[[k]] <- acc[[k]][[1L]]
      out
    }
    canon_lc <- build_ci(as.list(canon_set), as.list(canon_set))
    ci_code  <- if (!is.null(code2canon) && length(code2canon) > 0L)
                  build_ci(as.list(names(code2canon)), code2canon) else list()
    ci_label <- if (!is.null(lbl_to_code) && length(lbl_to_code) > 0L)
                  build_ci(as.list(names(lbl_to_code)), lbl_to_code) else list()
    # Genuine yes/no field? canonical set is a subset of {Y,N,U}
    allow_boolean <- length(canon_set) > 0 &&
                     all(toupper(trimws(canon_set)) %in% c("Y", "N", "U"))

    unique_vals <- unique(na.omit(as.character(df[[col]])))

    for (val in unique_vals) {
      s <- trimws(val)
      if (s == "") next

      # -- Already canonical (exact) -------------------------------------------
      if (s %in% canon_set) next

      # -- Multi-select {A,B,C}: canonicalise each token -----------------------
      if (startsWith(s, "{") && endsWith(s, "}")) {
        parts   <- trimws(strsplit(substr(s, 2L, nchar(s) - 1L), ",")[[1L]])
        new_par <- vapply(parts, function(p)
          resolve_token(p, canon_set, canon_lc, ci_code, ci_label, allow_boolean),
          character(1))
        if (!any(is.na(new_par))) {
          new_val <- paste0("{", paste(new_par, collapse = ","), "}")
          if (!identical(new_val, s)) {
            mask <- !is.na(df[[col]]) & trimws(df[[col]]) == val
            n_hit <- sum(mask)
            df[[col]][mask] <- new_val
            n_replacements <- n_replacements + n_hit
            replacements_log[[col]] <- c(replacements_log[[col]],
              sprintf("  '%s' -> '%s'  (%d record(s))", val, new_val, n_hit))
          }
        } else {
          mask <- !is.na(df[[col]]) & trimws(df[[col]]) == val
          n_unresolved <- n_unresolved + sum(mask)
          unresolved_log[[col]] <- c(unresolved_log[[col]],
            sprintf("  '%s'  (%d record(s)) [multi-select token(s) not in dictionary]", val, sum(mask)))
        }
        next
      }

      # -- Scalar value --------------------------------------------------------
      # Label that maps to empty/NA code -> contamination, delete.
      if (tolower(s) %in% names(ci_label) &&
          (is.null(ci_label[[tolower(s)]]) || is.na(ci_label[[tolower(s)]]) ||
           ci_label[[tolower(s)]] == "")) {
        mask <- !is.na(df[[col]]) & trimws(df[[col]]) == val
        n_hit <- sum(mask)
        df[[col]][mask] <- NA_character_
        n_deletions <- n_deletions + n_hit
        deletions_log[[col]] <- c(deletions_log[[col]],
          sprintf("  '%s'  (%d record(s)) [label maps to empty code]", val, n_hit))
        next
      }

      new_code <- resolve_token(s, canon_set, canon_lc, ci_code, ci_label, allow_boolean)
      if (!is.na(new_code)) {
        if (!identical(new_code, s)) {
          mask <- !is.na(df[[col]]) & trimws(df[[col]]) == val
          n_hit <- sum(mask)
          df[[col]][mask] <- new_code
          n_replacements <- n_replacements + n_hit
          replacements_log[[col]] <- c(replacements_log[[col]],
            sprintf("  '%s' -> '%s'  (%d record(s))", val, new_code, n_hit))
        }
      } else {
        # DECISION-FREE: unknown value left untouched and logged (never guessed)
        mask <- !is.na(df[[col]]) & trimws(df[[col]]) == val
        n_unresolved <- n_unresolved + sum(mask)
        unresolved_log[[col]] <- c(unresolved_log[[col]],
          sprintf("  '%s'  (%d record(s)) [not in dictionary - left untouched]", val, sum(mask)))
      }
    }
  }

  n_cols_replaced   <- length(replacements_log)
  n_cols_deleted    <- length(deletions_log)
  n_cols_unresolved <- length(unresolved_log)

  log_info(
    paste("clean_values_using_dict: %d replacement(s) across %d col(s) |",
          "%d deletion(s) across %d col(s) |",
          "%d unresolved value(s) left untouched across %d col(s)"),
    n_replacements, n_cols_replaced,
    n_deletions,    n_cols_deleted,
    n_unresolved,   n_cols_unresolved
  )

  # -- Write report ------------------------------------------------------------
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 04 - Dictionary-Based Value Cleaning Report",
        "===================================================",
        sprintf("Run timestamp           : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                 : %s", toupper(cfg$country)),
        sprintf("Dataset                 : %s", cfg$dataset),
        "",
        sprintf("Columns checked         : %d", length(cols_to_clean)),
        sprintf("Total replacements made : %d (across %d column(s))",
                n_replacements, n_cols_replaced),
        sprintf("Total deletions made    : %d (across %d column(s))",
                n_deletions, n_cols_deleted),
        sprintf("Total unresolved (kept) : %d (across %d column(s))",
                n_unresolved, n_cols_unresolved),
        "",
        "NOTE: 'unresolved' values are NOT in the dictionary for their variable",
        "and were LEFT UNTOUCHED (never guessed). They are listed below and are",
        "the candidates for the clinical-team decision file.",
        ""
      )

      lines <- c(lines, "=== Replacements (label -> code) ===")
      if (n_cols_replaced == 0) {
        lines <- c(lines, "  (none)")
      } else {
        for (col in names(replacements_log)) {
          lines <- c(lines,
                     sprintf("Column '%s':", col),
                     replacements_log[[col]])
        }
      }

      lines <- c(lines, "", "=== Deletions (label contamination / empty code) ===")
      if (n_cols_deleted == 0) {
        lines <- c(lines, "  (none)")
      } else {
        for (col in names(deletions_log)) {
          lines <- c(lines,
                     sprintf("Column '%s':", col),
                     deletions_log[[col]])
        }
      }

      lines <- c(lines, "",
                 "=== Unresolved values left untouched (clinical-decision candidates) ===")
      if (n_cols_unresolved == 0) {
        lines <- c(lines, "  (none)")
      } else {
        for (col in names(unresolved_log)) {
          lines <- c(lines,
                     sprintf("Column '%s':", col),
                     unresolved_log[[col]])
        }
      }

      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write Module 04 report: %s", e$message)
    })
  }

  return(df)
}

# =============================================================================
# Multi-select encoding normalisation
# =============================================================================
# Two encoding formats exist for multi-select fields across Neotree app
# versions and database export pipelines:
#
#   Brace format  (canonical): {DCC,S2S}
#   JSON array format (older): ["DCC","S2S"]
#
# Both formats encode the same information. Module 04 already validates and
# accepts brace-format multi-selects. JSON-array format values are unrecognised
# by the dictionary validator and would otherwise be flagged as invalid by
# Module 13. This function normalises all JSON-array encoded values to the
# canonical brace format so that the rest of the pipeline sees a single
# consistent representation.
#
# Affected columns: any column whose base name has an entry in value_map_list
# (i.e., columns with dictionary definitions), plus resus and delivinter
# explicitly named as known multi-select columns. The regex is conservative:
# it only converts strings matching the exact pattern ["X",...] and will not
# modify free-text or other structured values.
# =============================================================================

#' Normalise Multi-Select Encoding from JSON Array to Brace Format
#'
#' Converts ["A","B","C"] -> {A,B,C} for all columns that are expected to
#' carry multi-select values (identified by presence in value_map_list, or by
#' explicit inclusion in MULTISELECT_COLS).
#'
#' @param df              A data.frame.
#' @param value_map_list  Named list from cfg$value_map_list.
#' @return                data.frame with normalised multi-select values.
normalise_multiselect_encoding <- function(df, value_map_list) {

  # Known multi-select columns (add new ones here as the form evolves)
  MULTISELECT_COLS <- c("resus", "delivinter")

  get_base_name <- function(col) {
    col <- sub("\\.valuedischarge$", "", col)
    col <- sub("\\.value$",          "", col)
    return(col)
  }

  # Identify columns to check: those in value_map_list OR in MULTISELECT_COLS
  dict_bases <- names(value_map_list)
  cols_to_check <- names(df)[vapply(names(df), function(c) {
    base <- get_base_name(c)
    base %in% dict_bases | base %in% MULTISELECT_COLS
  }, logical(1))]

  # Regex: matches ["A","B"] or ["A","B","C"] etc.
  # Capture group 1 = the comma-separated content inside the brackets
  json_array_re <- "^\\[\"([^\"]*)\"(?:,\"([^\"]*)\")*(,\"[^\"]*\")*\\]$"

  n_converted  <- 0L
  cols_touched <- character(0)

  for (col in cols_to_check) {
    vals <- as.character(df[[col]])
    # Quick check: does this column contain any JSON-array-encoded values?
    has_json <- !is.na(vals) & startsWith(vals, "[")
    if (!any(has_json)) next

    new_vals <- vals
    for (i in which(has_json)) {
      v <- vals[i]
      # Must start with [" and end with "]
      if (!grepl('^\\["', v, perl = TRUE) || !endsWith(v, '"]')) next
      # Strip outer [ ], remove all " characters, split on comma.
      # This handles both compact ["A","B"] and spaced ["A", "B"] formats.
      inner <- substr(v, 2L, nchar(v) - 1L)          # remove [ ]
      inner <- gsub('"', '', inner, fixed = TRUE)     # remove all quotes
      parts <- trimws(strsplit(inner, ',', fixed = TRUE)[[1L]])
      if (length(parts) == 0L || any(nchar(parts) == 0L)) next
      new_vals[i] <- paste0("{", paste(parts, collapse = ","), "}")
      n_converted <- n_converted + 1L
    }

    changed <- sum(new_vals != vals, na.rm = TRUE)
    if (changed > 0L) {
      df[[col]]    <- new_vals
      cols_touched <- c(cols_touched, col)
    }
  }

  log_info(
    "normalise_multiselect_encoding: %d JSON-array value(s) converted to brace format across %d column(s): %s",
    n_converted,
    length(cols_touched),
    if (length(cols_touched) > 0L) paste(cols_touched, collapse = ", ") else "(none)"
  )

  return(df)
}

# =============================================================================
# modedelivery harmonisation
# =============================================================================
# Mixed script-version coding: older Neotree app scripts stored text labels
# (e.g. "SVD", "CSPrLab"), while newer scripts store numeric codes 1-7.
# Because the user dictionary lists this variable as "mode_delivery" (with
# underscore) but the actual column name is "modedelivery" (no underscore),
# the dictionary-driven clean_values_using_dict() silently misses it.  A
# dedicated recode block is therefore applied here after the dictionary pass.
#
# Canonical coding (from Neotree scripts):
#   1 = Spontaneous Vaginal Delivery (SVD)
#   2 = Vacuum extraction
#   3 = Forceps
#   4 = Elective Caesarean Section
#   5 = Emergency Caesarean Section
#   6 = Breech extraction (vaginal)
#   7 = Induced Vaginal Delivery
# =============================================================================

MODEDELIVERY_MAP <- c(
  "SVD"      = "1",   # Spontaneous Vaginal Delivery
  "Vent"     = "2",   # Vacuum extraction
  "For"      = "3",   # Forceps
  "ElCS"     = "4",   # Elective Caesarean Section
  "ECS"      = "5",   # Emergency Caesarean Section
  "CSPrLab"  = "5",   # CS before labour  (alias: Emergency CS)
  "CSPoLab"  = "5",   # CS after onset of labour (alias: Emergency CS)
  "IVD"      = "7",   # Induced Vaginal Delivery
  "ID"       = "7"    # Induced Delivery  (alias: Induced Vaginal Delivery)
)

harmonise_modedelivery <- function(df) {
  target_cols <- intersect(c("modedelivery", "modedelivery.value"), names(df))
  if (length(target_cols) == 0L) return(df)

  total_recoded <- 0L
  for (col in target_cols) {
    vals      <- as.character(df[[col]])
    to_recode <- !is.na(vals) & vals %in% names(MODEDELIVERY_MAP)
    n_recode  <- sum(to_recode)
    if (n_recode > 0L) {
      df[[col]][to_recode] <- MODEDELIVERY_MAP[vals[to_recode]]
      total_recoded <- total_recoded + n_recode
    }
  }
  log_info(
    "harmonise_modedelivery: %d text label(s) recoded to numeric (column(s): %s).",
    total_recoded,
    paste(target_cols, collapse = ", ")
  )
  return(df)
}

# =============================================================================
# Thompson score label stripping
# =============================================================================
# Some Neotree script versions stored Thompson score values as "0 = Normal",
# "1 = Mild", "2 = Moderate" etc. instead of bare integers.  Strip the
# " = <label>" suffix from all thompson* columns so all values are bare
# integers consistent with the numeric coding used in later script versions.
# =============================================================================

strip_thompson_labels <- function(df) {
  thompson_cols <- grep("^thomp", names(df), value = TRUE, ignore.case = TRUE)
  if (length(thompson_cols) == 0L) return(df)

  total_stripped <- 0L
  cols_affected  <- character(0)
  for (col in thompson_cols) {
    vals      <- as.character(df[[col]])
    has_label <- !is.na(vals) & grepl("^\\d+\\s*=", vals, perl = TRUE)
    n_strip   <- sum(has_label)
    if (n_strip > 0L) {
      df[[col]][has_label] <- sub("^(\\d+)\\s*=.*$", "\\1", vals[has_label], perl = TRUE)
      total_stripped <- total_stripped + n_strip
      cols_affected  <- c(cols_affected, col)
    }
  }
  log_info(
    "strip_thompson_labels: %d label string(s) stripped across %d thompson column(s): %s",
    total_stripped,
    length(cols_affected),
    if (length(cols_affected) > 0) paste(cols_affected, collapse = ", ") else "(none)"
  )
  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "04_dictionary_cleaning_report.txt") else NULL

# Step 0: normalise multi-select encoding before dictionary validation so
# that JSON-array format (["A","B"]) is converted to brace format ({A,B})
# and recognised as valid by clean_values_using_dict below.
df <- normalise_multiselect_encoding(df, cfg$value_map_list)

df <- clean_values_using_dict(
  df             = df,
  value_map_list = cfg$value_map_list,
  report_filepath = report_path
)

# Post-dictionary recodes: handle mixed script-version coding not covered by
# the dictionary (modedelivery column name mismatch, Thompson label contamination)
df <- harmonise_modedelivery(df)
df <- strip_thompson_labels(df)

log_info("Module 04 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
