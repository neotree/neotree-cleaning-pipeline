================================================================================
  Neotree Sample Maker — Full Pipeline Documentation
================================================================================
  Author  : David de Lorenzo, UCL GOS ICH
  Version : 1.4  (2026-05)
================================================================================

OVERVIEW
--------
The Neotree Sample Maker is a modular R pipeline for joining, cleaning, and
subsampling neonatal admission and discharge records from Neotree deployments
in Zimbabwe (ZIM) and Malawi (MWI).

It consists of two core pipelines plus two utility tools:

  Pipeline 1 — run_sample_maker.R  (or run_all.R for batch processing)
    PURPOSE: Joins admissions to discharges into master datasets.
    Processes ALL sources (database and metabase) — source filtering belongs
    in Pipeline 2.  Neolab, maternal, and all other standalone dataset types
    are skipped here and handled by Pipeline 2.

  Pipeline 2 — run_subsample_maker.R
    PURPOSE: Creates analysis-ready subsamples from master datasets or directly
    from cleaned files (admissions, discharges, neolab, maternal).
    Applies configurable date windows, facility filters, and column selection.
    Uses database ("db") files only by default; set INCLUDE_METABASE <- TRUE
    at the top of the script to also allow metabase ("mb") sources.
    For MWI maternal data, automatically uses combined_maternity_outcomes
    (the combined file already contains all rows from maternal_outcomes).

  Utility — run_data_profiler.R
    Profiles any pipeline CSV and writes a variable summary with types and
    descriptive statistics.  Use before configuring exclusion filters or to
    understand a new dataset.

  Utility — run_subsample_user_dict.R
    Combines the Neotree user data dictionary (variable descriptions, codes,
    and NA codes) with a statistical data profile into a single Excel workbook
    for sharing with research collaborators alongside a subsample data package.

RECOMMENDED WORKFLOW
  1. run run_all.R           -- builds master joined datasets (all sources)
  2. run run_subsample_maker.R -- filters to the date/facility/variable subset
                                  needed for each specific data request

--------------------------------------------------------------------------------
FOLDER STRUCTURE
--------------------------------------------------------------------------------

