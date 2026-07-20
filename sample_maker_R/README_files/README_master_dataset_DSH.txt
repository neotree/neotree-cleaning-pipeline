================================================================================
  Neotree Dataset Files -- Guide for Researchers
================================================================================

This document describes the files in this dataset folder.  Each file was
produced by the Neotree Sample Maker pipeline, which joins Neotree admission
records to their corresponding discharge records and prepares analysis-ready
datasets.

Read this before opening any file to make sure you are using the right one
for your analysis.


================================================================================
FILE NAMING CONVENTION
================================================================================

Every file name follows this pattern:

  {prefix}_{file_type}_{label}.csv  (or .txt)

  {prefix}   Identifies the country, data source, and cleaning method:
               MWI_db_r   = Malawi, from database, R-cleaned
               MWI_mb_r   = Malawi, from Metabase, R-cleaned
               ZIM_db_py  = Zimbabwe, from database, Python-cleaned
               (etc.)

  {label}    Describes the date window and any facility filter applied:
               to_20260302         = all records up to 2 March 2026
               20240101_to_20260302 = records between 1 Jan 2024 and 2 Mar 2026
               ALL                 = no date filter applied
               to_20260302_SMCH    = up to 2 Mar 2026, SMCH facility only

  Example:   MWI_db_r_master_joined_to_20260302.csv
             = Malawi / database / R-cleaned / all records up to 2 Mar 2026


================================================================================
WHICH FILE SHOULD I USE?
================================================================================

  For most analyses (admission + outcome data, maximising sample size):
    --> Use subsample_master_extended  or  master_joined_extended

  For analyses requiring only confirmed matched pairs (every row has full
  admission AND discharge data):
    --> Use subsample_master_extended_matched_only
        or joined_admissions_discharges_extended

  For analyses using direct UID matches only (strictest, smallest sample):
    --> Use joined_admissions_discharges

  Not sure?  See the full descriptions below, then check the
  matching_statistics report for match rates and outcome breakdowns.


================================================================================
FILE DESCRIPTIONS
================================================================================

--------------------------------------------------------------------------------
MAIN ANALYSIS FILES
--------------------------------------------------------------------------------

master_joined_{label}.csv
    THE FULL DATASET.  One row per admitted baby.  Rows where a matching
    discharge record was found ("direct_match") include all discharge
    variables (outcome, discharge datetime, etc.).  Rows with no discharge
    match ("unmatched") have blank discharge columns but still contain all
    admission data.

    Use for:  admission-level analyses that include babies regardless of
              whether a discharge was recorded.
    Column "match_type" tells you the status of each row:
      "direct_match" = admission matched to discharge by patient UID
      "unmatched"    = no discharge record found

master_joined_extended_{label}.csv
    Same as master_joined but with discharge data also filled in for some
    previously unmatched rows, where a probabilistic match was found (i.e.
    the discharge record existed but the UID contained a transcription
    error).  These rows are labelled "prob_match" in the match_type column.

    Use for:  same as master_joined, but with a higher proportion of rows
              having outcome data.
    Always report the match_type breakdown in any publication using this
    file (counts of direct_match / prob_match / unmatched).
    Column "prob_match_similarity" gives the similarity score (0-100) for
    probabilistically matched rows.

--------------------------------------------------------------------------------
MATCHED-PAIRS-ONLY FILES  (every row has both admission and discharge data)
--------------------------------------------------------------------------------

joined_admissions_discharges_{label}.csv
    Direct UID matches only.  Every row has a complete set of admission
    AND discharge variables.  No unmatched or probabilistic rows.

    Use for:  outcome analyses where you need paired data and want the
              strictest, most conservative match set.

joined_admissions_discharges_extended_{label}.csv
    Direct UID matches PLUS probabilistic matches.  Every row has both
    admission and discharge data.  Larger sample than the file above.

    Use for:  outcome analyses where you want to maximise matched sample
              size.  Always report the direct_match / prob_match split.

--------------------------------------------------------------------------------
SUBSAMPLE FILES  (date- or facility-filtered slices of the above)
--------------------------------------------------------------------------------

