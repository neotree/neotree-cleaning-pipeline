================================================================================
  Neotree Sample Maker — modules/output_writer.R
  README: Output file writing and report generation
================================================================================

PURPOSE
-------
output_writer.R writes all output files at the end of Pipeline 1.  It receives
the complete pipeline_state object from run_sample_maker.R and produces six
or more CSV files plus two detailed text reports.

This module is called at STEP 13 of run_sample_maker.R.


================================================================================
EXPORTED FUNCTION
================================================================================

  write_outputs(cfg, ps)

  Arguments:
    cfg   The CONFIG list from config.R
    ps    The pipeline_state list assembled by run_sample_maker.R, containing:
            admissions_path, discharges_path
            n_adm_raw, n_dis_raw
            admissions_full, discharges_full
            date_window, filter_result, varfilt_result
            adm_dedup, dis_dedup
            join_result
            var_info, prob_candidates, prob_assignments
            master_joined, master_joined_extended

  Returns a named list of all output file paths written:
    $joined, $joined_extended, $unmatched_adm, $unmatched_dis
    $master_joined, $master_extended
    $stats_report
    $prob_report     (NULL if no probabilistic matching ran)
    $prob_assign     (NULL if no assignments)
    $prob_cands      (NULL if no candidates)
    $dup_log         (NULL if no duplicates found)


================================================================================
OUTPUT DIRECTORY
================================================================================

All files are written to:
    {cfg$output_dir}/{country}_master/{source}/
    e.g. outputs/zim_master/from_database/

The directory is created automatically (recursively) if it does not exist.

File prefix:
    {COUNTRY}_{src}   e.g. ZIM_db, MWI_mb
    Derived from cfg$country (uppercased) and cfg$source.
    Source short codes: from_database → "db", from_metabase → "mb"

Filter label:
    Derived from the date window and facility filter.
    Examples: "to_20260228", "20220101_to_20260228", "ALL"


================================================================================
OUTPUT FILES
================================================================================

CSV FILES (always written):

  {prefix}_joined_admissions_discharges_{label}.csv
    The matched_pairs data frame from joiner.R.
    Contains only directly matched pairs (uid+facility key match).
    Every row has both admission and discharge data.

  {prefix}_joined_admissions_discharges_extended_{label}.csv
    Extends the file above by adding probabilistically matched pairs.
    Derived from master_joined_extended filtered to match_type != "unmatched".
    match_type = "direct_match" or "prob_match".
    Every row has both admission and discharge data.
    Use this when you want the maximum number of paired records for
    outcome or discharge-dependent analyses.

  {prefix}_unmatched_admissions_{label}.csv
    Admissions for which no discharge was found (direct or probabilistic).

  {prefix}_unmatched_discharges_{label}.csv
    Discharges for which no admission was found in the filtered set.

  {prefix}_master_joined_{label}.csv
    All filtered admissions.  match_type = "direct_match" or "unmatched".

  {prefix}_master_joined_extended_{label}.csv
    All filtered admissions with probabilistic matches included.
    match_type = "direct_match", "prob_match", or "unmatched".
    prob_match_similarity contains the score for prob_match rows.

CSV FILES (conditional):

  {prefix}_prob_assignments_{label}.csv
    Written only when at least one probabilistic pair was accepted.
    One row per accepted pair with: adm_uid, adm_facility, dis_uid,
    dis_facility, overall_similarity, and one column per scoring variable.

  {prefix}_prob_candidates_{label}.csv
    Written only when at least one candidate was found (above min_similarity,
    before one-to-one assignment).
    One row per candidate pair — useful for reviewing near-misses and
    cases where a close second candidate existed.

  {prefix}_duplicates_log.csv
    Written only when duplicates were found in admissions or discharges.
    Contains all duplicate records with action (KEPT/REMOVED) and
    possible_readmission flag.

TEXT REPORTS (always written):

  {prefix}_matching_statistics_{label}.txt
    Comprehensive overview of the entire Pipeline 1 run.  See below.

  {prefix}_prob_matching_report_{label}.txt
    Written only when probabilistic matching ran (even if no pairs accepted).
    Detailed report on the probabilistic step.  See below.


================================================================================
MATCHING STATISTICS REPORT — SECTIONS
================================================================================

1. METADATA
   Run date/time, script name, R version, config settings used
   (country, source, cleaning, dates, facility filter, prob matching settings).

2. INPUT FILES
   Paths to admissions and discharges files.
   Raw row counts before any processing.
   Column counts.

3. ADMISSION DATE FILTER
   Mode (simple / advanced), dates applied, facility filter, auto-mode flag.
   Rows before and after filtering; rows excluded.
   Variable filter (if applied): column, values, rows excluded.

4. DEDUPLICATION
   Number of duplicate keys found in admissions and discharges.
   Number of rows removed from each.

5. DIRECT MATCHING SUMMARY
   Total admissions and discharges after deduplication.
   Matched pairs count with percentage of admissions and discharges matched.
   Unmatched admissions and discharges with percentages.

6. OUTCOME DISTRIBUTION  (neotreeoutcome)
   Frequency table of neotreeoutcome values among matched pairs, sorted
   by frequency, with counts and percentages.
   Per-facility breakdown of matched pairs.

7. UNMATCHED BREAKDOWN
   Per-facility counts of unmatched admissions and unmatched discharges.

8. MASTER DATASETS SUMMARY
   Row counts and match_type breakdown for master_joined and master_joined_extended.
   prob_match_similarity statistics (min, mean, max) for prob_match rows.
   Row count and direct_match / prob_match split for joined_admissions_discharges_extended.

9. OUTPUT FILES
   Full paths of every file written, with file sizes.


================================================================================
PROBABILISTIC MATCHING REPORT — SECTIONS
================================================================================

1. METADATA
   Run date/time, script name.

2. CONFIGURATION
   All prob_match_* settings from config.R used in this run.

3. VARIABLE SELECTION
   For each candidate variable: whether it was included or excluded and why.
   For included variables: completeness % in admissions and discharges files,
   tolerance used.

4. CANDIDATE SEARCH
   Number of unmatched admissions and discharges searched.
   Number of pairs scored.
   Number of candidates above the minimum similarity threshold.
   Whether cross-facility search was used.

5. ONE-TO-ONE ASSIGNMENT
   Number of pairs accepted.
   Similarity score distribution (min, mean, max, quartiles).

6. PER-VARIABLE SCORE BREAKDOWN
   For each accepted assignment: mean score per variable across all accepted
   pairs.  Shows which variables were the most discriminating.

7. MASTER_JOINED_EXTENDED SUMMARY
   Row counts by match_type in the extended dataset.
   Coverage improvement vs master_joined (additional % of admissions
   with discharge data after probabilistic matching).

8. TOP-20 ASSIGNMENTS
   Table of the 20 accepted pairs with highest overall similarity,
   showing uid pairs, facilities, similarity, and key variable scores.

9. OUTPUT FILES
   Paths of all prob-related files written.


================================================================================
INTERNAL HELPERS
================================================================================

  .build_stats_report(cfg, ps, output_paths)
    Generates the matching statistics report as a character vector of lines.

  .build_prob_report(cfg, ps, output_paths)
    Generates the probabilistic matching report.

  .fac_breakdown(df, label)
    Formats a per-facility count table as report lines.

All helpers are internal (prefixed with ".") and not called directly.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (write.csv, writeLines, dir.create, file.path, format,
    Sys.time, R.version.string, table, range)
  - No other modules


================================================================================