sample_maker_R/
│
├── run_all.R                       *** START HERE — batch runner for all datasets ***
│                                       Processes ALL files in input/ automatically.
│                                       No config editing required for a standard run.
│
├── run_sample_maker.R              Pipeline 1 (single pair only — see note below)
├── run_subsample_maker.R           Subsample maker (master mode OR cleaned mode)
├── run_anonymizer.R                Anonymizer (config embedded in script)
├── run_data_profiler.R             Utility — variable profile for any CSV
├── run_subsample_user_dict.R       Utility — researcher data package (dict + profile)
│
├── config_sample_maker.R              Pipeline 1 config — only needed for single-pair runs
│                                      (run_all.R does not use this file)
│
├── config_subsample_master_TEMPLATE.R  COPY THIS for each new master mode request
│                                       (joined admissions + discharges)
├── config_subsample_cleaned_TEMPLATE.R COPY THIS for each new cleaned mode request
│                                       (standalone per-type files: adm/dis/neolab/maternal)
├── config_subsample_TEMPLATE.R        Full annotated reference — all options documented
│                                      (read this; do not copy or edit)
├── config_subsample_maker.R           Default subsample config for ad-hoc use
├── modules/
│   ├── file_finder.R               Locates input CSV files (Mode A and B)
│   ├── pipeline_file_resolver.R    Shared helper for cleaning pipeline output
│   ├── loader.R                    Loads and validates data
│   ├── filter_data.R               Date/facility filtering + auto date window
│   ├── deduplicator.R              Resolves duplicate uid+facility keys
│   ├── joiner.R                    Direct uid+facility matching
│   ├── prob_matcher.R              Probabilistic matching engine
│   ├── master_builder.R            Assembles master_joined and _extended
│   ├── output_writer.R             Writes Pipeline 1 CSVs and reports
│   ├── subsample_maker.R           Filtering, column selection (master datasets)
│   ├── subsample_maker_cleaned.R   Generic subsample logic for cleaned CSV files
│   ├── subsample_maker_maternal.R  Maternal outcomes subsample logic
│   ├── subsample_maker_neolab.R    Neolab blood culture subsample logic
│   ├── data_profiler.R             Shared profiling module (auto-runs, STEP 13)
│   └── anonymizer.R                De-identification of any pipeline output file
│
├── input/                          PLACE CLEANING PIPELINE OUTPUT HERE (read-only)
│   │                               Copy and rename the cleaning pipeline output/ folder.
│   │                               Contents follow the cleaning pipeline naming:
│   ├── zim_db_admissions_20260301/
│   │   └── zim_db_admissions_20260301_cleaned.csv
│   ├── zim_db_discharges_20260301/
│   │   └── zim_db_discharges_20260301_cleaned.csv
│   ├── zim_db_neolab_20260301/
│   │   └── zim_db_neolab_20260301_cleaned.csv
│   ├── mwi_mb_admissions_2026-03-31/
│   │   └── mwi_mb_admissions_2026-03-31_cleaned.csv
│   └── ...  (one subdirectory per dataset type / data cut)
│
├── user_dictionaries/              User data dictionaries (copy here from cleaning pipeline)
│   ├── neotree_user_dict_zim.xlsx  Variable descriptions for Zimbabwe datasets
│   └── neotree_user_dict_mwi.xlsx  Variable descriptions for Malawi datasets
│
├── outputs/                        All pipeline outputs (auto-created by run_all.R)
│   └── zim_master/from_database/   or outputs/{country}_master/{source}/
│       ├── {prefix}_master_joined_{label}.csv
│       ├── {prefix}_master_joined_extended_{label}.csv
│       ├── {prefix}_master_joined_{label}_na_coded.csv          <- ML training variant
│       ├── {prefix}_master_joined_extended_{label}_na_coded.csv <- ML training variant
│       ├── {prefix}_joined_admissions_discharges_{label}.csv
│       ├── {prefix}_unmatched_admissions_{label}.csv
│       ├── {prefix}_unmatched_discharges_{label}.csv
│       ├── {prefix}_prob_match_assignments_{label}.csv
│       ├── {prefix}_prob_match_candidates_{label}.csv
│       ├── {prefix}_matching_statistics_{label}.txt
│       ├── {prefix}_prob_matching_report_{label}.txt
│       ├── {prefix}_subsample_{type}_{label}.csv               <- subsample outputs
│       ├── {prefix}_subsample_{type}_{label}_report.txt
│       ├── {prefix}_data_package_{label}.xlsx                  <- researcher data package
│       └── profiles/                                           <- auto-generated (STEP 13)
│           ├── {prefix}_cleaned_admissions_{label}_variable_profile.csv
│           ├── {prefix}_cleaned_admissions_{label}_variable_profile.txt
│           ├── {prefix}_cleaned_discharges_{label}_variable_profile.csv
│           ├── {prefix}_cleaned_discharges_{label}_variable_profile.txt
│           ├── {prefix}_master_joined_{label}_variable_profile.csv
│           ├── {prefix}_master_joined_{label}_variable_profile.txt
│           ├── {prefix}_master_joined_extended_{label}_variable_profile.csv
│           └── {prefix}_master_joined_extended_{label}_variable_profile.txt
│
└── README_files/                   Documentation

--------------------------------------------------------------------------------
PIPELINE 1 — STEP-BY-STEP
--------------------------------------------------------------------------------

STEP 1  File Finder  (modules/file_finder.R)
  Locates the admissions and discharges CSV files.

  MODE A (default — cleaning pipeline output):
    Looks inside the input/ folder for subdirectories matching the pattern
    {country}_{src}_{type}_{date}/ and finds the *_cleaned.csv inside.
    Matching is case-insensitive.  The most recently modified file is used
    if multiple data cuts are present.

  MODE B (legacy — direct file path):
    Constructs the path {cleaned_files_dir}/{country}/{source}/{cleaning}/
    and finds CSV files by prefix-matching.  Used only when
    cleaning_pipeline_output_dir is NULL in config_sample_maker.R.

