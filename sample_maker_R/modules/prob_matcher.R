################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/prob_matcher.R
# PURPOSE: Probabilistic matching of unmatched admissions to unmatched
#          discharges using shared clinical variables.
#
# WHY RECORDS ARE UNMATCHED
#   Direct uid+facility matching fails when:
#     * UID was mistyped on admission or discharge form
#     * Facility name differs between the two records
#     * One record was never submitted / synced
#   Probabilistic matching uses clinical fingerprints (birthweight, gestation,
#   temperature, etc.) to recover as many of these pairs as possible.
#
# APPROACH
#   1. Auto-detect matching variables: shared columns that exist in both
#      admissions and discharges with >= COMPLETENESS_THRESHOLD non-NA values.
#   2. Score every unmatched_adm x unmatched_dis pair within the same facility
#      (facility blocking).  Optionally, a second cross-facility pass covers
#      admissions that found no within-facility candidate.
#   3. Greedy one-to-one assignment: sort all candidates by similarity
#      descending; accept the top pair; remove both from the pool; repeat.
#      Every admission and every discharge appears in at most one assignment.
#
# SIMILARITY SCORING  (per variable, combined as simple mean)
#   Numeric:
#     diff = 0              -> 100
#     0 < diff <= tol        -> linear decay 100 -> ~0
#     tol < diff <= 2xtol   -> continues to decay to 0
#     diff > 2xtol          -> 0
#     either value NA       -> variable excluded from denominator
#   Categorical:
#     exact string match    -> 100
#     mismatch or NA        -> 0 (NA excluded from denominator)
#
# FUNCTIONS EXPORTED
#   detect_match_variables(adm_full, dis_full, cfg)
#     -> list(vars, tolerances, col_map_adm, col_map_dis)
#
#   find_prob_candidates(unmatched_adm, unmatched_dis, var_info, cfg)
#     -> data frame of candidate pairs (top N per admission, above threshold)
#
#   assign_one_to_one(candidates)
#     -> data frame of accepted assignments (uid/facility/score per pair)
################################################################################

# Default candidate variables and their tolerances
# The function will only use those present and complete enough in the data.
PROB_CANDIDATE_VARS <- c(
  "birthweight", "gestation", "temperature",
  "apgar1", "apgar5", "apgar10",
  "gender", "ofc", "modedelivery", "typebirth"
)

# Default tolerance per variable (used when not specified in cfg)
PROB_DEFAULT_TOLERANCES <- list(
  birthweight  = 50,   # grams
  gestation    = 1,    # weeks
  ofc          = 1,    # cm
  temperature  = 0.5,  # degrees Celsius
  apgar1       = 0,    # exact (integer)
  apgar5       = 0,    # exact
  apgar10      = 0,    # exact
  gender       = 0,    # categorical
  modedelivery = 0,    # categorical
  typebirth    = 0     # categorical
)

# ==============================================================================
# 1. detect_match_variables()
# ==============================================================================
# Returns a var_info list describing which variables to use and their actual
# column names in each data frame.

detect_match_variables <- function(adm_full, dis_full, cfg) {

  threshold <- cfg$prob_match_completeness_threshold

  cat(sprintf(
    "[prob_matcher] Detecting matching variables (completeness threshold: %.0f%%)...\n",
    threshold * 100
  ))

  vars       <- list()   # var_name -> TRUE
  tolerances <- list()   # var_name -> numeric tolerance
  col_map_adm <- list()  # var_name -> actual column name in admissions
  col_map_dis <- list()  # var_name -> actual column name in discharges

  # Tolerance lookup: config overrides default
  get_tol <- function(var) {
    cfg_key <- paste0("prob_match_", var, "_tolerance")
    if (!is.null(cfg[[cfg_key]])) cfg[[cfg_key]] else PROB_DEFAULT_TOLERANCES[[var]] %||% 0
  }

  # Column resolver: returns the column name if present, or NULL
  resolve_col <- function(df, var) {
    if (var %in% names(df)) return(var)
    return(NULL)
  }

  for (var in PROB_CANDIDATE_VARS) {
    col_adm <- resolve_col(adm_full, var)
    col_dis <- resolve_col(dis_full, var)

    if (is.null(col_adm) || is.null(col_dis)) next  # not in one of the files

    # Completeness check (on the full files, not just unmatched subsets)
    pct_adm <- mean(!is.na(adm_full[[col_adm]]) & adm_full[[col_adm]] != "")
    pct_dis <- mean(!is.na(dis_full[[col_dis]]) & dis_full[[col_dis]] != "")

    if (pct_adm < threshold || pct_dis < threshold) next

    # Determine numeric vs categorical from the full admissions column
    col_vals <- suppressWarnings(as.numeric(adm_full[[col_adm]]))
    is_num   <- mean(!is.na(col_vals)) > 0.5  # majority parseable as numeric

    tol <- if (is_num) get_tol(var) else 0

    vars[[var]]        <- is_num
    tolerances[[var]]  <- tol
    col_map_adm[[var]] <- col_adm
    col_map_dis[[var]] <- col_dis

    cat(sprintf(
      "[prob_matcher]   [ok] %-14s  adm: %4.0f%%  dis: %4.0f%%  type: %-10s  tol: %s\n",
      var,
      pct_adm * 100, pct_dis * 100,
      ifelse(is_num, "numeric", "categorical"),
      ifelse(tol == 0, "exact", as.character(tol))
    ))
  }

  n <- length(vars)
  if (n == 0) {
    warning("[prob_matcher] No suitable matching variables found. Probabilistic matching skipped.")
  } else {
    cat(sprintf("[prob_matcher] %d variable(s) selected for matching.\n\n", n))
  }

  list(
    vars        = vars,
    tolerances  = tolerances,
    col_map_adm = col_map_adm,
    col_map_dis = col_map_dis
  )
}

