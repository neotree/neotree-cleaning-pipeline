================================================================================
  Neotree Sample Maker
  README: run_sample_maker.R — Main pipeline orchestration script
================================================================================

================================================================================
DEFAULT WORKFLOW
================================================================================

  For most work, use run_all.R — NOT this script.

  run_all.R automatically discovers ALL datasets in the input/ folder and
  processes every admissions+discharges pair in a single command, with no
  config editing required.  Neolab, maternal, and all other standalone dataset
  types are skipped and handled by run_subsample_maker.R.

    Rscript run_all.R

  See README_run_all.txt and README_PIPELINE.txt for full details.

================================================================================
WHEN TO USE run_sample_maker.R (SINGLE-PAIR MODE)
================================================================================

  Use this script only when you need to (re-)process a specific
  country/source combination without running everything else:
    - You have a new data extract for one country and don't want to
      reprocess the others.
    - You need a non-default date window for one pair.
    - You are passing a custom config as a command-line argument.

  For all other cases, use run_all.R.

================================================================================
OVERVIEW
================================================================================

run_sample_maker.R is the entry point for Pipeline 1 for a single
country/source pair.  It reads config_sample_maker.R, sources all modules,
and runs the full pipeline to produce complete master datasets covering all
facilities and all historical data up to one month before the data extraction
date.

You only need to edit config_sample_maker.R before running this script.
The script itself should not be modified.

This script is intentionally kept simple: it does not filter by facility,
apply per-facility date windows, or filter by clinical sub-population.
All such filtering is handled by the subsample makers, which read the master
datasets produced here and create tailored extracts on request from researchers.


================================================================================
HOW TO RUN
================================================================================

From RStudio
  Open run_sample_maker.R and click the "Source" button (top-right of editor).

From the command line (recommended for batch runs):
  cd /path/to/sample_maker_R
  Rscript run_sample_maker.R

With a custom config file:
  Rscript run_sample_maker.R /path/to/my_config.R

The script determines its own directory automatically so that all relative
paths (input/, modules/, outputs/) resolve correctly regardless of where you
launch R from.


================================================================================
REQUIREMENTS
================================================================================

  - R (any recent version; tested with R 4.x)
  - Base R only — no external packages are required
  - The modules/ subdirectory must be present alongside this script
  - config_sample_maker.R in the same directory (or passed as an argument)
  - input/ folder with the cleaning pipeline output (copied and renamed).
    One subdirectory per dataset cut, each holding a *_cleaned.csv file:
        input/
          zim_db_admissions_20260301/
            zim_db_admissions_20260301_cleaned.csv
          zim_db_discharges_20260301/
            zim_db_discharges_20260301_cleaned.csv


================================================================================
PIPELINE STEPS
================================================================================

STEP 0 — Resolve paths and load configuration
  Detects the script's own directory so that relative paths work correctly
  when running from Rscript, RStudio, or any working directory.
  Sources config_sample_maker.R (or the path given as a command-line argument).
  Sources all modules from modules/.

STEP 1 — Locate input files  [file_finder.R]
  MODE A: Searches the input/ folder for subdirectories matching
    {country}_{src}_{type}_{date}/ (case-insensitive) and returns the
    *_cleaned.csv file found inside.  Most recently modified wins if multiple
    data cuts are present.
  MODE B: Constructs the path {cleaned_files_dir}/{country}/{source}/{cleaning}/
    and finds files by prefix-matching {country}_{src}_{type}_*.csv.

STEP 2 — Load data  [loader.R]
  Reads both CSV files with read.csv().
  Validates that required columns are present:
    Admissions: uid, facility, datetimeadmission
    Discharges: uid, facility
  Stops with a clear error message if a file is empty or a column is missing.

STEP 2b — Load na_coded source files  [loader.R]  (only when output_na_coded = TRUE)
  Locates and loads the *_cleaned_na_coded.csv counterparts of the standard
  admissions and discharges files.  Na_coded files use numeric sentinel codes
  (-7, -8, -9, etc.) instead of blank NA to distinguish types of missingness —
  needed for ML model training.
  If either na_coded file is absent, a warning is printed and na_coded master
  output is skipped for this run (the standard master files are unaffected).

STEP 3 — Parse admission dates  [filter_data.R]
  Adds the column adm_date_parsed (POSIXct, UTC) to the admissions data frame.
  Handles full datetime ("YYYY-MM-DD HH:MM:SS") and date-only ("YYYY-MM-DD")
  formats.  Records with unparseable dates are flagged with a warning; they will
  be excluded from date-filtered output.

