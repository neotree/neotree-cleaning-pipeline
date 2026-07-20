================================================================================
  Neotree Sample Maker — modules/subsample_maker.R
  README: Subsample filtering, column selection, and report writing
================================================================================

PURPOSE
-------
subsample_maker.R provides all the logic for Pipeline 2 (run_subsample_maker.R).
It reads master_joined and master_joined_extended, applies an admission date
filter and optional facility/column selection, and writes the resulting
subsamples and a detailed text report.

This module is NOT part of Pipeline 1 (run_sample_maker.R).  It is sourced
exclusively by run_subsample_maker.R.


================================================================================
EXPORTED FUNCTIONS
================================================================================

1.  run_subsample_maker(master_joined, master_joined_extended, cfg)
    Applies all filters and column selection to both master datasets.
    Returns a sub_result list.

2.  write_subsample_outputs(sub_result, cfg, prefix, out_dir, na_coded = NULL)
    Writes four subsample CSVs and the text report.
    When na_coded is a named list (joined, extended, joined_matched,
    extended_matched), also writes four paired *_na_coded.csv files.
    Returns a named list of all output file paths.


================================================================================
FUNCTION DETAILS
================================================================================

----------------------------------------------------------------------
run_subsample_maker(master_joined, master_joined_extended, cfg)
----------------------------------------------------------------------

The function processes both master datasets in parallel using the same
configuration settings.  The cfg argument is the SUBSAMPLE_CONFIG list
from run_subsample_maker.R.

STEP A — ENSURE PARSED DATE
  Re-parses admission dates if adm_date_parsed is absent or not POSIXct.
  This handles the common case where master datasets are read from CSV
  (which drops POSIXct metadata, storing dates as character strings).
  Falls back to parsing datetimeadmission with the same two-format strategy
  used in filter_data.R (full datetime, then date-only).
  If datetimeadmission itself is missing, date filtering is skipped.

STEP B — RESOLVE FILTER INFO
  Calls .build_sub_filter_info() to determine the filter label and description.
  The label encodes the date window and facility selection:
    "to_20260228", "20240101_to_20260228", "ALL", "SMCH", etc.
  When column selection is active (sub_variables not NULL), "_Nvars" is
  appended to the label (e.g. "_12vars").

STEP C — APPLY FILTER (for each dataset)
  .apply_sub_filter() subsets rows based on cfg$sub_use_advanced_mode:

  SIMPLE MODE:
    Applies sub_start_date, sub_end_date, and sub_facility_filter.
    Same logic as apply_admission_filter() in filter_data.R.
    Rows where adm_date_parsed is NA are excluded when date bounds are set.

  ADVANCED MODE:
    Per-facility date ranges from sub_facility_date_ranges.
    Same logic as advanced mode in filter_data.R.

  Returns a metadata list per dataset:
    n_total, n_kept, n_excluded, n_missing_dates, date_min, date_max,
    filter_label, type_tab (match_type frequency table).

STEP D — APPLY EXCLUSION FILTERS (for each dataset)
  .apply_exclusion_filters() removes rows where a variable meets a condition.
  Applied to each dataset independently after the date/facility filter.

  cfg$sub_exclusion_filters is a list of entries:
    list(variable = "colname", operator = "<", value = 24)
  Supported operators: "<", "<=", ">", ">=", "==", "!=", "in", "not_in"

  Rows where the filter variable is NA are KEPT (conservative default).
  Numeric coercion is applied when the comparison value is numeric.
  Multiple filters are applied in sequence; a row is excluded if it matches
  any single filter.
  When any filters are set, "_excl" is appended to the output label.

  Returns: list(df, excl_info, n_total_excluded)
    excl_info  -- per-filter result: variable, operator, value, n_excluded,
                  skipped (TRUE if column not found)

STEP E — SELECT COLUMNS (for each dataset)
  .select_columns() restricts the data frame to the requested column set.

  MANDATORY COLUMNS (always retained regardless of sub_variables):
    uid, facility, uniquekey, datetimeadmission, match_key, adm_date_parsed,
    match_type, prob_match_similarity

  Requested columns (sub_variables) are matched by exact name against the
  data frame columns.  Names not found are recorded in a "not_found" list
  and reported in the subsample report.

  Returns the reduced data frame plus col_info:
    requested, found, not_found, mandatory, final_cols, n_vars

STEP G — DERIVE MATCHED-ONLY DATASETS (always)
  Two matched-only datasets are always derived, mirroring the Pipeline 1
  naming convention:

  subsample_joined_matched_only
    Derived from subsample_joined by keeping only rows where
    match_type == "direct_match".  Mirrors joined_admissions_discharges.

  subsample_joined_extended_matched_only
    Derived from subsample_joined_extended by removing rows where
    match_type == "unmatched".  Contains direct_match and prob_match rows.
    Mirrors joined_admissions_discharges_extended.

