================================================================================
  Neotree Sample Maker
  README: run_all.R — Batch runner for all datasets
================================================================================
  Author  : David de Lorenzo, UCL GOS ICH
  Version : 1.0  (2026-05)
================================================================================

OVERVIEW
--------
run_all.R is the recommended entry point for the Neotree Sample Maker.
It discovers all datasets in the input/ folder, routes each one to the
correct processing pipeline, and prints a batch summary at the end.

No manual file-by-file configuration is needed.  One script processes
everything in a single run.


================================================================================
HOW TO USE
================================================================================

1. Copy the cleaning pipeline output/ folder into the sample_maker_R/
   directory and rename it input/.

2. (Optional) Open run_all.R and review the filter settings near the top:

     RUN_ALL_FILTER <- NULL
       Leave NULL to process all discovered datasets.
       Set to a character vector to process only those names, e.g.:
         RUN_ALL_FILTER <- c("zim_db", "mwi_mb")

     RUN_ALL_SKIP <- character(0)
       Dataset names to skip regardless of RUN_ALL_FILTER.
       e.g. RUN_ALL_SKIP <- c("zim_db_neolab")

3. Run from RStudio (click Source) or from the terminal:
     Rscript run_all.R

4. Review the batch summary printed at the end.  All outputs are written
   to the outputs/ folder (auto-created).


================================================================================
WHAT run_all.R DOES
================================================================================

DISCOVERY
  Scans all immediate subdirectories of input/, looking for names that match
  the cleaning pipeline naming convention:
    {country}_{src}_{dataset}_{date}/
  where country ∈ {mwi, zim}, src ∈ {db, mb}.

ROUTING
  Each discovered dataset is routed to one of four categories:

  JOIN PAIRS (admissions + discharges)
    Datasets named *_admissions_* and *_discharges_* are paired by
    country+source.  Each pair is processed through the full 12-step
    Pipeline 1 (join, deduplication, probabilistic matching).

    Outputs written to: outputs/{country}_{src}/
    e.g. outputs/zim_db/

  NEOLAB
    Datasets named *_neolab_* are processed through the neolab subsample
    maker using default settings (full date range, all facilities, all columns).

    Outputs written to: outputs/{country}_{src}_neolab/
    e.g. outputs/zim_db_neolab/

  MATERNAL
    Datasets named *_maternal_outcomes_* or *_combined_maternity_outcomes_*
    are processed through the maternal subsample maker using default settings.

    Outputs written to: outputs/{country}_{src}_maternal/
    e.g. outputs/mwi_mb_maternal/

  SKIP (known non-target datasets)
    The following dataset types are recognised but intentionally skipped:
      phc_admissions, phc_discharges, baseline, infections,
      twenty_8_day_follow_up, dhis2_maternal_outcomes, maternity_completeness

  UNKNOWN
    Datasets that do not match any recognised pattern are reported in the
    batch summary with status UNKNOWN and are not processed.

BATCH SUMMARY
  After all runs complete, a summary table is printed showing each dataset,
  its routed type, elapsed time, and pass/fail status.


================================================================================
IMPORTANT: DEFAULT SETTINGS FOR BATCH RUNS
================================================================================

When run_all.R processes a join pair, neolab, or maternal dataset, it applies
the following defaults:

  Join pairs:   Auto one-month-in-arrears date window (adm_end_date = NULL),
                all facilities, probabilistic matching with min_similarity = 100.

  Neolab:       Full date range (sub_start_date = NULL, sub_end_date = NULL),
                all facilities, all columns.

  Maternal:     Full date range, all facilities, all columns.

If you need a specific date window, facility filter, column selection, or
exclusion filters for a particular dataset, use the individual run scripts
instead (run_sample_maker.R, run_subsample_maker_neolab.R, or
run_subsample_maker_maternal.R) with a custom config file.

run_all.R is designed for building complete master and reference datasets.
Tailored extracts for specific studies should be produced using the subsample
makers with study-specific config files.


================================================================================
REQUIREMENTS
================================================================================

  - R >= 4.0
  - Base R only — no external packages required
  - modules/ directory alongside run_all.R
  - input/ folder with cleaning pipeline output


================================================================================
TROUBLESHOOTING
================================================================================

"input/ directory not found"
  → The input/ folder does not exist in the same directory as run_all.R.
  → Copy and rename the cleaning pipeline output/ folder to input/.

"No matching subdirectory found for ..."
  → A join pair is missing its partner (e.g. admissions found but no discharges).
  → Check that both admissions and discharges are present in input/ for each
    country+source combination you want to join.

"Module not found: ..."
  → The modules/ directory must be in the same folder as run_all.R.

"FAILED" in batch summary
  → The error message for that run is printed above the summary table.
  → Check the input files for that dataset type.
  → For an admissions+discharges failure: edit config_sample_maker.R to set
    the correct country/source, then run:
      Rscript run_sample_maker.R
  → For a neolab or maternal failure: create a config from
    config_subsample_TEMPLATE.R (source_type = "cleaned") and run:
      Rscript run_subsample_maker.R /path/to/your_config.R

================================================================================
