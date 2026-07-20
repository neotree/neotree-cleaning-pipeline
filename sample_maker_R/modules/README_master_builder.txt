================================================================================
  Neotree Sample Maker — modules/master_builder.R
  README: Assembly of master_joined and master_joined_extended datasets
================================================================================

PURPOSE
-------
master_builder.R assembles the two master datasets that form the primary
deliverables of the pipeline.  It combines join results and probabilistic
matching results into unified, analysis-ready data frames.

This module provides two functions, called at STEPS 9 and 12 of
run_sample_maker.R.


================================================================================
EXPORTED FUNCTIONS
================================================================================

1.  build_master_joined(matched_pairs, unmatched_adm)
    Combines direct matches and unmatched admissions into one data frame.
    Returns master_joined.

2.  build_master_joined_extended(master_joined, assignments,
                                  unmatched_adm_df, unmatched_dis_df)
    Upgrades unmatched admissions using probabilistic assignment results.
    Returns master_joined_extended.


================================================================================
MASTER_JOINED
================================================================================

PURPOSE
  master_joined contains ALL filtered admissions — whether or not a discharge
  was found.  It is the primary dataset for admission-level analyses (clinical
  characteristics, admission rates, diagnoses) where discharge outcome is not
  always required.

COMPOSITION
  Direct match rows  (match_type = "direct_match"):
    Sourced from matched_pairs.
    All admission columns + all discharge columns (overlapping cols with "_dis"
    suffix as produced by joiner.R).

  Unmatched admission rows  (match_type = "unmatched"):
    Sourced from unmatched_adm.
    All admission columns + all discharge columns = NA.

ADDED COLUMNS
  match_type              "direct_match" or "unmatched"
  prob_match_similarity   NA_real_ for all rows in master_joined

CONSTRUCTION
  1. Tag matched_pairs with match_type = "direct_match" and
     prob_match_similarity = NA.
  2. Identify columns present in matched_pairs but absent from unmatched_adm
     (these are all the discharge columns).
  3. Add those columns to unmatched_adm as NA.
  4. Reorder unmatched_adm columns to match matched_pairs exactly.
  5. rbind() the two data frames.

Total rows = n_direct_match + n_unmatched = all filtered admissions.


================================================================================
MASTER_JOINED_EXTENDED
================================================================================

PURPOSE
  master_joined_extended extends master_joined by filling in discharge data
  for admissions that were probabilistically matched.  It is recommended when
  discharge outcomes are needed and you want maximum coverage.

COMPOSITION
  Direct match rows    (match_type = "direct_match"):
    Unchanged from master_joined.

  Probabilistic match rows  (match_type = "prob_match"):
    Admissions that were unmatched after the direct join but accepted by
    the probabilistic matching algorithm.
    Discharge columns filled from the matched unmatched discharge record.
    prob_match_similarity = the overall similarity score (0–100).

  Still-unmatched rows  (match_type = "unmatched"):
    Admissions that remain unmatched after both direct and probabilistic
    matching.  Discharge columns = NA.

CONSTRUCTION
  1. If no probabilistic assignments: return master_joined unchanged
     (just ensuring prob_match_similarity column is present as NA).

  2. Detect which columns in master_joined came from the discharge side:
     Discharge columns = all columns NOT in the original admissions and
     NOT in the pipeline housekeeping columns (match_type, prob_match_similarity,
     match_key).

  3. Build dis_col_map: a named character vector mapping
     master_joined column name → original column name in unmatched_dis_df.
     Columns with "_dis" suffix: strip the suffix to get the original name.
     Other columns: name is already the original discharge column name.
     This map is used to correctly fill discharge values for prob-matched rows.

  4. For each accepted probabilistic assignment (k):
     a. Find the corresponding "unmatched" row in master_joined by matching
        uid + facility.
     b. Start with that row (which already has the correct column structure
        but NA in all discharge columns).
     c. For each discharge column in dis_col_map, fill the value from
        unmatched_dis_df[assignment$dis_row_idx].
     d. Set match_type = "prob_match" and prob_match_similarity = score.

  5. Assemble master_joined_extended:
     direct_match rows     (from master_joined, unchanged)
     rbind prob_match rows (newly built)
     rbind still_unmatched (unmatched rows whose uid+facility is NOT in
                             the prob assignments)
     Reset row names.


================================================================================
COLUMN STRUCTURE
================================================================================

Both master datasets have the same column structure:
  All admission columns
  All discharge columns (overlapping ones with "_dis" suffix)
  match_type              "direct_match", "prob_match", or "unmatched"
  prob_match_similarity   numeric score for "prob_match" rows; NA otherwise

This uniform structure makes it easy to use either dataset in downstream
analyses with the same code — simply filter by match_type if needed.


================================================================================
CHOOSING BETWEEN THE TWO MASTER DATASETS
================================================================================

Use master_joined when:
  - Your analysis is at the admission level (clinical characteristics, diagnoses)
  - Discharge outcome is not required for all records
  - You want the most conservative dataset (only direct matches have discharge data)
  - You need to validate probabilistic matches before including them

Use master_joined_extended when:
  - Maximum coverage of discharge outcomes is needed
  - You want to include probabilistically matched discharge data
  - You are computing outcome rates across all admissions
  - You have reviewed the prob_assignments file and are satisfied with quality

In both cases, you can use the match_type column to subset or stratify your
analysis by matching method.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (rbind, setdiff, names, data.frame, which, paste)
  - Depends on output from joiner.R (matched_pairs, unmatched_adm)
  - Depends on output from prob_matcher.R (assignments, unmatched_dis_df)


================================================================================
