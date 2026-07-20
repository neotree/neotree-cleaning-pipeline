# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 16: NA Reason Coding
# =============================================================================
# PURPOSE:
#   For every NA cell in the final cleaned dataset, assigns one of four
#   reason codes explaining WHY the value is missing:
#
#     -6  REDACTED      A value was present in the raw data but was removed
#                       because it matched a PII pattern (phone number, email,
#                       hospital ID).  The information existed but cannot be
#                       shared.
#
#     -7  NOT APPLICABLE  The field was never shown to the data collector
#                       because the Neotree form's skip logic determined it
#                       was not relevant for this patient (e.g. a result field
#                       for a test that was never performed).  These NAs are
#                       structural and expected.
#
#     -8  INVALID / REMOVED  A value was present in the raw data but was
#                       removed by the cleaning pipeline because it failed
#                       validation: unrecognised dictionary code, label
#                       contamination, pattern contamination, out-of-range
#                       numeric, type coercion failure, or blacklisted value.
#
#     -9  UNKNOWN       The raw cell was empty or contained a recognised
#                       missing-value placeholder ("nan", "none", "null",
#                       "n/a", etc.).  The question was applicable but no
#                       useful value was recorded.
#
# CLASSIFICATION PRIORITY:
#   -6  takes priority when raw value matches any PII pattern.
#   -7  takes priority over -9 when the skip condition evaluates FALSE
#       (the field was not applicable even if the raw cell is empty).
#   -8  assigned when raw value was non-empty and non-PII but is NA in clean.
#   -9  assigned to all remaining NAs (empty or missing-string raw values
#       where the field was applicable or condition could not be evaluated).
#
# INPUTS:
#   df_clean         -- final cleaned data.frame (from Module 15 / 00b)
#   cfg              -- configuration list (country, dataset, csv_filepath,
#                      output_csv, report_dir, neotree_scripts_dir)
#
# OUTPUTS:
#   df_na_reasons    -- data.frame, same dimensions as df_clean.
#                      Each cell contains the reason code (-6/-7/-8/-9) if
#                      the corresponding df_clean cell is NA, otherwise NA_real_.
#                      Saved as *_na_reasons.csv alongside the clean CSV.
#
#   na_reasons_long  -- long-format provenance table:
#                      (uid, facility, variable, na_reason, raw_value)
#                      Saved as *_na_reasons_long.csv.  Useful for auditing
#                      and joining to clean data for ML feature engineering.
#
# USAGE:
#   source("00_setup/00_setup.r")   # provides cfg, df_clean
#   source("16_na_reason_coding/16_na_reason_coding.r")
# =============================================================================

source("00_setup/00_setup.r")
source("16_na_reason_coding/helpers/01_load_scripts.r")
source("16_na_reason_coding/helpers/02_condition_evaluator.r")
source("16_na_reason_coding/helpers/03_facility_script_map.r")

# =============================================================================
# CONSTANTS
# =============================================================================

NA_CODE_REDACTED    <- -6L   # PII removed
NA_CODE_NOT_APPLIC  <- -7L   # Skip logic -- field not shown
NA_CODE_INVALID     <- -8L   # Pipeline validation removed value
NA_CODE_UNKNOWN     <- -9L   # Raw was empty / missing string

MISSING_STRINGS_16 <- c("nan", "none", "na", "n/a", "null", "",
                         "NaN", "None", "NA", "N/A", "NULL")

PII_PATTERNS_16 <- list(
  phone_international = "^\\+?[0-9]{7,15}$",
  phone_local_zw      = "^0[67][0-9]{8}$",
  phone_local_mwi     = "^0[89][0-9]{8}$",
  email               = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}",
  nhs_number          = "^[0-9]{3}[- ][0-9]{3}[- ][0-9]{4}$"
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#' Normalise a Column Name to Match Script field_key_lower
#' Strips the .value / .valuedischarge suffix and lowercases, removes
#' non-alphanumeric characters -- matching the form used in 01_load_scripts.r
normalise_col_for_lookup <- function(col) {
  col <- sub("\\.valuedischarge$", "", col)
  col <- sub("\\.value$",          "", col)
  col <- tolower(gsub("[^A-Za-z0-9]", "", col))
  col
}