# ==============================================================================
# 2. find_prob_candidates()
# ==============================================================================
# Searches unmatched_adm against unmatched_dis.
# Returns a data frame of candidate pairs with similarity scores.

find_prob_candidates <- function(unmatched_adm, unmatched_dis, var_info, cfg) {

  if (length(var_info$vars) == 0 || nrow(unmatched_adm) == 0 || nrow(unmatched_dis) == 0) {
    cat("[prob_matcher] Skipping candidate search (no variables or empty inputs).\n\n")
    return(data.frame())
  }

  min_score   <- cfg$prob_match_min_similarity
  max_cands   <- cfg$prob_match_max_candidates
  cross_fac   <- isTRUE(cfg$prob_match_cross_facility)

  # Pre-convert matching columns to numeric where appropriate
  adm_numeric <- .preprocess_match_cols(unmatched_adm, var_info, side = "adm")
  dis_numeric <- .preprocess_match_cols(unmatched_dis, var_info, side = "dis")

  # Build facility index for discharge pool
  dis_facility_idx <- split(seq_len(nrow(unmatched_dis)), unmatched_dis$facility)

  n_adm      <- nrow(unmatched_adm)
  pb_step    <- max(1L, floor(n_adm / 20L))
  all_cands  <- vector("list", n_adm)

  cat(sprintf("[prob_matcher] Searching %d unmatched admissions against %d unmatched discharges...\n",
              n_adm, nrow(unmatched_dis)))

  for (i in seq_len(n_adm)) {

    if (i %% pb_step == 0L) {
      cat(sprintf("  Progress: %d/%d (%.0f%%)\r", i, n_adm, 100 * i / n_adm))
    }

    q_fac <- unmatched_adm$facility[i]

    # Determine search pool
    search_idx <- if (!is.na(q_fac) && as.character(q_fac) %in% names(dis_facility_idx)) {
      dis_facility_idx[[as.character(q_fac)]]
    } else {
      integer(0)
    }

    # Cross-facility fallback: if no within-facility candidates and cross_fac enabled
    if (length(search_idx) == 0 && cross_fac) {
      search_idx <- seq_len(nrow(unmatched_dis))
    }

    if (length(search_idx) == 0) next

    scores <- .score_candidates(
      i, search_idx,
      adm_numeric, dis_numeric,
      var_info
    )

    # Filter by minimum similarity
    keep <- which(scores >= min_score)
    if (length(keep) == 0) next

    # Sort and take top max_cands
    keep  <- keep[order(scores[keep], decreasing = TRUE)]
    keep  <- head(keep, max_cands)

    rows <- lapply(keep, function(j) {
      dis_idx <- search_idx[j]
      row     <- data.frame(
        adm_row_idx        = i,
        dis_row_idx        = dis_idx,
        overall_similarity = scores[j],
        adm_uid            = unmatched_adm$uid[i],
        adm_facility       = unmatched_adm$facility[i],
        dis_uid            = unmatched_dis$uid[dis_idx],
        dis_facility       = unmatched_dis$facility[dis_idx],
        same_facility      = identical(
          as.character(unmatched_adm$facility[i]),
          as.character(unmatched_dis$facility[dis_idx])
        ),
        stringsAsFactors   = FALSE
      )
      # Per-variable similarity scores
      for (var in names(var_info$vars)) {
        row[[paste0("sim_", var)]] <- .score_one(
          adm_numeric[[var]][i],
          dis_numeric[[var]][dis_idx],
          var_info$vars[[var]],
          var_info$tolerances[[var]]
        )
        row[[paste0("adm_", var)]] <- unmatched_adm[[ var_info$col_map_adm[[var]] ]][i]
        row[[paste0("dis_", var)]] <- unmatched_dis[[ var_info$col_map_dis[[var]] ]][dis_idx]
      }
      row
    })

    all_cands[[i]] <- do.call(rbind, rows)
  }

  cat(sprintf("  Progress: %d/%d (100%%)\n", n_adm, n_adm))

  result <- do.call(rbind, Filter(Negate(is.null), all_cands))
  if (is.null(result)) result <- data.frame()

  n_cands <- if (nrow(result) > 0) nrow(result) else 0
  n_adm_w_cands <- if (nrow(result) > 0) length(unique(result$adm_row_idx)) else 0

  cat(sprintf(
    "[prob_matcher] Found %d candidate pair(s) for %d / %d unmatched admissions.\n\n",
    n_cands, n_adm_w_cands, n_adm
  ))

  result
}