STEP 2  Load Data  (modules/loader.R)
  Reads both CSV files and validates that required columns are present:
    Admissions : uid, facility, datetimeadmission
    Discharges : uid, facility

STEP 2b  Load na_coded Source Files  (modules/loader.R)  [when output_na_coded = TRUE]
  Locates and loads the *_cleaned_na_coded.csv counterparts alongside the
  standard admissions and discharges files.  These files use numeric sentinel
  codes (-7, -8, -9, etc.) instead of blank NA to distinguish types of
  missingness — needed for ML model training.  If either na_coded file is
  absent the pipeline continues normally and emits a warning (no error).

STEP 3  Parse Admission Dates  (modules/filter_data.R)
  Parses datetimeadmission into a POSIXct column (adm_date_parsed).
  Handles both full datetime ("YYYY-MM-DD HH:MM:SS") and date-only ("YYYY-MM-DD")
  values.  Records with unparseable dates are excluded from date filtering.

STEP 4  Resolve Date Window  (modules/filter_data.R)
  ONE-MONTH-IN-ARREARS LOGIC:
  If adm_end_date = NULL (default), the pipeline sets:
    adm_end_date = last admission date in file  −  1 calendar month
  This prevents inflating "unmatched" counts with babies still admitted at the
  time of data extraction.  The user can override this with an explicit date.

STEP 5  Filter Admissions  (modules/filter_data.R)
  Applies the date window and optional facility filter to admissions.
  Discharges are NOT filtered — all discharge records are available for matching.
  SIMPLE mode  (use_advanced_mode = FALSE): one global date window for all
               facilities (adm_start_date / adm_end_date from config).
  ADVANCED mode (use_advanced_mode = TRUE): per-facility date ranges defined
               in facility_date_ranges; useful when facilities have different
               data cut-off dates.

STEP 6  Variable Filter  (modules/filter_data.R)
  Optional: retains only admissions where a specified column matches target
  values (e.g. methodestgest IN {"USS"}).  Applied after the date/facility filter.

STEP 7  Deduplication  (modules/deduplicator.R)
  Detects duplicate uid+facility keys in both files.  When duplicates are found,
  the row with the fewest NA values is kept.  All duplicate groups are written to
  a DUPLICATES_LOG CSV for manual review.  Possible genuine readmissions
  (same uid+facility, different admission datetimes) are flagged.

STEP 7  Direct Join  (modules/joiner.R)
  Matches admissions to discharges using uid + facility as a composite key
  (set intersection).  Produces three datasets:
    matched_pairs       — admissions with a discharge found
    unmatched_adm       — admissions with no matching discharge
    unmatched_dis       — discharges with no matching admission in the filter window
  Overlapping column names in the discharge file receive a "_dis" suffix.

STEP 8  master_joined  (modules/master_builder.R)
  Combines matched_pairs and unmatched_adm into a single data frame.
  All discharge columns are set to NA for unmatched admissions.
  A match_type column flags each row: "direct_match" or "unmatched".

STEP 9  Variable Detection  (modules/prob_matcher.R)
  Auto-detects shared clinical variables suitable for probabilistic matching:
  present in both files and ≥ completeness_threshold non-NA.

STEP 10  Probabilistic Matching  (modules/prob_matcher.R)
  Searches unmatched admissions against unmatched discharges using clinical
  similarity scores.  Two phases:
    1. find_prob_candidates()  — scores all pairs within the same facility;
       optional cross-facility search for admissions with no within-facility
       candidate.  Returns top N candidates above the similarity threshold.
    2. assign_one_to_one()     — greedy assignment: sorts candidates by
       similarity descending; accepts top pair; removes both from pool; repeats.
       Each admission and discharge appears in at most one accepted pair.

  SIMILARITY SCORING (per variable, averaged):
    Numeric  : 100 at diff=0; linear decay to ~0 at diff=tolerance;
               continues to 0 at 2×tolerance; 0 beyond.
    Categorical : 100 for exact match; 0 for mismatch or NA.
    NA values  : excluded from denominator (variable skipped for that pair).

  DEFAULT BEHAVIOUR (prob_match_min_similarity = 100):
    Only pairs where every available variable matches exactly within tolerance
    are accepted.  In practice this recovers records where the UID was entered
    with a single-character typo or similar scan error, while rejecting
    coincidental clinical matches between different babies.
    NOTE: birthweight tolerances must be expressed in grams (the unit used by
    the cleaned Neotree data); the default tolerance of 20 corresponds to 20 g.

