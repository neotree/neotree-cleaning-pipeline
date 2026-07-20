################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/master_builder.R
# PURPOSE: Assembles the two master datasets from the join and prob-matching
#          results.
#
# MASTER JOINED  (master_joined)
#   Contains ALL selected admissions, regardless of whether a matching discharge
#   was found.  Useful for admission-level analyses (clinical characteristics,
#   rates of various diagnoses) where discharge outcome is not required.
#
#   Row composition:
#     * Matched admissions   -- full admission + discharge data  (match_type = "direct_match")
#     * Unmatched admissions -- admission data only; discharge cols = NA  (match_type = "unmatched")
#
#   Columns:
#     * All admission columns (from matched_pairs)
#     * All discharge columns (overlapping ones with "_dis" suffix, as in joined file)
#     * match_type     : "direct_match" | "unmatched"
#     * prob_match_similarity : NA for all rows
#
# MASTER JOINED EXTENDED  (master_joined_extended)
#   Extends master_joined by upgrading unmatched admissions that received a
#   probabilistic match.
#
#   Row composition:
#     * Direct matched pairs       (match_type = "direct_match")
#     * Probabilistically matched  (match_type = "prob_match")
#     * Still unmatched admissions (match_type = "unmatched")
#
#   Columns: identical to master_joined, plus:
#     * prob_match_similarity : match score (0-100) for prob_match rows; NA otherwise
#
# FUNCTIONS EXPORTED
#   build_master_joined(matched_pairs, unmatched_adm)
#     -> master_joined data frame
#
#   build_master_joined_extended(master_joined, assignments, unmatched_adm_df,
#                                unmatched_dis_df)
#     -> master_joined_extended data frame
################################################################################

# ==============================================================================
# 1. build_master_joined()
# ==============================================================================
build_master_joined <- function(matched_pairs, unmatched_adm) {

  cat("[master] Building master_joined dataset...\n")

  # --- Tag the matched pairs ---
  mp <- matched_pairs
  mp$match_type            <- "direct_match"
  mp$prob_match_similarity <- NA_real_

  # --- Pad unmatched admissions with NA discharge columns ---
  ua <- unmatched_adm

  # All columns in matched_pairs that are absent from unmatched_adm -> add as NA
  missing_from_ua <- setdiff(names(mp), names(ua))
  for (col in missing_from_ua) {
    ua[[col]] <- NA
  }

  # Explicitly tag unmatched rows -- the generic loop above would set these to NA
  ua$match_type            <- "unmatched"
  ua$prob_match_similarity <- NA_real_

  # Reorder to match column order of matched_pairs exactly
  ua <- ua[, names(mp), drop = FALSE]

  # --- Bind ---
  master <- rbind(mp, ua)

  cat(sprintf(
    "[master]   master_joined : %d rows  (%d direct_match + %d unmatched)\n\n",
    nrow(master), nrow(mp), nrow(ua)
  ))

  master
}

