================================================================================
  Neotree Sample Maker — modules/filter_data.R
  README: Date parsing, date window resolution, and admission filtering
================================================================================

PURPOSE
-------
filter_data.R handles all date-related processing and admission filtering.
It contains four exported functions that are called in sequence (STEPS 3–6)
in run_sample_maker.R.

Discharges are intentionally NOT filtered.  All discharge records are kept
so that admissions selected up to adm_end_date have the best chance of
finding a matching discharge.


================================================================================
EXPORTED FUNCTIONS
================================================================================

1.  parse_admission_dates(admissions)
    Adds the column adm_date_parsed to the admissions data frame.
    Returns the updated data frame.

2.  resolve_date_window(admissions, cfg)
    Determines the actual start/end dates to use.
    Returns a date_window list.

3.  apply_admission_filter(admissions, date_window, cfg)
    Applies the date window and facility filter.
    Returns a named list with the filtered admissions and filter metadata.

4.  apply_variable_filter(admissions, cfg, filter_result)
    Optional: filters admissions by a column value.
    Returns a named list with the (possibly unchanged) admissions.


================================================================================
FUNCTION DETAILS
================================================================================

----------------------------------------------------------------------
parse_admission_dates(admissions)
----------------------------------------------------------------------

Adds adm_date_parsed (POSIXct, UTC timezone) by parsing datetimeadmission.

Two formats are tried in order:
  1. Full datetime: "%Y-%m-%d %H:%M:%S"   e.g. "2024-03-15 08:30:00"
  2. Date only:     "%Y-%m-%d"             e.g. "2024-03-15"

Records where both parses fail receive NA in adm_date_parsed.  These are
counted and warned about; they will be excluded from any date-filtered output
(since their position in the date range is unknown).

Prints the overall date range of the admissions file.

Returns:  admissions data frame with adm_date_parsed column added.

----------------------------------------------------------------------
resolve_date_window(admissions, cfg)
----------------------------------------------------------------------

Determines the adm_start and adm_end dates to use for filtering.

AUTO MODE (cfg$adm_end_date = NULL and cfg$use_advanced_mode = FALSE):
  adm_end  = latest adm_date_parsed in file − 1 calendar month
           = seq(max_date, by = "-1 month", length.out = 2)[2]
             This correctly handles month-end edge cases:
               31 March   → 28 February  (not 3 March)
               31 January → 31 December  (prior year)
  adm_start = cfg$adm_start_date (which may also be NULL = no lower bound)

MANUAL MODE (cfg$adm_end_date provided):
  Uses cfg$adm_start_date and cfg$adm_end_date as-is.

ADVANCED MODE (cfg$use_advanced_mode = TRUE):
  No global date window is computed; the function returns NULL for both
  adm_start and adm_end.  Date filtering is done per-facility in
  apply_admission_filter().

Returns a named list:
  $adm_start   "YYYY-MM-DD" string or NULL
  $adm_end     "YYYY-MM-DD" string or NULL
  $auto_mode   TRUE if adm_end was auto-computed
  $label       Human-readable label used in output file names

Filter label convention:
  Both dates:  "20220101_to_20260228"
  End only:    "to_20260228"
  Start only:  "from_20220101"
  Neither:     "ALL"
  With facility:  "to_20260228_SMCH"  (facility appended after date part)

----------------------------------------------------------------------
apply_admission_filter(admissions, date_window, cfg)
----------------------------------------------------------------------

SIMPLE MODE (cfg$use_advanced_mode = FALSE):
  Applies adm_start, adm_end, and optional cfg$facility_filter.
  Start bound: adm_date_parsed >= start_dt  (records with NA date excluded)
  End bound:   adm_date_parsed <= end_dt at 23:59:59
  Facility:    admissions$facility %in% cfg$facility_filter

ADVANCED MODE (cfg$use_advanced_mode = TRUE):
  Applies per-facility date ranges from cfg$facility_date_ranges.
  Each entry c("FACILITY", "start_date", "end_date") produces one chunk.
  Chunks are row-bound; duplicate uid+facility keys from overlapping entries
  are silently removed.

Both modes report:
  - Number of admissions before/after filtering
  - Number excluded

Stops with a helpful error if zero admissions remain, showing the available
date range and facilities in the file.

Returns a named list:
  $admissions     Filtered admissions data frame
  $n_before       Row count before filter
  $n_after        Row count after filter
  $n_excluded     Rows removed
  $filter_desc    Character vector of filter description lines (for report)
  $filter_label   The label string (used in output filenames)

----------------------------------------------------------------------
apply_variable_filter(admissions, cfg, filter_result)
----------------------------------------------------------------------

Optional filter applied AFTER date/facility filtering.

If cfg$variable_filter_col is NULL: returns admissions unchanged (no-op).

Otherwise: retains only rows where admissions[[col]] is in cfg$variable_filter_values.
The column must exist in the admissions data frame (stops with error if not).

Stops with an error if zero admissions remain, showing the values present in
that column (before this filter, using filter_result$admissions for context).

Returns a named list:
  $admissions          (Possibly filtered) data frame
  $n_excluded_varfilt  Number of rows removed by this filter
  $var_filter_desc     One-line description string (or NULL if disabled)


================================================================================
DESIGN NOTES
================================================================================

WHY DISCHARGES ARE NOT FILTERED
  Filtering discharges by date would exclude discharges that correspond to
  babies admitted before the window started, creating artificial gaps.  By
  keeping all discharge records, any baby admitted up to adm_end_date has
  the maximum chance of finding its discharge record, regardless of when
  the discharge was recorded.

WHY "ONE MONTH IN ARREARS"
  At the time of data extraction, babies admitted in the most recent weeks
  may still be in the hospital.  Including them would inflate the "unmatched"
  count with babies who are simply not yet discharged, not babies with missing
  data.  The one-month buffer gives nearly all admitted babies enough time to
  reach discharge before the analysis cut-off.

WHY seq() FOR MONTH SUBTRACTION
  Simple arithmetic (subtract 30 days) does not give a clean calendar-month
  offset.  seq(date, by="-1 month") uses the calendar and correctly handles
  month-end edge cases.


================================================================================
DEPENDENCIES
================================================================================

  - Base R only (as.POSIXct, seq.Date, range, subset, do.call, rbind)
  - No other modules


================================================================================