STEP 11  master_joined_extended  (modules/master_builder.R)
  Upgrades unmatched admission rows that received a probabilistic match:
  fills in discharge columns from the matched discharge record, sets
  match_type = "prob_match", and records the similarity score.

STEP 12  Write Outputs  (modules/output_writer.R)
  Writes all CSV files and two text reports.  When output_na_coded = TRUE and
  both na_coded source files were found in Step 2b, also writes na_coded
  variants of master_joined and master_joined_extended (sentinel-coded NA).

STEP 13  Automatic Data Profiling  (modules/data_profiler.R)
  Runs automatically at the end of every pipeline run.  Produces two files
  (CSV + TXT) per dataset, written to a profiles/ subfolder alongside the
  main outputs:

    profiles/{prefix}_cleaned_admissions_{label}_variable_profile.csv/.txt
    profiles/{prefix}_cleaned_discharges_{label}_variable_profile.csv/.txt
    profiles/{prefix}_master_joined_{label}_variable_profile.csv/.txt
    profiles/{prefix}_master_joined_extended_{label}_variable_profile.csv/.txt

  Each profile contains one row per column with: variable type
  (numeric/boolean/categorical), n present, missing rate, and descriptive
  statistics appropriate to the type (range/mean/median for numeric; top-3
  values for categorical; TRUE/FALSE counts for boolean).

  In run_all.R, ALL CSV files found anywhere in the input/ folder are also
  profiled at the start of the batch run, including dataset types that are
  not processed by the join pipeline (e.g. PHC, DHIS2, baseline surveys).
  Profiles for input files are written to a profiles/ subfolder alongside
  each input CSV.

  The standalone run_data_profiler.R remains available for profiling any
  arbitrary CSV on demand.  The module (modules/data_profiler.R) is shared
  by both — no external packages required.

--------------------------------------------------------------------------------
PIPELINE 2 — SUBSAMPLE MAKERS
--------------------------------------------------------------------------------

run_subsample_maker.R supports two source modes (set source_type in config):

  source_type = "master"  (default, backward compatible)
    Reads master_joined and master_joined_extended CSV files produced by
    Pipeline 1.  Outputs four files mirroring the Pipeline 1 naming convention.
    Use for analyses requiring both admission AND discharge data.

  source_type = "cleaned"
    Reads directly from cleaned CSV files in the input/ folder.  Each enabled
    dataset type (admissions, discharges, neolab, maternal) is processed
    independently and produces one CSV per type.
    Use when creating a multi-dataset data package, or when working with
    cleaned data before the join pipeline has been run.

Two additional standalone subsample makers handle specific dataset types:

  run_subsample_maker_maternal.R — Filters maternal outcome files (Mode A or B)
  run_subsample_maker_neolab.R   — Filters Neolab blood culture files (Mode A or B)

All subsample makers use the same general pattern:
  STEP 1  Load the input dataset
  STEP 2  Apply date window, facility filter, and exclusion filters
  STEP 3  Optionally restrict to a column subset
  STEP 4  Write output CSV and text report

See README_subsample_maker_maternal.md and README_subsample_maker_neolab.md
for detailed documentation of those tools.

--------------------------------------------------------------------------------
UTILITY — RESEARCHER DATA PACKAGE
--------------------------------------------------------------------------------

run_subsample_user_dict.R combines two sources of information into a single
Excel workbook designed to be shared alongside a subsample CSV:

  (a) Neotree user data dictionary
      Variable descriptions, types, allowed values, NA codes, and cross-dataset
      availability.  Read from neotree_user_dict_{country}.xlsx in the
      user_dictionaries/ folder.

  (b) Statistical data profile
      For each variable: n present, missing rate, and descriptive statistics
      (range / mean / median for numeric; top values for categorical;
      TRUE/FALSE counts for boolean).