STEP 4 — Resolve the admission date window  [filter_data.R]
  In AUTO mode (adm_end_date = NULL, use_advanced_mode = FALSE):
    adm_end = latest admission date in file − 1 calendar month
    adm_start = NULL (no lower bound — all historical data)
  In MANUAL SIMPLE mode: uses adm_start_date / adm_end_date from config as-is.
  In ADVANCED mode (use_advanced_mode = TRUE): no global window is computed;
    per-facility ranges from facility_date_ranges are used directly in Step 5.
  The resolved window is stored as a date_window list and used in Step 5.

STEP 5 — Filter admissions by date window  [filter_data.R]
  SIMPLE mode: applies one global date window to all admissions.
  ADVANCED mode: applies per-facility date ranges from facility_date_ranges,
    then deduplicates rows if ranges overlap.
  Discharges are NOT filtered — all discharge records are used for matching.
  Reports the number of admissions before and after filtering.
  Stops with a helpful error if no admissions remain after filtering.

  NOTE — Facility filtering for analysis purposes, variable sub-population
  filtering, and column selection are not part of this pipeline. Use the
  subsample makers for those needs.

STEP 6 — Deduplicate  [deduplicator.R]
  Detects duplicate uid+facility match keys in admissions and discharges
  separately.  When duplicates are found, keeps the row with the fewest NAs
  (the most complete record) and logs all duplicates to a CSV file.
  Possible genuine readmissions (same uid+facility, different admission times)
  are flagged in the log for manual review.

STEP 7 — Join admissions to discharges  [joiner.R]
  Creates a match_key column (uid + "_" + facility) in both data frames.
  Uses set intersection / set difference to produce:
    matched_pairs        — admissions with a matching discharge
    unmatched_adm        — admissions with no matching discharge
    unmatched_dis        — discharges with no matching admission
  Discharge columns that share names with admission columns (except match_key)
  are renamed with a "_dis" suffix in the matched_pairs dataset.

STEP 8 — Build master_joined  [master_builder.R]
  Combines matched_pairs and unmatched_adm into a single data frame:
    direct_match rows  — full admission + discharge data
    unmatched rows     — admission data only; discharge columns = NA
  Adds match_type and prob_match_similarity columns.
  master_joined contains ALL filtered admissions — the primary dataset
  for admission-level analyses.

STEP 9 — Detect probabilistic matching variables  [prob_matcher.R]
  Assesses completeness of each candidate matching variable in the FULL
  (unfiltered) admissions and discharges files.
  Variables with completeness below prob_match_completeness_threshold are
  excluded.  Reports which variables will be used, their completeness, and
  tolerances.

STEP 10 — Probabilistic matching  [prob_matcher.R]
  For each unmatched admission, scores candidate unmatched discharges using
  the variables selected in Step 9.  Scoring is facility-blocked (only pairs
  within the same facility are scored, unless prob_match_cross_facility = TRUE).
  Numeric variables use linear-decay scoring within their tolerance window.
  Categorical variables (gender, modedelivery, typebirth) use exact match.
  The greedy one-to-one assignment algorithm accepts the highest-scoring pair
  first, then removes both from further consideration, iterating until no
  candidates above the minimum similarity remain.

  DEFAULT (prob_match_min_similarity = 100): only perfect-scoring pairs are
  accepted.  This recovers records where the UID contains a single-character
  entry or scan error, while preventing coincidental clinical matches between
  different babies.

STEP 11 — Build master_joined_extended  [master_builder.R]
  Extends master_joined by upgrading unmatched admissions that received a
  probabilistic match:
    direct_match rows    — unchanged from master_joined
    prob_match rows      — discharge data filled from matched unmatched_dis row
    unmatched rows       — admissions that remain unmatched after both passes
  Adds prob_match_similarity scores for prob_match rows.
  master_joined_extended is the recommended dataset when discharge outcomes are
  needed and you want maximum coverage.

STEP 12 — Write outputs  [output_writer.R]
  Writes all output files.  When output_na_coded = TRUE and both na_coded
  source files were found in Step 2b, also writes na_coded variants of
  master_joined and master_joined_extended.
  See OUTPUTS section below.


================================================================================
OUTPUTS
================================================================================

All files are written to:
  outputs/{country}_master/{source}/   e.g. outputs/zim_master/from_database/

File prefix:  {COUNTRY}_{src}     e.g. ZIM_db, MWI_mb
Filter label: encodes the date window   e.g. to_20260228, 20220101_to_20260228