STEP H — RETURN
  Returns a sub_result list:
    $subsample_joined                        All admissions (master_joined filtered)
    $subsample_joined_extended               All admissions + prob matches (master_joined_extended filtered)
    $subsample_joined_matched_only           Direct matches only
    $subsample_joined_extended_matched_only  Direct + prob matches only
    $meta_joined                             Date/facility filter results for master_joined
    $meta_extended                           Date/facility filter results for master_joined_extended
    $excl_joined                             Exclusion filter results for master_joined
    $excl_extended                           Exclusion filter results for master_joined_extended
    $sub_filter_desc                         Filter description lines (for report)
    $sub_label                               Output file label string
    $col_info                                Column selection metadata

----------------------------------------------------------------------
write_subsample_outputs(sub_result, cfg, prefix, out_dir, na_coded = NULL)
----------------------------------------------------------------------

Writes five files to out_dir:

  {prefix}_subsample_master_{label}.csv
  {prefix}_subsample_master_extended_{label}.csv
  {prefix}_subsample_master_matched_only_{label}.csv
  {prefix}_subsample_master_extended_matched_only_{label}.csv
  {prefix}_subsample_report_{label}.txt

When na_coded is a named list (joined, extended, joined_matched,
extended_matched) — supplied when cfg$output_na_coded = TRUE — four
additional files are written alongside the standard CSVs:

  {prefix}_subsample_master_{label}_na_coded.csv
  {prefix}_subsample_master_extended_{label}_na_coded.csv
  {prefix}_subsample_master_matched_only_{label}_na_coded.csv
  {prefix}_subsample_master_extended_matched_only_{label}_na_coded.csv

The label is taken from sub_result$sub_label.
The out_dir is created automatically if needed.
write.csv() is used with row.names = FALSE.

Returns a named list of all output file paths (five or nine entries):
  $sub_joined, $sub_extended, $sub_joined_matched, $sub_extended_matched,
  $report  [always]
  $sub_joined_nc, $sub_extended_nc, $sub_joined_matched_nc,
  $sub_extended_matched_nc  [when na_coded is supplied]


================================================================================
SUBSAMPLE REPORT — SECTIONS
================================================================================

1. METADATA
   Run date/time, script, input file paths, row counts.

2. INPUT FILES
   master_joined and master_joined_extended dimensions.

3. FILTER APPLIED
   Mode (simple / advanced), date bounds, facility filter.
   Full description of what was applied.

4. FILTER RESULTS
   For each dataset (joined and extended):
     Rows before / kept / excluded.
     Rows with missing dates (if any).
     Date range of kept rows.
     Distribution of match_type among kept rows.

4b. EXCLUSION FILTER RESULTS
   For each filter entry: variable, operator, value, rows removed.
   Total rows removed by exclusion filters, and rows remaining.
   Section omitted from report when no exclusion filters are configured.

5. COLUMN SELECTION
   Whether column selection was active.
   Variables requested, found, not found.
   Mandatory columns always retained.
   Final column count.

6. FACILITY BREAKDOWN
   Per-facility row counts for subsample_joined and subsample_joined_extended.

6b. MATCHED-ONLY OUTPUTS
    Stats for both matched-only files, always produced:
    - subsample_joined_matched_only: row count (direct matches only).
    - subsample_joined_extended_matched_only: row count, direct/prob split,
      number of unmatched rows removed from subsample_joined_extended.

7. OUTCOME DISTRIBUTIONS
   neotreeoutcome distribution (if column present) for each output dataset,
   broken down by match_type.

8. OUTPUT FILES
   Full paths and sizes of all CSVs (four standard + up to four na_coded)
   and this report.


================================================================================
MANDATORY COLUMNS
================================================================================

The following columns are ALWAYS included in subsample outputs, even if not
listed in sub_variables, because they are required for data linkage, audit,
and downstream analysis:

  uid                    Patient identifier
  facility               Facility name
  uniquekey              Neotree record identifier (if present)
  datetimeadmission      Original admission datetime string
  match_key              uid + "_" + facility composite key
  adm_date_parsed        Parsed admission date (POSIXct)
  match_type             "direct_match", "prob_match", or "unmatched"
  prob_match_similarity  Similarity score for prob_match rows


================================================================================
RELATIONSHIP TO PIPELINE 1
================================================================================

run_sample_maker.R (Pipeline 1)
    Produces: master_joined, master_joined_extended

run_subsample_maker.R / subsample_maker.R (Pipeline 2)
    Reads:    master_joined, master_joined_extended
    Produces: subsample_joined, subsample_joined_extended, subsample_report

The separation means:
  - Pipeline 1 is run infrequently (when new data arrives)
  - Pipeline 2 can be run many times with different date windows or column
    sets, without repeating the join and probabilistic matching steps


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (read.csv, write.csv, as.POSIXct, table, range, Sys.time)
  - No other modules
  - Not sourced by run_sample_maker.R — standalone use only


================================================================================