OUTPUT:
  {prefix}_data_package_{label}.xlsx
      Sheets:
        About        — study name, country, run date, dataset summary table
        Admissions   — combined dict + profile (if admissions subsample provided)
        Discharges   — combined dict + profile (if discharges subsample provided)
        Neolab       — combined dict + profile (if neolab subsample provided)
        Maternal     — combined dict + profile (if maternal subsample provided)
        NA Codes     — legend of standard Neotree missing-value codes

USAGE:
  Edit DICT_CONFIG at the top of run_subsample_user_dict.R, then:
    Rscript run_subsample_user_dict.R
  Or pass an external config:
    Rscript run_subsample_user_dict.R my_study_dict_config.R

  AUTO MODE: set subsample_dir to discover all *_subsample_*.csv in a folder.
  MANUAL MODE: list specific files in subsample_files.

REQUIRES:  openxlsx package  (install.packages("openxlsx"))

TYPICAL WORKFLOW:
  1. Run run_subsample_maker.R to produce the subsample CSV(s).
  2. Ensure user_dictionaries/ contains neotree_user_dict_{country}.xlsx.
  3. Edit DICT_CONFIG (set subsample_dir or subsample_files, study_name, country).
  4. Run run_subsample_user_dict.R.
  5. Share the subsample CSV(s) together with the _data_package.xlsx workbook.

--------------------------------------------------------------------------------
PIPELINE 3 — ANONYMIZER
--------------------------------------------------------------------------------

run_anonymizer.R is a standalone script.  All configuration is embedded at
the top of the script in two sections:
  SECTION A — which files to process and where to write outputs
  SECTION B — additional columns to remove beyond the built-in defaults

WHAT THE ANONYMIZER ALWAYS DOES (built-in, not configurable from the script):
  Removes:   uid, uniquekey, match_key, adm_date_parsed
  Converts:  datetimeadmission → adm_yearmonth ("2024-03")
             datetimedischarge → dis_yearmonth

SECTION B lets you add any further columns specific to your data
(device IDs, HCW IDs, GPS coordinates, mother identifiers, etc.)

RECOMMENDED ORDER:
  run_all.R (or run_sample_maker.R)  ->  subsample makers  ->  run_anonymizer.R

The anonymizer should always run last because the subsample_maker relies on
exact datetimes and uid/facility for its filtering logic.

--------------------------------------------------------------------------------
UTILITY — DATA PROFILER
--------------------------------------------------------------------------------

Data profiling now happens automatically at the end of every pipeline run
(run_sample_maker.R STEP 13, and run_all.R) and after every subsample run
(run_subsample_maker.R).  Profile files are written to a profiles/ subfolder
alongside the pipeline outputs.  No configuration is needed — it just runs.

run_data_profiler.R is the standalone version for profiling any arbitrary CSV
on demand.  Use it to inspect a file before configuring filters, or to profile
a file that was produced outside the pipeline.

WHAT IT PRODUCES:
  {filename}_variable_profile.csv
      One row per column with:
        variable, type (numeric/boolean/categorical),
        n_total, n_present, n_missing, pct_missing
        Numeric columns:     min, max, mean, median, sd, mode_value, n_distinct
        Boolean columns:     n_true, n_false, pct_true
        Categorical columns: n_distinct, top1..3 values with counts

  {filename}_variable_profile.txt
      Human-readable version formatted for quick review in a text editor.

COLUMN TYPING RULES:
  numeric    : ≥ 90% of non-missing values are coercible to a number,
               AND the column has ≤ 500 distinct values.
  boolean    : R logical (TRUE/FALSE/NA) columns.
  categorical: everything else.

STANDALONE USAGE:
  Edit PROFILER_CONFIG near the top of run_data_profiler.R (set input_file),
  then:
    Rscript run_data_profiler.R
  Or pass the file path directly:
    Rscript run_data_profiler.R path/to/your_file.csv