CSVs:
  {prefix}_joined_admissions_discharges_{label}.csv
      Matched admission+discharge pairs only (direct matches).
      Use for analyses requiring complete admission AND discharge data.

  {prefix}_unmatched_admissions_{label}.csv
      Admissions for which no matching discharge was found.

  {prefix}_unmatched_discharges_{label}.csv
      Discharges for which no matching admission was found in the date window.

  {prefix}_master_joined_{label}.csv
      ALL filtered admissions. Direct matches have discharge data; unmatched
      admissions have NA in all discharge columns.
      match_type column: "direct_match" or "unmatched"
      Recommended for admission-level analyses.

  {prefix}_master_joined_extended_{label}.csv
      As master_joined, but with an additional pass of probabilistic matching.
      match_type column: "direct_match", "prob_match", or "unmatched"
      prob_match_similarity: score 0–100 for prob_match rows; NA otherwise.
      Recommended when discharge outcomes are needed and coverage is important.

  {prefix}_master_joined_{label}_na_coded.csv           (only when output_na_coded = TRUE)
      Same rows and columns as master_joined, but NA values are represented as
      numeric sentinel codes (-7, -8, -9, etc.) matching the cleaning pipeline's
      na_coded output.  Use for ML model training where different types of
      missingness must be distinguished.

  {prefix}_master_joined_extended_{label}_na_coded.csv  (only when output_na_coded = TRUE)
      Na_coded equivalent of master_joined_extended.

  {prefix}_prob_assignments_{label}.csv   (only when prob matches found)
      One row per accepted probabilistic pair with similarity scores and the
      per-variable breakdown.

  {prefix}_prob_candidates_{label}.csv    (only when prob matches found)
      All candidate pairs above the minimum threshold (before one-to-one
      assignment), up to max_candidates per admission.

  {prefix}_duplicates_log.csv             (only when duplicates found)
      All duplicate uid+facility records from admissions and/or discharges,
      with the action taken (KEPT/REMOVED) and a possible_readmission flag.

Text reports:
  {prefix}_matching_statistics_{label}.txt
      Comprehensive statistics report covering: metadata, input file summary,
      date/facility filter results, deduplication results, direct matching
      summary, outcome distribution (neotreeoutcome), unmatched breakdowns by
      facility, master_joined summary, and a list of all output files written.

  {prefix}_prob_matching_report_{label}.txt  (only when prob matching ran)
      Detailed probabilistic matching report covering: configuration used,
      variables selected (with completeness %), candidate search statistics,
      one-to-one assignment results, per-variable score breakdown, top 20
      accepted pairs, and master_joined_extended summary.


================================================================================
CONSOLE OUTPUT
================================================================================

The script prints step-by-step progress to the console as it runs.  Each
module prefixes its messages with its name in square brackets, for example:

  [file_finder] Admissions file : zim_db_admissions_20260301_cleaned.csv
  [loader]   4721 records, 87 columns loaded from: ...
  [filter]   Date range in file : 2019-01-15  to  2026-03-18
  [filter]   AUTO date window : adm_end set to 2026-02-18 ...
  [dedup]   ADMISSIONS: no duplicate keys found
  [joiner] Matching results:
    Matched pairs        : 33755  (89.3% of admissions | ...)
  [master] Building master_joined dataset...
  [prob]   Variables selected for matching: birthweight, gestation, gender ...

If the script stops with an error, the message will indicate which module
raised it and usually what to check in config.R or the input files.


================================================================================
RUNNING MULTIPLE COMBINATIONS
================================================================================

To process all available data combinations at once, use run_all.R.
It scans the input/ folder automatically and requires no per-run configuration.

To run a specific subset manually, either:

  a) Edit config_sample_maker.R and re-run the script for each combination, or

  b) Create separate config files (e.g. config_zim_db.R, config_mwi_mb.R)
     and call:
       Rscript run_sample_maker.R config_zim_db.R
       Rscript run_sample_maker.R config_mwi_mb.R

Each run writes its outputs to its own subdirectory so there is no risk of
files overwriting each other.


================================================================================
TROUBLESHOOTING
================================================================================

"input directory not found"
  → Check that the input/ folder exists in the same directory as run_sample_maker.R.
  → Make sure you copied and renamed the cleaning pipeline output/ folder to input/.
  → Or set cleaning_pipeline_output_dir to a different path in config_sample_maker.R.

"No admissions subdirectory found for zim_db_admissions_..."
  → Verify that the input/ folder contains a subdirectory whose name starts with
    the expected prefix (e.g. zim_db_admissions_).
  → Country and source settings in config_sample_maker.R must match the folder names.
  → Folder name matching is case-insensitive, so capitalisation differences are handled.

"No admissions file found ... Expected a file starting with 'zim_db_admissions_'"
  → The subdirectory was found but contains no *_cleaned.csv file.
  → Check that the cleaning pipeline wrote its output correctly to that folder.

"Required column(s) missing from admissions file: uid"
  → The input CSV is missing an expected column.  Check the file header.

"No admissions remain after filtering"
  → The date window excludes all records.
  → The error message shows the available date range in the file.
  → Adjust adm_start_date or adm_end_date in config_sample_maker.R.

"Module not found: prob_matcher.R"
  → The modules/ directory must be in the same folder as run_sample_maker.R.

================================================================================