#' Check Whether a Raw Value Matches Any PII Pattern
is_pii_value <- function(val) {
  if (is.na(val) || val == "") return(FALSE)
  any(vapply(PII_PATTERNS_16, function(pat)
    grepl(pat, val, perl = TRUE), logical(1)))
}

#' Check Whether a Raw Value Is a Recognised Missing-Value Placeholder
is_missing_string <- function(val) {
  if (is.na(val)) return(TRUE)
  trimws(val) %in% MISSING_STRINGS_16
}

#' Strip .value / .valuedischarge Suffix (for matching raw to clean columns)
strip_suffix <- function(col) {
  col <- sub("\\.valuedischarge$", "", col)
  col <- sub("\\.value$",          "", col)
  col
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

#' Classify NA Cells in the Cleaned Dataset
#'
#' @param df_clean         Final cleaned data.frame (after module 15/00b).
#' @param df_raw           Raw data.frame (original CSV before any cleaning).
#' @param script_conditions data.frame from load_all_scripts()$conditions.
#' @param cfg              Pipeline configuration list.
#' @return                 List with $wide (same dims as df_clean) and
#'                         $long (provenance data.frame).
classify_na_reasons <- function(df_clean, df_raw, script_conditions, cfg) {

  log_info("Module 16: classifying NA cells in %d x %d dataset.",
           nrow(df_clean), ncol(df_clean))

  key_cols   <- c("uid", "facility", "uniquekey")
  data_cols  <- setdiff(names(df_clean), key_cols)
  country    <- toupper(cfg$country)
  dataset    <- cfg$dataset

  # ------------------------------------------------------------------
  # 1. Align raw data to clean data on uid + facility
  # ------------------------------------------------------------------
  # The raw data has .value suffixed columns; the clean data has plain names
  # (suffix stripped by module 15).  Build a name map: clean_col -> raw_col.

  raw_col_map <- build_raw_col_map(names(df_raw), names(df_clean))

  # Standardise raw key columns
  raw_keys <- normalise_raw_keys(df_raw)

  # ------------------------------------------------------------------
  # 2. Build per-row script lookup: uid -> script_id
  # ------------------------------------------------------------------
  # We resolve the script for every row once rather than per-cell.
  log_info("Resolving script IDs for %d rows...", nrow(df_clean))

  scriptid_col <- intersect(c("scriptid", "script_id"), tolower(names(df_raw)))[1]
  raw_scriptids <- if (!is.na(scriptid_col))
    tolower(df_raw[[scriptid_col]]) else rep(NA_character_, nrow(df_raw))

  # Join scriptid to clean data via uid+facility
  script_lookup <- resolve_row_scripts(
    df_clean, raw_keys, raw_scriptids, country, dataset
  )

  # ------------------------------------------------------------------
  # 3. Pre-build condition lookup: script_id + field_key_lower -> condition
  # ------------------------------------------------------------------
  cond_lookup <- build_condition_lookup(script_conditions)

  # ------------------------------------------------------------------
  # 4. Build raw value matrix aligned to clean data
  # ------------------------------------------------------------------
  log_info("Aligning raw values to clean dataset columns...")
  raw_aligned <- align_raw_to_clean(df_clean, df_raw, raw_keys, raw_col_map)

  # ------------------------------------------------------------------
  # 5. Classify each NA cell
  # ------------------------------------------------------------------
  log_info("Classifying NA cells...")

  # Initialise result matrix (NA = cell was not NA in clean data)
  reasons_mat <- matrix(NA_integer_, nrow = nrow(df_clean), ncol = length(data_cols))
  colnames(reasons_mat) <- data_cols

  # Pre-build patient value rows for condition evaluation
  # We need the raw values keyed by field_key_lower for each patient
  raw_for_eval <- build_raw_eval_frame(raw_aligned, names(df_raw))

  # Column-major list: raw_cols_list[[field]][row] is faster than
  # slicing a data.frame row inside a tight loop (avoids as.list(df[ri,]))
  raw_cols_list <- as.list(raw_for_eval)

  # Vectorised PII checker: operates on a character vector of raw values
  check_pii_vec <- function(vals) {
    out       <- rep(FALSE, length(vals))
    candidate <- !is.na(vals) & vals != ""
    if (!any(candidate)) return(out)
    for (pat in PII_PATTERNS_16) {
      out[candidate] <- out[candidate] |
        grepl(pat, vals[candidate], perl = TRUE)
    }
    out
  }

  # Precompute the full set of missing-value strings (trimmed + original)
  missing_set <- unique(c(MISSING_STRINGS_16, trimws(MISSING_STRINGS_16)))

  # ------------------------------------------------------------------
  # Skip logic evaluation infrastructure
  #
  # Problem: evaluate_condition() calls translate_condition() + parse() +
  # new.env() on every single row -- millions of times.
  #
  # Fix 1: parse each unique condition string ONCE and cache the result.
  #   parsed_cond_cache[[cond_string]] -> parsed expression object (or NA)
  #
  # Fix 2: create one eval environment with a mutable row pointer.
  #   skip_lookup reads raw_cols_list[[key]][row_ptr$i], so we only need
  #   to update row_ptr$i per row rather than rebuild the whole env.
  # ------------------------------------------------------------------
  parsed_cond_cache <- list()

  row_ptr    <- new.env(hash = FALSE, parent = emptyenv())
  row_ptr$i  <- 1L

  skip_lookup <- function(key) {
    cv <- raw_cols_list[[key]]
    if (is.null(cv)) return(NA_character_)
    v <- cv[row_ptr$i]
    if (is.null(v) || is.na(v)) return(NA_character_)
    as.character(v)
  }

  skip_eval_env          <- new.env(parent = baseenv())
  skip_eval_env[["."]]   <- skip_lookup

  n_redacted   <- 0L
  n_notapplic  <- 0L
  n_invalid    <- 0L
  n_unknown    <- 0L

  for (ci in seq_along(data_cols)) {
    col     <- data_cols[ci]
    col_key <- normalise_col_for_lookup(col)

    # Row indices where the clean value is NA
    na_rows <- which(is.na(df_clean[[col]]))
    if (length(na_rows) == 0L) next

    raw_vals <- raw_aligned[[col]][na_rows]

    # --- Vectorised Priority 1: PII ---
    is_pii <- check_pii_vec(raw_vals)

    # --- Vectorised Priority 3: Invalid (raw non-empty, non-missing-string) ---
    # Evaluated here; may be overridden by -7 below for the same row.
    is_non_empty <- !is.na(raw_vals) & !(trimws(raw_vals) %in% missing_set)

    # Initialise result for this column (0 = unclassified -> will become -9)
    result <- integer(length(na_rows))
    result[is_pii]                 <- NA_CODE_REDACTED   # -6
    result[!is_pii & is_non_empty] <- NA_CODE_INVALID    # -8 (tentative; -7 may override)

    # --- Priority 2: Skip logic (-7 can override -8 but not -6) ---
    sids_here <- script_lookup[na_rows]
    skip_cand <- which(!is_pii)

    for (k in skip_cand) {
      sid <- sids_here[k]
      if (is.na(sid)) next
      cond <- get_condition(cond_lookup, sid, col_key)
      if (is.na(cond) || cond == "") next

      # --- Cached parse: translate + parse() once per unique condition ---
      parsed_expr <- parsed_cond_cache[[cond]]
      if (is.null(parsed_expr)) {
        r_expr      <- translate_condition(cond)
        parsed_expr <- if (!is.na(r_expr))
          tryCatch(parse(text = r_expr), error = function(e) NA)
        else
          NA
        parsed_cond_cache[[cond]] <- parsed_expr
      }
      if (identical(parsed_expr, NA)) next

      # --- Reused eval env: just update the row pointer ---
      row_ptr$i <- na_rows[k]

      shown <- tryCatch(
        eval(parsed_expr, envir = skip_eval_env),
        error   = function(e) NA,
        warning = function(w) suppressWarnings(
          tryCatch(eval(parsed_expr, envir = skip_eval_env),
                   error = function(e) NA)
        )
      )

      if (length(shown) > 0L && isFALSE(shown[[1L]])) {
        result[k] <- NA_CODE_NOT_APPLIC   # -7
      }
    }

    # --- Priority 4: remaining 0s -> Unknown ---
    result[result == 0L] <- NA_CODE_UNKNOWN

    reasons_mat[na_rows, ci] <- result

    n_redacted  <- n_redacted  + sum(result == NA_CODE_REDACTED,  na.rm = TRUE)
    n_notapplic <- n_notapplic + sum(result == NA_CODE_NOT_APPLIC, na.rm = TRUE)
    n_invalid   <- n_invalid   + sum(result == NA_CODE_INVALID,   na.rm = TRUE)
    n_unknown   <- n_unknown   + sum(result == NA_CODE_UNKNOWN,   na.rm = TRUE)
  }

  total_na <- n_redacted + n_notapplic + n_invalid + n_unknown
  log_info("NA classification complete:")
  log_info("  -6 Redacted      : %d  (%.1f%%)", n_redacted,
           100 * n_redacted  / max(total_na, 1))
  log_info("  -7 Not applicable: %d  (%.1f%%)", n_notapplic,
           100 * n_notapplic / max(total_na, 1))
  log_info("  -8 Invalid/removed: %d  (%.1f%%)", n_invalid,
           100 * n_invalid   / max(total_na, 1))
  log_info("  -9 Unknown       : %d  (%.1f%%)", n_unknown,
           100 * n_unknown   / max(total_na, 1))
  log_info("  Total NA cells   : %d", total_na)

  # ------------------------------------------------------------------
  # 6. Build output data.frames
  # ------------------------------------------------------------------
  # Wide: same shape as df_clean, with reason codes in NA positions
  df_wide <- as.data.frame(reasons_mat, stringsAsFactors = FALSE)
  df_wide <- cbind(df_clean[, key_cols, drop = FALSE], df_wide)

  # Long: one row per NA cell
  df_long <- build_long_format(df_clean, reasons_mat, raw_aligned,
                               data_cols, key_cols)

  list(wide = df_wide, long = df_long,
       counts = list(redacted   = n_redacted,
                     notapplic  = n_notapplic,
                     invalid    = n_invalid,
                     unknown    = n_unknown))
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

#' Build a Map from Clean Column Names to Raw Column Names
build_raw_col_map <- function(raw_names, clean_names) {
  # raw columns have .value suffix; clean columns have it stripped
  raw_base <- tolower(gsub("[^A-Za-z0-9.]", "", raw_names))
  clean_base <- tolower(gsub("[^A-Za-z0-9]", "", clean_names))

  map <- setNames(rep(NA_character_, length(clean_names)), clean_names)
  for (cn in clean_names) {
    cn_norm <- tolower(gsub("[^A-Za-z0-9]", "", cn))
    # Try exact match first (raw has .value suffix)
    candidates <- raw_names[raw_base %in%
                              c(paste0(cn_norm, ".value"),
                                paste0(cn_norm, ".valuedischarge"),
                                cn_norm)]
    if (length(candidates) > 0) map[[cn]] <- candidates[1]
  }
  map
}

#' Normalise Raw Key Columns to Lowercase Compact Names
normalise_raw_keys <- function(df_raw) {
  names(df_raw) <- tolower(gsub("[^A-Za-z0-9._]", "", names(df_raw)))
  cols <- names(df_raw)
  uid_col      <- intersect(c("uid"), cols)[1]
  facility_col <- intersect(c("facility"), cols)[1]
  key_col      <- intersect(c("uniquekey", "unique_key"), cols)[1]

  data.frame(
    uid       = if (!is.na(uid_col))      df_raw[[uid_col]]      else NA_character_,
    facility  = if (!is.na(facility_col)) df_raw[[facility_col]] else NA_character_,
    uniquekey = if (!is.na(key_col))      df_raw[[key_col]]      else NA_character_,
    stringsAsFactors = FALSE
  )
}

#' Resolve the Script ID for Every Row in df_clean
#'
#' Vectorised: one match() call maps clean uids to raw rows; resolve_script_id
#' is then applied via mapply (still one call per row but no hash lookups).
resolve_row_scripts <- function(df_clean, raw_keys, raw_scriptids,
                                country, dataset) {
  # Single vectorised uid join
  raw_idx  <- match(as.character(df_clean$uid), as.character(raw_keys$uid))
  raw_sids <- ifelse(!is.na(raw_idx), raw_scriptids[raw_idx], NA_character_)

  mapply(
    resolve_script_id,
    scriptid_raw = raw_sids,
    facility     = as.character(df_clean$facility),
    MoreArgs     = list(country = country, dataset = dataset),
    USE.NAMES    = FALSE
  )
}

#' Build a Two-Level Lookup: script_id -> field_key_lower -> condition
build_condition_lookup <- function(script_conditions) {
  if (nrow(script_conditions) == 0) return(list())

  result <- list()
  for (sid in unique(script_conditions$script_id)) {
    sub <- script_conditions[script_conditions$script_id == sid, ]
    # If a field appears multiple times (multiple screens), use the most
    # restrictive condition -- in practice fields should be unique per script
    field_conds <- setNames(sub$effective_condition, sub$field_key_lower)
    # Remove empty conditions (always shown)
    field_conds <- field_conds[field_conds != ""]
    result[[sid]] <- field_conds
  }
  result
}

#' Look Up a Condition String for a (script_id, field_key_lower) Pair
get_condition <- function(cond_lookup, script_id, field_key_lower) {
  script_conds <- cond_lookup[[script_id]]
  if (is.null(script_conds)) return(NA_character_)
  # script_conds is a named character vector; [[ on a missing key throws
  # "subscript out of bounds" rather than returning NULL, so check first.
  if (!field_key_lower %in% names(script_conds)) return(NA_character_)
  val <- script_conds[[field_key_lower]]
  if (is.null(val)) return(NA_character_)
  val
}

#' Align Raw Data Columns to Clean Data Shape
#'
#' Returns a character matrix with the same number of rows as df_clean
#' and columns matching data_cols.  Values are raw (pre-cleaning) strings.
#'
#' Vectorised: one match() call maps all clean rows to raw rows; the
#' inner loop runs once per column (422) not once per cell (16.4 M).
align_raw_to_clean <- function(df_clean, df_raw, raw_keys, raw_col_map) {
  n_rows    <- nrow(df_clean)
  data_cols <- setdiff(names(df_clean), c("uid", "facility", "uniquekey"))

  mat <- matrix(NA_character_, nrow = n_rows, ncol = length(data_cols))
  colnames(mat) <- data_cols

  # Single vectorised join: clean row i -> raw row uid_to_raw[i] (NA if no match)
  uid_to_raw <- match(as.character(df_clean$uid), as.character(raw_keys$uid))
  valid      <- which(!is.na(uid_to_raw))   # clean rows that have a raw counterpart

  if (length(valid) == 0L) return(as.data.frame(mat, stringsAsFactors = FALSE))

  raw_row_idx <- uid_to_raw[valid]          # corresponding raw row indices

  for (ci in seq_along(data_cols)) {
    col     <- data_cols[ci]
    raw_col <- raw_col_map[[col]]
    if (is.na(raw_col) || !raw_col %in% names(df_raw)) next

    raw_vals          <- as.character(df_raw[[raw_col]])
    mat[valid, ci]    <- raw_vals[raw_row_idx]
  }

  as.data.frame(mat, stringsAsFactors = FALSE)
}

#' Build a Data Frame of Raw Values Keyed by field_key_lower (for condition eval)
build_raw_eval_frame <- function(raw_aligned, raw_col_names) {
  # Column names in raw_aligned are clean-data column names (suffix stripped)
  # We need field_key_lower (no dots, no suffix, lowercase, no special chars)
  eval_names <- tolower(gsub("[^A-Za-z0-9]", "", names(raw_aligned)))
  df <- raw_aligned
  names(df) <- eval_names
  df
}

#' Build Per-Variable NA Reason Summary
#'
#' Returns a data.frame with one row per data variable showing: total rows,
#' present count, missing count, % missing, and breakdown by reason code.
#' Sorted by n_missing descending so the most-problematic variables appear first.
build_variable_summary <- function(na_long, n_rows, data_cols) {
  counts_by_code <- list()
  for (code in c(-6L, -7L, -8L, -9L)) {
    sub <- na_long[!is.na(na_long$na_reason) & na_long$na_reason == code, ]
    counts_by_code[[as.character(code)]] <- table(sub$variable)
  }

  get_n <- function(tbl, v) {
    n <- tbl[v]
    if (length(n) == 0L || is.na(n)) 0L else as.integer(n)
  }

  rows <- lapply(data_cols, function(v) {
    n_red  <- get_n(counts_by_code[["-6"]], v)
    n_nap  <- get_n(counts_by_code[["-7"]], v)
    n_inv  <- get_n(counts_by_code[["-8"]], v)
    n_unk  <- get_n(counts_by_code[["-9"]], v)
    n_miss <- n_red + n_nap + n_inv + n_unk
    data.frame(
      variable         = v,
      n_total          = n_rows,
      n_present        = n_rows - n_miss,
      n_missing        = n_miss,
      pct_missing      = round(100 * n_miss / max(n_rows, 1L), 1),
      n_not_applicable = n_nap,
      n_invalid        = n_inv,
      n_unknown        = n_unk,
      n_redacted       = n_red,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out[order(-out$n_missing), ]
}

#' Build Long-Format NA Reasons Table
#'
#' Vectorised: which(..., arr.ind = TRUE) finds all assigned cells in one call;
#' the output data.frame is built in a single pass with no row-by-row appending.
build_long_format <- function(df_clean, reasons_mat, raw_aligned,
                              data_cols, key_cols) {

  idx <- which(!is.na(reasons_mat), arr.ind = TRUE)

  if (nrow(idx) == 0L) {
    return(data.frame(uid = character(), facility = character(),
                      variable = character(), na_reason = integer(),
                      raw_value = character(), stringsAsFactors = FALSE))
  }

  ri <- idx[, 1]
  ci <- idx[, 2]

  # Fetch raw values column by column (vectorised per column)
  raw_value <- character(nrow(idx))
  for (col_i in unique(ci)) {
    rows_for_col           <- which(ci == col_i)
    col_name               <- data_cols[col_i]
    raw_value[rows_for_col] <- raw_aligned[[col_name]][ri[rows_for_col]]
  }

  data.frame(
    uid       = df_clean$uid[ri],
    facility  = df_clean$facility[ri],
    variable  = data_cols[ci],
    na_reason = reasons_mat[idx],
    raw_value = raw_value,
    stringsAsFactors = FALSE
  )
}

#' Build Clean-Coded Data Frame
#'
#' Returns a copy of df_clean where every NA cell is replaced by its reason
#' code (-6 / -7 / -8 / -9) from df_na_reasons.  All columns are coerced to
#' character so the integer codes can be embedded uniformly regardless of the
#' original column type (numeric, boolean, datetime, categorical).
#'
#' @param df_clean      Final cleaned data.frame (from Module 15 / 00b).
#' @param df_na_reasons Wide reasons data.frame produced by classify_na_reasons()
#'                      (same dimensions as df_clean; NA positions hold the code,
#'                      non-NA positions are NA_integer_).
#' @return              Character data.frame with the same columns as df_clean;
#'                      NA cells are replaced by their reason code strings
#'                      ("-6", "-7", "-8", "-9").
build_clean_coded <- function(df_clean, df_na_reasons) {
  key_cols  <- intersect(c("uid", "facility", "uniquekey"), names(df_clean))
  data_cols <- setdiff(names(df_clean), key_cols)

  # Coerce to character, preserving true NAs (as.character(NA) -> "NA" in R,
  # so we restore NA_character_ explicitly for every originally-NA cell).
  df_coded <- as.data.frame(
    lapply(df_clean, function(x) {
      out          <- as.character(x)
      out[is.na(x)] <- NA_character_
      out
    }),
    stringsAsFactors = FALSE
  )

  # Embed reason codes into NA positions
  for (col in data_cols) {
    if (!col %in% names(df_na_reasons)) next
    na_mask <- is.na(df_coded[[col]])
    if (!any(na_mask)) next
    codes    <- df_na_reasons[[col]][na_mask]   # integer or NA
    assigned <- !is.na(codes)
    df_coded[[col]][na_mask][assigned] <- as.character(codes[assigned])
  }

  df_coded
}

# =============================================================================
# RUN
# =============================================================================

log_info("Module 16: NA Reason Coding started.")

# -- Check prerequisites -------------------------------------------------------
if (!exists("df_clean")) {
  stop("df_clean not found. Run modules 00-15 (and optionally 00b) first.")
}
if (is.null(cfg$neotree_scripts_dir) || !dir.exists(cfg$neotree_scripts_dir)) {
  stop(sprintf(
    "cfg$neotree_scripts_dir not set or directory not found: %s\n",
    cfg$neotree_scripts_dir %||% "<not set>"
  ))
}

# -- Load raw data -------------------------------------------------------------
log_info("Loading raw data from: %s", basename(cfg$csv_filepath))
df_raw_16 <- tryCatch(
  readr::read_csv(cfg$csv_filepath,
                  col_types  = readr::cols(.default = readr::col_character()),
                  name_repair = "minimal",
                  show_col_types = FALSE),
  error = function(e) stop(sprintf("Cannot read raw CSV: %s", e$message))
)
df_raw_16 <- as.data.frame(df_raw_16, stringsAsFactors = FALSE)

# -- Load scripts --------------------------------------------------------------
log_info("Loading Neotree scripts from: %s", cfg$neotree_scripts_dir)
scripts_data <- load_all_scripts(cfg$neotree_scripts_dir)

# -- Classify NAs -------------------------------------------------------------
na_result <- classify_na_reasons(
  df_clean          = df_clean,
  df_raw            = df_raw_16,
  script_conditions = scripts_data$conditions,
  cfg               = cfg
)

df_na_reasons      <- na_result$wide
na_reasons_long    <- na_result$long

# -- Save outputs -------------------------------------------------------------
output_base <- sub("\\.csv$", "", cfg$output_csv)

na_reasons_wide_path <- paste0(output_base, "_na_reasons.csv.gz")
na_reasons_long_path <- paste0(output_base, "_na_reasons_long.csv.gz")

tryCatch({
  readr::write_csv(df_na_reasons, na_reasons_wide_path, na = "")
  log_info("NA reasons (wide) saved: %s", na_reasons_wide_path)
}, error = function(e) log_warn("Could not save NA reasons wide CSV: %s", e$message))

if (isTRUE(cfg$save_na_reasons_long)) {
  tryCatch({
    readr::write_csv(na_reasons_long, na_reasons_long_path, na = "")
    log_info("NA reasons (long) saved: %s", na_reasons_long_path)
  }, error = function(e) log_warn("Could not save NA reasons long CSV: %s", e$message))
} else {
  log_info("NA reasons (long) skipped (SAVE_NA_REASONS_LONG = FALSE).")
}

# -- Per-variable missingness summary ------------------------------------------
key_cols_16  <- intersect(c("uid", "facility", "uniquekey"), names(df_clean))
data_cols_16 <- setdiff(names(df_clean), key_cols_16)
var_summary  <- build_variable_summary(na_reasons_long, nrow(df_clean), data_cols_16)

na_summary_path <- paste0(output_base, "_na_reasons_summary.csv")
tryCatch({
  readr::write_csv(var_summary, na_summary_path, na = "")
  log_info("NA reasons (summary) saved: %s", na_summary_path)
}, error = function(e) log_warn("Could not save NA reasons summary CSV: %s", e$message))

# -- NA-coded output ----------------------------------------------------------
# A copy of the cleaned file where every NA cell is replaced by its reason code
# (-6/-7/-8/-9).  Controlled by cfg$save_na_coded.
na_coded_path <- sub("\\.csv$", "_na_coded.csv", cfg$output_csv)
if (isTRUE(cfg$save_na_coded)) {
  tryCatch({
    df_na_coded <- build_clean_coded(df_clean, df_na_reasons)
    readr::write_csv(df_na_coded, na_coded_path, na = "")
    log_info("NA-coded file saved: %s", na_coded_path)
  }, error = function(e) log_warn("Could not save NA-coded CSV: %s", e$message))
} else {
  log_info("NA-coded file skipped (SAVE_NA_CODED = FALSE).")
}

# -- Module report -------------------------------------------------------------
if (!is.null(cfg$report_dir)) {
  report_path <- file.path(cfg$report_dir, "16_na_reason_coding_summary.txt")
  tryCatch({
    counts <- na_result$counts
    total  <- sum(unlist(counts))
    pct <- function(n) sprintf("%.1f%%", 100 * n / max(total, 1))

    # Top-20 most-missing variables for the text report
    top_n  <- min(20L, nrow(var_summary))
    top_df <- var_summary[seq_len(top_n), ]
    # Column widths
    max_var_w <- max(nchar(top_df$variable), nchar("Variable"), na.rm = TRUE)
    fmt_hdr <- sprintf("  %%-%ds  %%6s  %%7s  %%6s  %%6s  %%6s  %%6s",
                       max_var_w)
    fmt_row <- sprintf("  %%-%ds  %%6d  %%6.1f%%%%  %%6d  %%6d  %%6d  %%6d",
                       max_var_w)
    tbl_header <- sprintf(fmt_hdr,
      "Variable", "N", "%Miss", "-7NA", "-8Inv", "-9Unk", "-6Red")
    tbl_sep    <- paste(rep("-", nchar(tbl_header)), collapse = "")
    tbl_rows   <- mapply(function(v, nt, pm, nap, inv, unk, red)
        sprintf(fmt_row, v, nt, pm, nap, inv, unk, red),
      top_df$variable, top_df$n_total, top_df$pct_missing,
      top_df$n_not_applicable, top_df$n_invalid,
      top_df$n_unknown, top_df$n_redacted,
      SIMPLIFY = TRUE)

    lines <- c(
      "NA Reason Coding Summary",
      "========================",
      sprintf("Country              : %s", toupper(cfg$country)),
      sprintf("Dataset              : %s", cfg$dataset),
      sprintf("Input CSV            : %s", cfg$csv_filepath),
      sprintf("Scripts directory    : %s", cfg$neotree_scripts_dir),
      sprintf("Scripts loaded       : %d", nrow(scripts_data$index)),
      sprintf("Total NA cells coded : %d", total),
      "",
      "Overall NA Reason Breakdown:",
      sprintf("  -6  Redacted (PII)      : %6d  (%s)", counts$redacted,  pct(counts$redacted)),
      sprintf("  -7  Not applicable      : %6d  (%s)", counts$notapplic, pct(counts$notapplic)),
      sprintf("  -8  Invalid / removed   : %6d  (%s)", counts$invalid,   pct(counts$invalid)),
      sprintf("  -9  Unknown             : %6d  (%s)", counts$unknown,   pct(counts$unknown)),
      "",
      sprintf("Per-Variable Missingness (top %d by %% missing, all variables in summary CSV):",
              top_n),
      tbl_sep,
      tbl_header,
      tbl_sep,
      tbl_rows,
      tbl_sep,
      "",
      sprintf("Output (wide)    : %s", na_reasons_wide_path),
      sprintf("Output (long)    : %s",
              if (isTRUE(cfg$save_na_reasons_long)) na_reasons_long_path else "(skipped)"),
      sprintf("Output (summary) : %s", na_summary_path),
      sprintf("Output (na_coded): %s",
              if (isTRUE(cfg$save_na_coded)) na_coded_path else "(skipped)"),
      sprintf("Run timestamp    : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    )
    writeLines(lines, report_path)
  }, error = function(e) log_warn("Could not write module 16 report: %s", e$message))
}

log_info("Module 16 complete.")
