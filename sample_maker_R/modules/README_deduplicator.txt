================================================================================
  Neotree Sample Maker — modules/deduplicator.R
  README: Duplicate key detection and resolution
================================================================================

PURPOSE
-------
deduplicator.R detects and resolves records that share the same uid+facility
match key within the admissions or discharges file.  Such duplicates would
cause problems in the join step (one-to-one matching assumes each key appears
exactly once).

This module is called once for admissions and once for discharges at STEP 7
of run_sample_maker.R, after filtering and before joining.


================================================================================
EXPORTED FUNCTION
================================================================================

  resolve_duplicates(df, label)

  Arguments:
    df      A data frame that already has a match_key column
            (created by joiner.R, but also expected here as it is added
             earlier in the pipeline if needed — in practice the joiner
             adds match_key, so the deduplicator works on the pre-key
             data frames passed by run_sample_maker.R)

    NOTE: In practice, run_sample_maker.R passes admissions and discharges
    before the joiner step.  The deduplicator uses df$match_key which is
    added as paste(uid, facility, sep="_") by the joiner; however, since
    deduplication happens before joining, run_sample_maker.R ensures
    match_key exists by calling the deduplicator after the joiner adds it
    internally, or by pre-adding the key.  In the current pipeline version
    the key is added inside joiner.R, and deduplication is applied to the
    already-keyed data frames passed via join_result.  Check run_sample_maker.R
    for the exact call sequence.

    label   A string label used in console messages ("ADMISSIONS" or
            "DISCHARGES")

  Returns a named list:
    $df          Data frame with duplicate rows removed
    $log         Data frame with one row per duplicate record (for CSV log)
    $n_dup_keys  Number of distinct keys that had duplicates
    $n_removed   Total number of rows removed


================================================================================
HOW IT WORKS
================================================================================

1. FIND DUPLICATE KEYS
   Identifies all match_key values that appear more than once.
   If none: prints a "no duplicates" message and returns the input unchanged
   (with an empty log data frame).

2. RESOLVE EACH DUPLICATE GROUP
   For each duplicated key:
     a. Find all row indices with that key.
     b. Count NAs in each row.
     c. Keep the row with the fewest NAs (most complete record).
        If two rows have the same NA count, the first is kept (which.min).
     d. Mark all other rows for removal.

3. FLAG POSSIBLE READMISSIONS
   For rows in the admissions file: if more than one row in a duplicate group
   has a non-NA, non-empty datetimeadmission, the group is flagged as a
   possible genuine readmission (same baby admitted, discharged, and re-admitted
   under the same uid+facility).
   Genuine readmissions are NOT excluded automatically — they are flagged in
   the log for manual clinical review.
   A console warning is printed for each such group.

4. BUILD THE DUPLICATE LOG
   For every row in every duplicate group, a log entry is written with:
     source                 "ADMISSIONS" or "DISCHARGES"
     match_key              the uid+facility key
     row_index_in_file      row number in the original data frame
     na_count               number of NA values in that row
     action                 "KEPT" or "REMOVED"
     possible_readmission   TRUE or FALSE

5. REMOVE DUPLICATE ROWS
   All marked rows are removed from the data frame.

6. REPORT
   Prints the number of duplicate keys resolved and rows removed.


================================================================================
OUTPUT FILES
================================================================================

The duplicate log is written to a CSV file by output_writer.R (not by this
module directly).  The file is only created when at least one duplicate was
found in either admissions or discharges.

  {prefix}_duplicates_log.csv
    Contains all duplicate records (from both admissions and discharges) with
    the action taken and the possible_readmission flag.

Clinicians should review this file, particularly rows flagged as possible
readmissions, to determine whether the kept record is correct and whether the
removed records represent genuine separate clinical episodes that should be
tracked differently.


================================================================================
DESIGN NOTES
================================================================================

WHY KEEP THE MOST COMPLETE ROW
  In practice, duplicate records often arise from data entry errors or system
  re-imports where one version is partially filled and another is more complete.
  Keeping the row with the fewest NAs maximises the clinical information retained.

WHY FLAG RATHER THAN AUTO-EXCLUDE READMISSIONS
  Genuine readmissions (same baby, multiple admissions) should be included in
  the dataset as separate clinical episodes.  However, they cannot both be
  matched to a single discharge under a uid+facility key.  Rather than silently
  discarding a valid admission, the module flags these cases so a clinician can
  decide how to handle them (e.g. assign a modified uid for one episode).

WHY DEDUPLICATE BEFORE JOINING
  The joiner uses set intersection, which in R operates on unique values.
  If duplicate keys are present, the join would still produce only one matched
  pair (as intersect returns unique keys), but the original row ordering
  assumptions would be violated.  Deduplication before joining ensures clean
  one-to-one matching.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (duplicated, which, vapply, data.frame, do.call, rbind)
  - No other modules


================================================================================
