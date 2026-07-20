================================================================================
  Neotree Sample Maker — modules/prob_matcher.R
  README: Probabilistic matching of unmatched records
================================================================================

PURPOSE
-------
prob_matcher.R attempts to recover admission-discharge pairs that failed the
direct uid+facility join.  It uses shared clinical variables to score the
similarity between unmatched admissions and unmatched discharges, then
applies greedy one-to-one assignment to select the best non-conflicting pairs.

This module provides three functions, called at STEPS 10–11 of run_sample_maker.R.


================================================================================
WHY RECORDS ARE UNMATCHED
================================================================================

The direct join fails when:
  - A uid was mistyped on the admission or discharge form
  - The facility name was entered differently in the two forms
  - One record was never submitted or synced to the database
  - The baby's uid was assigned differently at admission vs discharge

Probabilistic matching uses the baby's clinical "fingerprint" — birthweight,
gestational age, APGAR scores, sex, etc. — to find the most likely discharge
counterpart for each unmatched admission.


================================================================================
EXPORTED FUNCTIONS
================================================================================

1.  detect_match_variables(adm_full, dis_full, cfg)
    Determines which variables to use for scoring.
    Returns a var_info list.

2.  find_prob_candidates(unmatched_adm, unmatched_dis, var_info, cfg)
    Scores all candidate pairs and returns the top N per admission.
    Returns a data frame of candidates.

3.  assign_one_to_one(candidates)
    Greedy one-to-one assignment from the candidate list.
    Returns a data frame of accepted pairs.


================================================================================
CANDIDATE VARIABLES
================================================================================

The module considers these 10 variables (PROB_CANDIDATE_VARS):
  Numeric:      birthweight, gestation, temperature, apgar1, apgar5, apgar10, ofc
  Categorical:  gender, modedelivery, typebirth

Only variables that:
  a) exist in both the admissions and discharges files
  b) have at least prob_match_completeness_threshold (default 30%) non-NA values
     in BOTH files (assessed on the FULL files, not just the unmatched subsets)
  ...are included in scoring.  Variables that do not meet these criteria are
  reported as excluded in the console output and the prob matching report.

Completeness is assessed on the full loaded files (not the unmatched subsets)
to avoid distorted estimates when unmatched subsets are small.

  IMPORTANT -- birthweight column name and weight concepts
  --------------------------------------------------------
  birthweight is the single strongest numeric matching fingerprint. The module
  keys on the EXACT, literal column name "birthweight" (resolve_col checks
  `var %in% names(df)`); it does NOT know about the other birth-weight column
  names used elsewhere in the data (`bwt`, `bwtdis`).

  The cleaning pipeline holds birth weight under three interchangeable names
  across form/era -- `birthweight`, `bwt`, `bwtdis` -- all the SAME concept
  ("Birth weight (g)"); `bwtdis` is birth weight, not discharge weight. The
  cleaning pipeline's planned harmonisation adds a canonical
  `birthweight_g = coalesce(birthweight, bwt, bwtdis)` column while keeping the
  originals. Admission weight (`admissionweight`) and discharge/last-recorded
  weight (`dischweight`) are DIFFERENT concepts and are never folded into birth
  weight.

  Consequence for matching: keep the neonatal cleaned admissions/discharges
  birth-weight column addressable as "birthweight" so this matcher keeps using
  it. If the project ever renames it to "birthweight_g", update
  PROB_CANDIDATE_VARS and the prob_match_birthweight_tolerance key here --
  otherwise resolve_col returns NULL, birthweight is silently excluded from
  scoring, and the extended join quietly degrades. Coalescing does not change the values seen here: admissions and
  discharges each carry only one birth-weight column, so no tolerance/threshold
  re-tuning is needed.


================================================================================
FUNCTION DETAILS
================================================================================

----------------------------------------------------------------------
detect_match_variables(adm_full, dis_full, cfg)
----------------------------------------------------------------------

For each candidate variable:
  1. Resolve the actual column name in each file using resolve_col():
     checks whether the variable name exists in the data frame.
  2. Check completeness (proportion non-NA) in both files.
  3. If completeness ≥ threshold in both: include the variable.
  4. Look up the tolerance from config.R (cfg$prob_match_birthweight_tolerance
     etc.) or fall back to the built-in default.

Returns a named list (var_info):
  $vars         Named list of variables selected (name → TRUE)
  $tolerances   Named list of tolerances (name → numeric)
  $col_map_adm  Named list mapping variable name → column name in admissions
  $col_map_dis  Named list mapping variable name → column name in discharges

----------------------------------------------------------------------
find_prob_candidates(unmatched_adm, unmatched_dis, var_info, cfg)
----------------------------------------------------------------------