TYPICAL WORKFLOW:
  1. Open the profiles/ subfolder created automatically after your pipeline run.
  2. Review {prefix}_master_joined_{label}_variable_profile.txt.
  3. Find the variable you want to filter on — read its min/max/mean/top values.
  4. Set sub_exclusion_filters using the exact column name and threshold.
  5. For a CSV not produced by the pipeline, use run_data_profiler.R directly.

--------------------------------------------------------------------------------
OUTPUTS — WHICH FILE TO USE FOR WHICH ANALYSIS
--------------------------------------------------------------------------------

Pipeline 1 and Pipeline 2 (run_subsample_maker.R) produce parallel sets of
files.  The table below shows the correspondence.

  PIPELINE 1 (full dataset)                   PIPELINE 2 (date/facility subsample)
  ------------------------------------------  ------------------------------------------------
  master_joined                               subsample_master
    All selected admissions.                    Same content, filtered to the
    Matched rows have full discharge data;      configured date window and facilities.
    unmatched rows have NA discharge cols.      Use for admission-level analyses.
    Use for admission-level analyses.

  master_joined_extended                      subsample_master_extended
    Same as master_joined but with              Same content, filtered.
    probabilistically recovered discharge       Increases matched row count vs the
    data for some previously unmatched rows.    _matched_only files.
    match_type = direct_match, prob_match,      Always report the match_type
    or unmatched.                               breakdown when using this file.

  joined_admissions_discharges                subsample_master_matched_only
    Direct uid+facility matched pairs only.     Filtered slice of the same.
    Every row has paired discharge data.        Every row has paired discharge data.
    Strictest "clean" matched set.              Use when only direct matches are needed.

  joined_admissions_discharges_extended       subsample_master_extended_matched_only
    Direct + probabilistic matched pairs.       Filtered slice of the same.
    Every row has paired discharge data.        Every row has paired discharge data.
    match_type = direct_match or prob_match.    Use for outcome analyses requiring
    Use to maximise sample size for outcome     maximum sample size.
    analyses.  Report match_type breakdown.     Report match_type breakdown.
  ------------------------------------------  ------------------------------------------------

ADDITIONAL PIPELINE 1 OUTPUTS

  unmatched_admissions           Admissions with no discharge found.  Contains
                                 admission data but no outcome.  Use for
                                 sensitivity analyses.

  unmatched_discharges           Discharges with no matching admission in the
                                 filter window.  Use for data quality review.

  prob_match_assignments         Accepted probabilistic pairs with similarity
                                 scores.  Review before using any _extended file.

  prob_match_candidates          All candidate pairs above the similarity
                                 threshold.  Use for investigating specific
                                 unmatched admissions.

  matching_statistics.txt        Primary quality report: filter counts,
                                 deduplication, match rates, outcome frequencies.

  prob_matching_report.txt       Probabilistic matching quality report:
                                 variables used, score distributions, per-variable
                                 breakdown for accepted assignments.

--------------------------------------------------------------------------------
FILE NAMING CONVENTION
--------------------------------------------------------------------------------

  {prefix}  : {COUNTRY}_{source_short}
              e.g. ZIM_db  (Zimbabwe, from_database)
                   MWI_db  (Malawi, from_database)
                   MWI_mb  (Malawi, from_metabase — only if INCLUDE_METABASE = TRUE)

  {label}   : derived from the admission date window and facility filter
              e.g. to_20260228          (auto mode, no start bound)
                   20240101_to_20261231 (explicit start and end)
                   20240101_to_20261231_SMCH  (with facility filter)
                   ALL                  (no date or facility filter)

  {sub_label}: same structure as {label} but derived from subsample settings.
               Suffixes appended when options are active:
                 "_Nvars"        column selection is active (N = variable count)
                 "_excl"         exclusion filters are active
                 "_matched_only" sub_matched_only = TRUE

