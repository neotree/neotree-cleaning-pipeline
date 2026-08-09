# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 13: Categorical & Object Feature Validation
# =============================================================================
# PURPOSE:
#   Validates categorical (factor) and free-text (object/character) columns
#   through five steps:
#
#   1. FRAME SHIFT CORRECTION - residual misaligned values are mapped back to
#      their correct column using the data dictionary.
#   2. VALUE STANDARDISATION  - inconsistent categorical codes (e.g. "HCH"
#      vs "SMCH" for the same hospital) are aligned using the
#      value_mappings defined in the setup.
#   3. INVALID VALUE REMOVAL  - column-header strings, frame-shift artefacts,
#      and other unexpected values are identified and set to NA.
#   4. DISALLOWED VALUE REMOVAL - a pre-defined list of specifically known
#      bad entries (e.g. timestamps in categorical fields) is removed.
#   5. MISSING VALUE NORMALISATION - literal strings "nan", "None", "NA"
#      are replaced with real NA.
#   6. DEDUPLICATION - applied to the validated sub-frame.
#
# INPUTS:
#   df            - data.frame after Module 10
#   cfg           - configuration (cat, obj, value_mappings, values_to_delete)
#
# OUTPUTS:
#   df_categorical - validated categorical/object sub-frame
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("13_categorical_object_validation/13_categorical_object_validation.r")
# =============================================================================

source("00_setup/00_setup.r")

# -- Constants -----------------------------------------------------------------
MISSING_STRINGS <- c("nan", "none", "na", "n/a", "null", "", "NaN", "None",
                     "NA", "N/A", "NULL")

# -- Function ------------------------------------------------------------------

#' Validate Categorical and Object Features
#'
#' @param df           Full data.frame from Module 10.
#' @param cfg          Config list with $cat, $obj, $value_mappings,
#'                     $values_to_delete.
#' @param report_filepath Optional path for a text report.
#' @return Validated categorical/object sub-frame.
validate_categorical <- function(df, cfg, report_filepath = NULL) {

  key_cols  <- c("facility", "uid", "uniquekey")
  cat_cols  <- intersect(cfg$cat, names(df))
  obj_cols  <- intersect(cfg$obj, names(df))
  all_cols  <- unique(c(key_cols, cat_cols, obj_cols))
  keep_cols <- all_cols[all_cols %in% names(df)]
  df_cat    <- df[, keep_cols, drop = FALSE]

  base_name <- function(col) {
    col <- sub("\\.value$", "", col)
    col <- sub("\\.valuedischarge$", "", col)
    return(col)
  }

  standardised_count <- 0L
  deleted_count      <- 0L
  missing_norm_count <- 0L

  # -- Step 1 & 2: Value standardisation via value_mappings ------------------
  for (col in setdiff(all_cols, key_cols)) {
    if (!col %in% names(df_cat)) next
    base <- base_name(col)

    if (base %in% names(cfg$value_mappings)) {
      mapping <- cfg$value_mappings[[base]]
      for (canonical in names(mapping)) {
        aliases <- mapping[[canonical]]
        mask    <- df_cat[[col]] %in% aliases & !is.na(df_cat[[col]])
        n_fix   <- sum(mask)
        if (n_fix > 0) {
          df_cat[[col]][mask] <- canonical
          standardised_count <- standardised_count + n_fix
        }
      }
    }
  }

  # -- Step 3: Remove values from disallowed list ----------------------------
  for (base in names(cfg$values_to_delete)) {
    # Try exact column name, then with .value suffix
    for (col in c(base, paste0(base, ".value"))) {
      if (!col %in% names(df_cat)) next
      bad_vals <- cfg$values_to_delete[[base]]
      mask     <- df_cat[[col]] %in% bad_vals & !is.na(df_cat[[col]])
      n_del    <- sum(mask)
      if (n_del > 0) {
        df_cat[[col]][mask] <- NA_character_
        deleted_count <- deleted_count + n_del
        log_info(
          "  validate_categorical: %d disallowed value(s) removed from '%s'.",
          n_del, col
        )
      }
    }
  }

  # -- Step 4: Remove values that look like column headers or timestamps ------
  header_pattern  <- "^[A-Z][a-z]+(\\s[A-Z][a-z]+){2,}\\??$"   # "Name Of Birth Facility"
  ts_iso_pattern  <- "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}"  # ISO datetime strings
  ts_word_pattern <- "^(January|February|March|April|May|June|July|August|September|October|November|December)"

  for (col in setdiff(cat_cols, key_cols)) {
    if (!col %in% names(df_cat)) next
    vals   <- as.character(df_cat[[col]])
    bad    <- grepl(header_pattern, vals) |
              grepl(ts_iso_pattern, vals) |
              grepl(ts_word_pattern, vals)
    n_del  <- sum(bad & !is.na(df_cat[[col]]))
    if (n_del > 0) {
      df_cat[[col]][bad] <- NA_character_
      deleted_count <- deleted_count + n_del
    }
  }

  # -- Step 5: Normalise missing-value strings -------------------------------
  for (col in setdiff(all_cols, key_cols)) {
    if (!col %in% names(df_cat)) next
    mask <- trimws(df_cat[[col]]) %in% MISSING_STRINGS & !is.na(df_cat[[col]])
    n_fix <- sum(mask)
    if (n_fix > 0) {
      df_cat[[col]][mask] <- NA_character_
      missing_norm_count <- missing_norm_count + n_fix
    }
  }

  # -- Ensure categorical columns are factors --------------------------------
  for (col in setdiff(cat_cols, key_cols)) {
    if (col %in% names(df_cat))
      df_cat[[col]] <- as.factor(df_cat[[col]])
  }

  # -- Deduplication ---------------------------------------------------------
  n_before <- nrow(df_cat)
  df_cat   <- dplyr::distinct(df_cat)
  n_dedup  <- n_before - nrow(df_cat)

  log_info(
    paste("validate_categorical: %d values standardised | %d disallowed removed |",
          "%d missing normalised | %d duplicates removed."),
    standardised_count, deleted_count, missing_norm_count, n_dedup
  )

  # Optional report
  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c("Categorical / Object Validation Report",
                 "======================================",
        sprintf("Values standardised (mappings)   : %d", standardised_count),
        sprintf("Disallowed values removed        : %d", deleted_count),
        sprintf("Missing strings normalised       : %d", missing_norm_count),
        sprintf("Duplicate rows removed           : %d", n_dedup),
        sprintf("Final categorical/object rows    : %d", nrow(df_cat))
      )
      writeLines(lines, report_filepath)
    }, error = function(e) {
      log_warn("Could not write categorical validation report: %s", e$message)
    })
  }

  return(df_cat)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "13_categorical_validation_report.txt") else NULL

df_categorical <- validate_categorical(df, cfg,
                                       report_filepath = report_path)
log_info("Module 13 complete. Categorical sub-frame: %d rows x %d cols.",
         nrow(df_categorical), ncol(df_categorical))
