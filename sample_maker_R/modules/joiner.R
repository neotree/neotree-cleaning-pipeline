################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/joiner.R
# PURPOSE: Match admissions to discharges using uid + facility as the unique
#          key, producing three output datasets.
#
# MATCHING LOGIC
#   1. A match_key column (uid + "_" + facility) is added to both data frames.
#   2. Set intersection  -> matched pairs
#   3. Admissions with no discharge found    -> unmatched_admissions
#      (baby still admitted, or discharge record missing / entered under
#       different uid/facility)
#   4. Discharges with no corresponding admission in the filtered set
#      -> unmatched_discharges
#      (admission outside the selected date window, or missing admission record)
#
# MATCHED PAIRS DATASET
#   All admission columns are retained as-is.
#   Discharge columns that share a name with an admission column (except
#   match_key) are suffixed with "_dis" to avoid ambiguity.
#
# FUNCTION EXPORTED
#   join_data(admissions, discharges)
#     -> returns list(matched_pairs, unmatched_admissions, unmatched_discharges,
#                    n_matched, n_unmatched_adm, n_unmatched_dis,
#                    n_adm_total, n_dis_total)
################################################################################

join_data <- function(admissions, discharges) {

  cat("[joiner] Creating match keys (uid + facility)...\n")

  admissions$match_key <- paste(admissions$uid, admissions$facility, sep = "_")
  discharges$match_key <- paste(discharges$uid, discharges$facility, sep = "_")

  n_adm_unique <- length(unique(admissions$match_key))
  n_dis_unique <- length(unique(discharges$match_key))
  cat(sprintf("[joiner]   Unique admission keys : %d\n", n_adm_unique))
  cat(sprintf("[joiner]   Unique discharge keys : %d\n\n", n_dis_unique))

  # ---------------------------------------------------------------------------
  # Set operations
  # ---------------------------------------------------------------------------
  adm_keys          <- admissions$match_key
  dis_keys          <- discharges$match_key

  matched_keys       <- intersect(adm_keys, dis_keys)
  unmatched_adm_keys <- setdiff(adm_keys, dis_keys)
  unmatched_dis_keys <- setdiff(dis_keys, adm_keys)

  n_matched       <- length(matched_keys)
  n_unmatched_adm <- length(unmatched_adm_keys)
  n_unmatched_dis <- length(unmatched_dis_keys)

  n_adm <- nrow(admissions)
  n_dis <- nrow(discharges)

  cat(sprintf(
    "[joiner] Matching results:\n  Matched pairs        : %d  (%.1f%% of admissions | %.1f%% of discharges)\n  Unmatched admissions : %d  (%.1f%%)\n  Unmatched discharges : %d  (%.1f%%)\n\n",
    n_matched,
    100 * n_matched / n_adm,
    100 * n_matched / n_dis,
    n_unmatched_adm, 100 * n_unmatched_adm / n_adm,
    n_unmatched_dis, 100 * n_unmatched_dis / n_dis
  ))

  # ---------------------------------------------------------------------------
  # Subset rows
  # ---------------------------------------------------------------------------
  adm_matched    <- admissions[admissions$match_key %in% matched_keys, ]
  dis_matched    <- discharges[discharges$match_key %in% matched_keys, ]
  unmatched_adm  <- admissions[admissions$match_key %in% unmatched_adm_keys, ]
  unmatched_dis  <- discharges[discharges$match_key %in% unmatched_dis_keys, ]

  # ---------------------------------------------------------------------------
  # Build matched pairs dataset
  # ---------------------------------------------------------------------------
  cat("[joiner] Building matched pairs dataset...\n")

  # Sort both by match_key so rows align correctly after merging
  adm_matched <- adm_matched[order(adm_matched$match_key), ]
  dis_matched <- dis_matched[order(dis_matched$match_key), ]

  # Rename overlapping discharge columns (except match_key) -> add _dis suffix
  adm_cols <- names(adm_matched)
  dis_cols <- names(dis_matched)
  overlap  <- setdiff(intersect(adm_cols, dis_cols), "match_key")

  if (length(overlap) > 0) {
    cat(sprintf(
      "[joiner]   %d column(s) shared between admissions and discharges -- adding '_dis' suffix to discharge copies:\n  %s\n",
      length(overlap),
      paste(head(overlap, 10), collapse = ", ")
    ))
    names(dis_matched)[names(dis_matched) %in% overlap] <-
      paste0(names(dis_matched)[names(dis_matched) %in% overlap], "_dis")
  }

  matched_pairs <- cbind(
    adm_matched,
    dis_matched[, names(dis_matched) != "match_key", drop = FALSE]
  )

  cat(sprintf(
    "[joiner]   Matched pairs dataset : %d rows x %d columns\n\n",
    nrow(matched_pairs), ncol(matched_pairs)
  ))

  # ---------------------------------------------------------------------------
  # Neotree outcome summary for matched pairs
  # ---------------------------------------------------------------------------
  outcome_col <- .find_outcome_col(matched_pairs)
  outcome_summary <- .build_outcome_summary(matched_pairs, outcome_col)

  list(
    matched_pairs      = matched_pairs,
    unmatched_adm      = unmatched_adm,
    unmatched_dis      = unmatched_dis,
    n_matched          = n_matched,
    n_unmatched_adm    = n_unmatched_adm,
    n_unmatched_dis    = n_unmatched_dis,
    n_adm_total        = n_adm,
    n_dis_total        = n_dis,
    outcome_col        = outcome_col,
    outcome_summary    = outcome_summary
  )
}

# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------
.find_outcome_col <- function(df) {
  if ("neotreeoutcome" %in% names(df))     return("neotreeoutcome")
  if ("neotreeoutcome_dis" %in% names(df)) return("neotreeoutcome_dis")
  return(NULL)
}

.build_outcome_summary <- function(matched_pairs, outcome_col) {
  if (is.null(outcome_col)) {
    return(list(
      lines       = "  [neotreeoutcome column not found in matched pairs dataset]",
      col_used    = NULL
    ))
  }

  outcomes      <- matched_pairs[[outcome_col]]
  outcome_table <- sort(table(outcomes, useNA = "ifany"), decreasing = TRUE)
  total         <- nrow(matched_pairs)

  header <- c(
    sprintf("  Outcome column used : %s", outcome_col),
    sprintf("  Total matched pairs : %d", total),
    "",
    sprintf("  %-35s  %6s  %6s", "Outcome", "N", "%"),
    sprintf("  %-35s  %6s  %6s", strrep("-", 35), strrep("-", 6), strrep("-", 6))
  )

  rows <- vapply(seq_along(outcome_table), function(i) {
    label <- names(outcome_table)[i]
    if (is.na(label)) label <- "(missing / NA)"
    sprintf("  %-35s  %6d  %5.1f%%", label, outcome_table[i],
            100 * outcome_table[i] / total)
  }, character(1))

  # Facility breakdown
  fac_table <- sort(table(matched_pairs$facility), decreasing = TRUE)
  fac_header <- c("", "  Matched pairs by facility:")
  fac_rows <- vapply(seq_along(fac_table), function(i) {
    sprintf("    %-20s  %6d  %5.1f%%",
            names(fac_table)[i], fac_table[i],
            100 * fac_table[i] / total)
  }, character(1))

  list(
    lines    = c(header, rows, fac_header, fac_rows),
    col_used = outcome_col
  )
}