# ==============================================================================
# 2. build_master_joined_extended()
# ==============================================================================
build_master_joined_extended <- function(master_joined,
                                          assignments,
                                          unmatched_adm_df,
                                          unmatched_dis_df) {

  cat("[master] Building master_joined_extended dataset...\n")

  if (nrow(assignments) == 0) {
    cat("[master]   No probabilistic assignments -- master_joined_extended equals master_joined.\n\n")
    mje <- master_joined
    mje$prob_match_similarity <- NA_real_
    return(mje)
  }

  # -------------------------------------------------------------------------
  # Identify which columns in master_joined came from the discharge side.
  # These are: columns that appear in unmatched_dis_df (possibly with _dis
  # suffix for overlapping names), plus match_key_dis.
  #
  # Strategy: look at master_joined column names and identify the discharge-
  # originated subset by comparing against matched_pairs structure.
  # The overlap columns in matched_pairs carry "_dis" suffix; other discharge
  # columns keep their original names.
  # We detect discharge columns as: all columns NOT in the original admissions
  # (unmatched_adm_df), except the housekeeping cols added by the pipeline.
  # -------------------------------------------------------------------------
  pipeline_cols  <- c("match_type", "prob_match_similarity", "match_key")
  adm_col_names  <- names(unmatched_adm_df)

  dis_col_names_in_master <- setdiff(names(master_joined),
                                     c(adm_col_names, pipeline_cols))

  # Build a mapping: actual column name in master_joined -> original col name in
  # unmatched_dis_df.
  # Columns ending in "_dis" are overlapping cols whose original name is col
  # minus the suffix.
  dis_col_map <- character(0)
  for (col in dis_col_names_in_master) {
    if (grepl("_dis$", col)) {
      orig <- sub("_dis$", "", col)
      if (orig %in% names(unmatched_dis_df)) dis_col_map[col] <- orig
    } else {
      if (col %in% names(unmatched_dis_df)) dis_col_map[col] <- col
    }
  }

  # -------------------------------------------------------------------------
  # For each accepted assignment, build one row with the structure of
  # master_joined: admission data from unmatched_adm_df, discharge data from
  # unmatched_dis_df, match_type = "prob_match".
  # -------------------------------------------------------------------------
  n_assign <- nrow(assignments)

  prob_rows <- vector("list", n_assign)

  for (k in seq_len(n_assign)) {
    ai  <- assignments$adm_row_idx[k]
    di  <- assignments$dis_row_idx[k]
    sim <- assignments$overall_similarity[k]

    # Start with the existing "unmatched" row in master_joined for this admission
    # (which already has the right column structure but NA discharge cols)
    # Identify the row by adm_row_idx: this maps to unmatched_adm_df row ai,
    # which corresponds to the row in master_joined where match_type == "unmatched"
    # and uid + facility match.
    uid_ai  <- unmatched_adm_df$uid[ai]
    fac_ai  <- unmatched_adm_df$facility[ai]

    uid_match <- if (is.na(uid_ai))  is.na(master_joined$uid)  else
                   !is.na(master_joined$uid)  & master_joined$uid  == uid_ai
    fac_match <- if (is.na(fac_ai)) is.na(master_joined$facility) else
                   !is.na(master_joined$facility) & master_joined$facility == fac_ai

    mj_mask <- master_joined$match_type == "unmatched" & uid_match & fac_match

    if (sum(mj_mask) != 1) {
      # Fallback: rebuild from unmatched_adm_df row
      base_row <- unmatched_adm_df[ai, , drop = FALSE]
      for (mc in names(master_joined)) {
        if (!mc %in% names(base_row)) base_row[[mc]] <- NA
      }
      base_row <- base_row[, names(master_joined), drop = FALSE]
    } else {
      base_row <- master_joined[which(mj_mask)[1], , drop = FALSE]
    }

    # Fill discharge columns from the matched discharge row
    dis_row <- unmatched_dis_df[di, , drop = FALSE]
    for (master_col in names(dis_col_map)) {
      orig_dis_col <- dis_col_map[[master_col]]
      if (orig_dis_col %in% names(dis_row)) {
        base_row[[master_col]] <- dis_row[[orig_dis_col]]
      }
    }

    base_row$match_type            <- "prob_match"
    base_row$prob_match_similarity <- sim

    prob_rows[[k]] <- base_row
  }

  prob_df <- do.call(rbind, prob_rows)

  # -------------------------------------------------------------------------
  # Assemble master_joined_extended:
  #   * direct_match rows  (unchanged)
  #   * prob_match rows    (new, from prob_df)
  #   * unmatched rows     (those NOT in the prob assignments)
  # -------------------------------------------------------------------------

  # UIDs of admissions that were prob-matched
  prob_adm_uids <- assignments$adm_uid
  prob_adm_facs <- assignments$adm_facility

  # Key for lookup (uid_facility)
  mj_key <- paste(master_joined$uid, master_joined$facility, sep = "_")
  prob_key <- paste(prob_adm_uids, prob_adm_facs, sep = "_")

  direct_rows    <- master_joined[master_joined$match_type == "direct_match", ]
  still_unmatched <- master_joined[
    master_joined$match_type == "unmatched" & !mj_key %in% prob_key,
  ]

  mje <- rbind(direct_rows, prob_df, still_unmatched)
  rownames(mje) <- NULL

  n_dm  <- nrow(direct_rows)
  n_pm  <- nrow(prob_df)
  n_um  <- nrow(still_unmatched)

  cat(sprintf(
    "[master]   master_joined_extended : %d rows  (%d direct_match + %d prob_match + %d unmatched)\n\n",
    nrow(mje), n_dm, n_pm, n_um
  ))

  mje
}