If subsample files are present, they are filtered versions of the master
files above, restricted to a specific date window and/or set of facilities.
The sub_label in their filename encodes the filter applied.

subsample_master_{sub_label}.csv
    Filtered equivalent of master_joined.

subsample_master_extended_{sub_label}.csv
    Filtered equivalent of master_joined_extended.

subsample_master_matched_only_{sub_label}.csv
    Filtered equivalent of joined_admissions_discharges (direct matches).

subsample_master_extended_matched_only_{sub_label}.csv
    Filtered equivalent of joined_admissions_discharges_extended
    (direct + probabilistic matches).

--------------------------------------------------------------------------------
UNMATCHED RECORDS  (for data quality review or sensitivity analyses)
--------------------------------------------------------------------------------

unmatched_admissions_{label}.csv
    Admissions for which no discharge record was found, even after
    probabilistic matching.  Contains only admission variables; all
    discharge columns are blank.  Not suitable for outcome analyses,
    but useful for understanding how many babies have incomplete records.

unmatched_discharges_{label}.csv
    Discharge records that could not be matched to any admission in the
    dataset.  Useful for data quality review.  Not intended for
    clinical analyses.

--------------------------------------------------------------------------------
QUALITY REPORTS  (read these before using the data)
--------------------------------------------------------------------------------

matching_statistics_{label}.txt
    Primary data quality report.  Shows how many records were processed,
    how many were matched (direct and probabilistic), match rates by
    facility, and the distribution of outcomes in the matched dataset.
    READ THIS FIRST before starting any analysis.

prob_matching_report_{label}.txt
    Technical report on the probabilistic matching step.  Describes which
    clinical variables were used for matching, the distribution of
    similarity scores, and a per-variable breakdown for accepted pairs.
    Review this to assess the quality of probabilistic matches before
    using any _extended file.

subsample_report_{sub_label}.txt
    (Present only if subsample files were produced.)  Describes the filters
    applied, how many rows were retained or excluded, the facility
    breakdown, and the match_type distribution in the subsample.

duplicates_log.csv
    (Present only if duplicate records were detected.)  Lists records where
    the same patient UID appeared more than once in the same facility.
    Useful for data quality review.

--------------------------------------------------------------------------------
PROBABILISTIC MATCH DETAIL  (for advanced review)
--------------------------------------------------------------------------------

prob_match_assignments_{label}.csv
    One row per accepted probabilistic match pair, with the similarity
    score and the values of each variable used in matching.  Review this
    if you want to inspect individual probabilistic matches before
    including them in an analysis.

prob_match_candidates_{label}.csv
    All candidate pairs that were scored above the similarity threshold,
    including pairs that were not ultimately assigned.  Use only for
    detailed investigation of specific records.


================================================================================
KEY COLUMNS PRESENT IN MOST FILES
================================================================================

  uid                   Patient identifier (from Neotree)
  facility              Facility name
  datetimeadmission     Date and time of admission
  match_type            "direct_match", "prob_match", or "unmatched"
  prob_match_similarity Similarity score for prob_match rows (blank otherwise)
  neotreeoutcome        Recorded discharge outcome (Discharged, Died, LAMA, etc.)
  datetimedischarge     Date and time of discharge (blank for unmatched rows)


================================================================================
IMPORTANT NOTES FOR ANALYSIS
================================================================================

1. The date window applied during data extraction uses a one-month-in-arrears
   cutoff.  This means the dataset intentionally excludes the most recent month
   of admissions to avoid inflating "unmatched" counts with babies still
   admitted at the time of extraction.  The label in the filename shows the
   exact cutoff date used (e.g. "to_20260302").

2. When using any _extended file, always report the match_type breakdown
   (counts of direct_match, prob_match, and unmatched rows) as part of your
   methods, and consider whether probabilistic matches should be included or
   excluded in a sensitivity analysis.

3. The files do not contain personally identifiable information such as
   mother names or GPS coordinates, but they do contain patient UIDs.
   Handle in accordance with your data sharing agreement.

================================================================================
  Neotree Sample Maker  --  UCL GOS Institute of Child Health
================================================================================