FACILITY BLOCKING
  To keep computation tractable on large datasets, pairs are only scored
  within the same facility (facility blocking).  This also reduces false
  positives: babies at different hospitals are very unlikely to be matches.

  If cfg$prob_match_cross_facility = TRUE:
    Any unmatched admission that found no within-facility candidate is
    then scored against ALL unmatched discharges regardless of facility.
    Useful when the facility name was mistyped on one form.
    Can be slow on large datasets.

SCORING (vectorised within each facility block)
  For each candidate pair (adm_i, dis_j):
    overall_similarity = mean of per-variable scores (variables where at
                         least one side is non-NA contribute to the mean)

  Per-variable scoring:
    Numeric variables:
      diff = |adm_value − dis_value|
      tol  = tolerance from var_info$tolerances

      score =
        100                           if diff = 0
        100 × (1 − diff / tol)        if 0 < diff ≤ tol
        100 × (1 − diff / (2×tol))    if tol < diff ≤ 2×tol  (clamped at 0)
        0                             if diff > 2×tol

      If tolerance = 0: score = 100 if diff = 0, else 0 (exact match).
      If either value is NA: variable excluded from the denominator.

    Categorical variables (gender, modedelivery, typebirth):
      score = 100 if values match exactly (case-sensitive)
      score = 0   if values differ
      If either value is NA: variable excluded from denominator.

    If ALL variables are NA for a pair: similarity = 0 (pair rejected).

FILTERING CANDIDATES
  Only pairs with overall_similarity ≥ prob_match_min_similarity are retained.
  For each unmatched admission, the top prob_match_max_candidates scoring
  discharges are kept (this cap is for the investigation report only;
  the one-to-one assignment considers all candidates).

Returns a data frame with one row per candidate pair:
  adm_row_idx, dis_row_idx, adm_uid, adm_facility, dis_uid, dis_facility,
  overall_similarity, plus one column per scoring variable (variable_score).

----------------------------------------------------------------------
assign_one_to_one(candidates)
----------------------------------------------------------------------

GREEDY ALGORITHM
  1. Sort all candidates by overall_similarity descending.
  2. Accept the top-scoring pair.
  3. Remove all other candidates involving either the accepted admission
     or the accepted discharge.
  4. Repeat from step 2 with the remaining candidates.
  5. Stop when no candidates remain.

This ensures every admission and every discharge appears in at most one
accepted pair (one-to-one constraint).  Higher-scoring pairs are always
preferred over lower-scoring ones involving the same records.

Returns a data frame with one row per accepted assignment:
  adm_row_idx, dis_row_idx, adm_uid, adm_facility, dis_uid, dis_facility,
  overall_similarity, plus per-variable scores.
  Returns an empty data frame if no candidates exceeded the threshold.


================================================================================
CONFIGURATION SETTINGS (from config.R)
================================================================================

  prob_match_min_similarity          Minimum score (0–100) to be a candidate
  prob_match_max_candidates          Max candidates per admission in report
  prob_match_completeness_threshold  Min proportion non-NA (0–1) for a variable
  prob_match_cross_facility          Allow cross-facility search (TRUE/FALSE)

  prob_match_birthweight_tolerance   grams (default 50)
  prob_match_gestation_tolerance     weeks (default 1)
  prob_match_ofc_tolerance           cm (default 1)
  prob_match_temperature_tolerance   °C (default 0.5)
  prob_match_apgar1_tolerance        score units (default 0 = exact)
  prob_match_apgar5_tolerance        score units (default 0 = exact)
  prob_match_apgar10_tolerance       score units (default 0 = exact)


================================================================================
INTERPRETING RESULTS
================================================================================

High similarity (≥ 80):  Strong evidence of a true match.
Medium (60–79):          Plausible match, especially if several variables agree.
Below threshold:         Not reported as a candidate.

The prob_assignments CSV gives the per-variable score breakdown for each
accepted pair, which can be used for manual review.

The prob_candidates CSV lists all candidate pairs above the threshold (before
one-to-one assignment), allowing inspection of cases where a close second
candidate existed.


================================================================================
LIMITATIONS
================================================================================

  - Probabilistic matching cannot recover pairs where ALL discriminating
    clinical variables are missing or identical between different babies.
  - Twins or multiples from the same mother may receive similar scores
    against multiple discharges; the greedy algorithm will accept the best
    one and leave the other unmatched.
  - Cross-facility matching (prob_match_cross_facility = TRUE) increases
    recall but also increases the risk of false positives.
  - Scores depend on which variables are available in both files; fewer
    variables → lower discriminating power.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (no external packages)
  - The %||% null-coalescing operator is defined within this module
  - No other modules are sourced


================================================================================