--------------------------------------------------------------------------------
QUICK START — BATCH PROCESSING (recommended)
--------------------------------------------------------------------------------

  1. Run the cleaning pipeline for all datasets (Zimbabwe and/or Malawi).

  2. Copy the cleaning pipeline output/ folder into the sample_maker_R/
     directory and rename it input/.

  3. Open run_all.R.  Review the optional filter settings at the top:
       RUN_ALL_FILTER   <- NULL           # leave NULL to process all datasets
       RUN_ALL_SKIP     <- character(0)   # datasets to skip by name

  4. Source run_all.R (RStudio) or:
       Rscript run_all.R

     The script will:
     - Discover all datasets in input/
     - Join admissions+discharges pairs for ALL sources (db and mb)
     - Skip neolab, maternal, and all other standalone types
       (these belong in run_subsample_maker.R)
     - Print a batch summary with elapsed time and pass/fail status

  5. Check the batch summary output.  All results are written to outputs/.
     Na_coded variants (*_na_coded.csv) of the master files are written
     automatically when output_na_coded = TRUE (the default) and the cleaning
     pipeline produced *_cleaned_na_coded.csv files in the input/ folder.

  6. Variable profiles are created automatically.  Open:
       outputs/zim_master/from_database/profiles/{prefix}_master_joined_{label}_variable_profile.txt
     to inspect variable types, missing rates, and descriptive statistics
     before configuring sub_exclusion_filters.
     For profiling a file on demand, use run_data_profiler.R directly:
       Rscript run_data_profiler.R path/to/your_file.csv

  7. To create a subsample for a data access request, note that
     run_subsample_maker.R uses database ("db") files by default.
     Set INCLUDE_METABASE <- TRUE at the top of the script only if you
     specifically need metabase ("mb") source files.
     For MWI maternal data, the script automatically uses
     combined_maternity_outcomes regardless of which files are in input/.

     Copy the appropriate template(s) and rename them for the researcher:

     - Master mode (joined admissions + discharges):
         Copy config_subsample_master_TEMPLATE.R
         Fill in: master file paths, date window, facility, variable list.

     - Cleaned mode (standalone per-type files for DSH or neolab/maternal):
         Copy config_subsample_cleaned_TEMPLATE.R
         Fill in: country/source, date window, facility, per-dataset variables.

     Run both with:
       Rscript run_subsample_maker.R config_subsample_StudyName_Nvars.R
       Rscript run_subsample_maker.R config_subsample_StudyName_cleaned.R

     Write both to the same output_dir.  See README_run_subsample_maker.txt and
     the config_subsample_*_TEMPLATE.R files for a worked example.

  8. To generate a researcher data package (dictionary + statistics workbook):
       Edit DICT_CONFIG in run_subsample_user_dict.R (or in a separate config file),
       then:
         Rscript run_subsample_user_dict.R
       This produces a {prefix}_data_package_{label}.xlsx combining variable
       descriptions with a statistical profile of the subsample.
       Requires: install.packages("openxlsx")

  9. To share a de-identified dataset: edit run_anonymizer.R and run:
       Rscript run_anonymizer.R

--------------------------------------------------------------------------------
QUICK START — SINGLE PAIR (use only when run_all.R is not appropriate)
--------------------------------------------------------------------------------

  Use this approach only when you need to (re-)process a specific
  country/source pair without running everything — for example, after
  receiving a new data extract for one country while the other is unchanged,
  or when testing a non-default date window for a single pair.

  For all other cases use run_all.R (see above).

  1. Copy the cleaning pipeline output/ folder → input/ (same as above).

  2. Open config_sample_maker.R.  Set country and source.  Leave
     adm_start_date and adm_end_date as NULL for the auto one-month
     in-arrears window, or set explicit dates.

  3. Source run_sample_maker.R (RStudio) or:
       Rscript run_sample_maker.R

  4. Check the matching_statistics_{label}.txt report in outputs/.

--------------------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------------------

  R version  : >= 4.0

  Core pipeline (base R only — no external packages required):
    run_sample_maker.R, run_subsample_maker.R, run_all.R,
    run_anonymizer.R, run_data_profiler.R, and all modules.

  Researcher data package (one additional package):
    run_subsample_user_dict.R requires openxlsx.
    Install once with:  install.packages("openxlsx")

  No tidyverse, dplyr, or lubridate dependencies anywhere.

================================================================================
  End of pipeline documentation
================================================================================
