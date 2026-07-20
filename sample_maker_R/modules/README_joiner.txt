================================================================================
  Neotree Sample Maker — modules/joiner.R
  README: Direct uid+facility join of admissions to discharges
================================================================================

PURPOSE
-------
joiner.R performs the primary matching step: it joins admissions to discharges
using the composite key uid + facility.  It produces matched pairs and the two
unmatched datasets, and computes a Neotree outcome summary for the matched set.

This module is called at STEP 8 of run_sample_maker.R, after deduplication.


================================================================================
EXPORTED FUNCTION
================================================================================

  join_data(admissions, discharges)

  Arguments:
    admissions   Filtered and deduplicated admissions data frame
    discharges   Deduplicated discharges data frame (not date-filtered)

  Returns a named list:
    $matched_pairs      Rows matched in both files (admission + discharge cols)
    $unmatched_adm      Admission rows with no matching discharge
    $unmatched_dis      Discharge rows with no matching admission key
    $n_matched          Number of matched pairs
    $n_unmatched_adm    Number of unmatched admissions
    $n_unmatched_dis    Number of unmatched discharges
    $n_adm_total        Total admissions (after filter, before join)
    $n_dis_total        Total discharges (before join)
    $outcome_col        Name of outcome column used ("neotreeoutcome" or
                        "neotreeoutcome_dis"), or NULL if not found
    $outcome_summary    List with formatted outcome distribution lines and
                        facility breakdown


================================================================================
HOW IT WORKS
================================================================================

1. CREATE MATCH KEYS
   Adds match_key = paste(uid, facility, sep="_") to both data frames.
   Reports the number of unique keys in each file.

2. SET OPERATIONS
   matched_keys       = intersect(adm_keys, dis_keys)
   unmatched_adm_keys = setdiff(adm_keys, dis_keys)
   unmatched_dis_keys = setdiff(dis_keys, adm_keys)

   This is a pure set-based join: each unique key either matches or does not.
   The one-to-one deduplication in STEP 7 ensures no key appears twice, so
   each matched key corresponds to exactly one admission and one discharge.

3. SUBSET ROWS
   adm_matched, dis_matched, unmatched_adm, and unmatched_dis are extracted
   by subsetting on the key sets.

4. BUILD MATCHED PAIRS
   Both matched subsets are sorted by match_key to align rows correctly.
   Discharge columns that share a name with an admission column (except
   match_key itself) are renamed by appending "_dis".
   This avoids column name conflicts in the combined dataset.
   The number of renamed columns is reported to the console.
   The combined data frame is built with cbind() (match_key column from
   the discharge side is dropped to avoid duplication).

5. OUTCOME SUMMARY
   Looks for the "neotreeoutcome" column (first in admissions side, then as
   "neotreeoutcome_dis" if the admissions file did not have it).
   Builds a formatted frequency table of outcomes with percentages.
   Also builds a per-facility breakdown of matched pairs.
   These are returned as $outcome_summary and included in the statistics report.


================================================================================
MATCHING KEY
================================================================================

The match key is:   uid + "_" + facility

Both uid and facility must match exactly (case-sensitive) for a pair to be
considered a match.  Common reasons for unmatched records:

  Unmatched admissions:
    - Baby still admitted (not yet discharged)
    - Discharge entered under a different uid or facility name
    - uid was not collected at admission or was entered differently
    - Discharge record missing from the data extract

  Unmatched discharges:
    - Admission falls outside the selected date window
    - Admission record missing
    - uid or facility name discrepancy between admission and discharge entry

The probabilistic matching module (prob_matcher.R) attempts to recover some
of these unmatched pairs using clinical similarity scores.


================================================================================
COLUMN NAMING IN MATCHED PAIRS
================================================================================

All admission columns are kept with their original names.
Discharge columns that overlap with admission column names (except match_key)
receive a "_dis" suffix.  For example:

  If both files have a column "gender":
    Admissions side → "gender"         (unchanged)
    Discharge side  → "gender_dis"

  If both files have "neotreeoutcome":
    Admissions side → "neotreeoutcome"
    Discharge side  → "neotreeoutcome_dis"

  Unique discharge columns (not in admissions) keep their original names.

The master_builder.R module uses this "_dis" suffix convention to reconstruct
the discharge side when building master_joined_extended for probabilistic pairs.


================================================================================
OUTCOME SUMMARY FORMAT
================================================================================

The outcome summary is included in the matching statistics report.
It shows the distribution of neotreeoutcome values among matched pairs,
sorted by frequency, with counts and percentages:

  Outcome column used : neotreeoutcome_dis
  Total matched pairs : 33755

  Outcome                              N       %
  -----------------------------------  ------  ------
  Discharged home                      28431   84.2%
  Died                                  2891    8.6%
  Transferred out                       1754    5.2%
  ...

Followed by a per-facility breakdown showing the number of matched pairs
from each facility.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (intersect, setdiff, cbind, order, table, vapply)
  - No other modules


================================================================================