# ==============================================================================
# 3. assign_one_to_one()
# ==============================================================================
# Greedy one-to-one assignment from candidates.
# Guarantees each admission and each discharge appears in at most one pair.

assign_one_to_one <- function(candidates) {

  if (nrow(candidates) == 0) {
    cat("[prob_matcher] No candidates to assign.\n\n")
    return(data.frame())
  }

  # Sort by similarity descending
  cands_sorted <- candidates[order(-candidates$overall_similarity), ]

  assigned_adm <- integer(0)
  assigned_dis <- integer(0)
  accepted     <- vector("list", nrow(cands_sorted))
  n_accepted   <- 0L

  for (i in seq_len(nrow(cands_sorted))) {
    r   <- cands_sorted[i, ]
    ai  <- r$adm_row_idx
    di  <- r$dis_row_idx

    if (ai %in% assigned_adm || di %in% assigned_dis) next

    n_accepted           <- n_accepted + 1L
    accepted[[n_accepted]] <- r
    assigned_adm         <- c(assigned_adm, ai)
    assigned_dis         <- c(assigned_dis, di)
  }

  assignments <- if (n_accepted > 0) {
    do.call(rbind, accepted[seq_len(n_accepted)])
  } else {
    data.frame()
  }

  cat(sprintf(
    "[prob_matcher] One-to-one assignment: %d pair(s) accepted from %d candidate(s).\n\n",
    n_accepted, nrow(candidates)
  ))

  assignments
}

# ==============================================================================
# Internal helpers
# ==============================================================================

# Null-coalescing operator (used in detect_match_variables)
`%||%` <- function(a, b) if (!is.null(a)) a else b

# Pre-convert matching columns to numeric vectors (NA where non-numeric)
.preprocess_match_cols <- function(df, var_info, side) {
  result <- list()
  col_map <- if (side == "adm") var_info$col_map_adm else var_info$col_map_dis
  for (var in names(var_info$vars)) {
    is_num <- var_info$vars[[var]]
    col    <- col_map[[var]]
    if (is_num) {
      result[[var]] <- suppressWarnings(as.numeric(df[[col]]))
    } else {
      result[[var]] <- as.character(df[[col]])
    }
  }
  result
}

# Score one query value against a vector of search values
.score_candidates <- function(query_i, search_idx,
                               adm_num, dis_num, var_info) {

  n_search  <- length(search_idx)
  total     <- numeric(n_search)
  n_valid   <- numeric(n_search)

  for (var in names(var_info$vars)) {
    q_val <- adm_num[[var]][query_i]
    s_vals <- dis_num[[var]][search_idx]

    # Skip variable if query is NA
    if (length(q_val) == 0 || is.na(q_val)) next

    is_num <- var_info$vars[[var]]
    tol    <- var_info$tolerances[[var]]

    if (is_num) {
      s_num  <- s_vals  # already numeric
      valid  <- !is.na(s_num)
      diffs  <- abs(q_val - s_num)

      scores <- ifelse(!valid, 0,
        ifelse(diffs == 0, 100,
          ifelse(tol == 0, 0,
            ifelse(diffs <= tol, 100 * (1 - diffs / tol),
              ifelse(diffs <= tol * 2, 50 * (1 - (diffs - tol) / tol), 0)
            )
          )
        )
      )
    } else {
      valid  <- !is.na(s_vals) & s_vals != ""
      scores <- ifelse(valid & as.character(q_val) == s_vals, 100, 0)
    }

    total   <- total   + scores
    n_valid <- n_valid + as.numeric(valid)
  }

  ifelse(n_valid > 0, total / n_valid, 0)
}

# Score a single (query, match) value pair -- used for per-variable reporting
.score_one <- function(q_val, m_val, is_num, tol) {
  if (is.na(q_val) || is.na(m_val)) return(NA_real_)
  if (is_num) {
    diff <- abs(q_val - m_val)
    if (diff == 0)                 return(100)
    if (tol == 0)                  return(0)
    if (diff <= tol)               return(100 * (1 - diff / tol))
    if (diff <= tol * 2)           return(50 * (1 - (diff - tol) / tol))
    return(0)
  } else {
    return(if (as.character(q_val) == as.character(m_val)) 100 else 0)
  }
}
