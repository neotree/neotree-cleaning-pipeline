================================================================================
  Neotree Sample Maker
  README: run_data_profiler.R -- Variable profile utility
================================================================================

OVERVIEW
--------
run_data_profiler.R is a standalone utility that reads any pipeline CSV file
and writes a variable summary with data types and descriptive statistics.

It is not part of Pipeline 1, 2, or 3.  Run it any time you need to explore
what variables are available in a file and what values they contain, without
having to open the CSV directly.

Typical use cases:
  - Find the exact column name for a variable before setting sub_exclusion_filters
    in config_subsample_maker.R.
  - Check the range, mean, and typical values of a numeric variable (e.g.
    gestation, birthweight, apgar5) to set a sensible exclusion threshold.
  - Inspect the distinct values of a categorical variable (e.g. neotreeoutcome,
    modedelivery, gender) before using the "in" / "not_in" operator.
  - See the TRUE/FALSE balance of boolean variables (e.g. multiplicity, antenatalcare).
  - Assess data completeness (pct_missing) across all columns.


================================================================================
WHICH FILE TO PROFILE
================================================================================

Profile a Pipeline 1 OUTPUT file -- not a raw cleaned input file.

The data flow is:

  inputs/{country}/{source}/{cleaning}/
      admissions CSV  \
                       --> run_sample_maker.R --> outputs/.../
      discharges CSV  /                    master_joined.csv            <- profile this
                                           master_joined_extended.csv   <- or this

The raw cleaned files in inputs/ are separate admissions and discharges files
(pre-joining).  Their column names and row structure differ from the joined
master files that Pipeline 2 actually reads.

Profile master_joined (or master_joined_extended -- they have the same columns)
because sub_exclusion_filters and sub_variables in config_subsample_maker.R
must use the exact column names as they appear in those joined files.

Any Pipeline 1 output can be profiled: master_joined, master_joined_extended,
joined_admissions_discharges, joined_admissions_discharges_extended.
Pipeline 2 outputs (subsample_master, etc.) and anonymized files can also be
profiled, but for configuring filters, use the master file.


================================================================================
HOW TO RUN
================================================================================

----------------------------------------------------------------------
OPTION A -- Edit the embedded config, then run (simplest)
----------------------------------------------------------------------

1. Open run_data_profiler.R.
2. Set input_file in the PROFILER_CONFIG block near the top.
3. In RStudio click "Source", or from a terminal:
     Rscript run_data_profiler.R

----------------------------------------------------------------------
OPTION B -- Pass the input file as a command-line argument
----------------------------------------------------------------------

     Rscript run_data_profiler.R path/to/master_joined.csv

Relative paths are resolved from the working directory.  This is the
quickest way to profile a file without editing the script.

----------------------------------------------------------------------
Requirements (both options)
----------------------------------------------------------------------

  - R (any recent version)
  - Base R only -- no external packages required
  - The input CSV file must exist and be readable


================================================================================
CONFIGURATION  (PROFILER_CONFIG block inside the script)
================================================================================

  input_file
      Path to the CSV file to profile.
      Can be relative (resolved from the script directory) or absolute.
      Any pipeline output file is valid.

  output_dir
      NULL  -> outputs are written to the same directory as input_file.
      Or provide an explicit path: "outputs/zim_master/profiles"

  numeric_threshold   (default: 0.90)
      A column is classified as numeric when at least this proportion of its
      non-missing values can be coerced to a number.  The 0.90 default handles
      columns that contain occasional text codes alongside numeric values
      without misclassifying them as categorical.
      Set to 1.0 if you want strict numeric detection.

  max_numeric_distinct   (default: 500)
      Columns with more distinct values than this are always treated as
      categorical regardless of numeric_threshold.  This prevents treating
      large integer-coded identifier columns as numeric for statistics.


================================================================================
OUTPUTS
================================================================================

Two files are written per run, next to the input file (or in output_dir):

  {input_filename}_variable_profile.csv
      One row per column in the input file.  Columns present in every row:

        variable      Column name (exact, as it appears in the master file
                      header -- use this when setting sub_exclusion_filters
                      or sub_variables).
        type          "numeric", "boolean", or "categorical"
        n_total       Total rows in the input file.
        n_present     Rows with a non-missing value for this variable.
        n_missing     Rows that are NA or blank.
        pct_missing   Missing percentage.

      Additional columns for numeric variables:

        min           Minimum value (computed numerically).
        max           Maximum value.
        mean          Arithmetic mean.
        median        Median.
        sd            Standard deviation.
        mode_value    Most frequently occurring value, as stored in the CSV.
        n_distinct    Number of distinct non-missing values.
        sample_values Up to 3 of the most common raw values, pipe-separated,
                      exactly as they appear in the CSV file.
                      Use this to understand whether the variable contains
                      decimal values, because this affects which rows a
                      threshold catches.
                      Example: "38 | 37 | 36"       -- whole numbers only;
                                                        <= 24 catches exactly
                                                        those records.
                               "38.0 | 37.5 | 36.0" -- half-unit values exist;
                                                        <= 24 would also catch
                                                        24.5.
                      Note: in R, 24 and 24.0 are the same number, so the
                      number of decimals you write in value = ... has no
                      effect on the threshold itself.  What matters is
                      knowing what precision the data actually uses so you
                      can set the threshold deliberately.

      Additional columns for boolean variables:

        n_true        Count of TRUE values among non-missing rows.
        n_false       Count of FALSE values among non-missing rows.
        pct_true      Percentage of non-missing rows that are TRUE.
        sample_values Shown for completeness (will be "TRUE | FALSE" or
                      "TRUE" / "FALSE" if the column is all one value).

        Boolean columns originate from Neotree's TRUE/FALSE fields; R's
        read.csv converts them to R logical type automatically.  The profiler
        detects logical columns before applying numeric coercion, so they are
        never misclassified as numeric.

        To filter on a boolean column in sub_exclusion_filters, use the ==
        operator with value = TRUE or value = FALSE:
          list(variable = "multiplicity", operator = "==", value = TRUE)

      Additional columns for categorical variables:

        n_distinct    Number of distinct non-missing values.
        sample_values Up to 3 of the most common raw values, pipe-separated,
                      exactly as stored (preserves capitalisation and spacing).
                      Use these to confirm exact spelling before writing
                      value = "..." in sub_exclusion_filters.
        top1_value    Most frequent value (exact string).
        top1_n        Count of the most frequent value.
        top2_value    Second most frequent value.
        top2_n        Count of the second most frequent value.
        top3_value    Third most frequent value.
        top3_n        Count of the third most frequent value.

      Fields that do not apply to a given type are left blank in the CSV.

  {input_filename}_variable_profile.txt
      Human-readable version of the same data, formatted in four sections:
        NUMERIC VARIABLES     -- table with min / max / mean / median and
                                 sample_values (raw format, e.g. "24 | 25 | 28")
        BOOLEAN VARIABLES     -- table with n_true, n_false, pct_true
        CATEGORICAL VARIABLES -- table with n_distinct and top 3 values
                                 (shown exactly as stored, case-sensitive)
        MISSING DATA SUMMARY  -- all columns with > 0% missing, sorted
                                 by pct_missing descending

      The text report also prints notes explaining:
        - How to read sample_values to determine decimal format.
        - That for numeric filters, 24 and 24.0 are identical in R.
        - That boolean columns should be filtered with == TRUE / == FALSE.
        - That for categorical filters, values must be copied exactly
          (case-sensitive).


================================================================================
TYPICAL WORKFLOW: setting sub_exclusion_filters
================================================================================

1. Run the data profiler on the master file you will subsample from.

     Rscript run_data_profiler.R outputs/zim_master/.../ZIM_db_master_joined_to_20260228.csv

2. Open the resulting _variable_profile.txt in a text editor.

3. Find the variable you want to filter on in the NUMERIC VARIABLES table.
   Note the exact name in the "Variable" column, read the min / max / mean
   to choose a sensible threshold, and check sample_values to see how the
   data is stored.

   Example (gestation, weeks):
     Variable                       n    n_miss%       Min      Max     Mean   Median  sample_values (raw)
     gestation                   8234     1.2%       22.0     44.0     37.1     37.0   38 | 37 | 36

   The sample_values "38 | 37 | 36" tells you gestation is stored as whole
   numbers.  So <= 24 will catch records with gestation exactly 24 and below,
   and there are no 24.5 values in the data to worry about.
   If sample_values showed "38.0 | 37.5 | 36.0", half-week values exist and
   <= 24 would also catch 24.5 -- you would need to decide whether that is
   the intended behaviour.

4. Copy the exact variable name into config_subsample_maker.R:

     sub_exclusion_filters = list(
       list(variable = "gestation", operator = "<", value = 24)
     )

5. For boolean variables, find the column in the BOOLEAN VARIABLES table.
   Use the == operator with value = TRUE or value = FALSE.

   Example (multiplicity):
     Variable                          n    n_miss%   n_true   n_false   pct_true
     multiplicity                   8102     2.3%      312      7790       3.9%

     sub_exclusion_filters = list(
       list(variable = "multiplicity", operator = "==", value = TRUE)
     )

6. For categorical variables, find the column in CATEGORICAL VARIABLES.
   The top values are shown exactly as stored -- copy them precisely,
   including capitalisation.

   Example (neotreeoutcome):
     Variable                        n      n_miss%   n_dist   Top values
     neotreeoutcome               7892       4.5%        8    Discharged:5431  Died:1204  LAMA:831

   "LAMA" not "lama" or "Lama" -- copy exactly as shown.

     sub_exclusion_filters = list(
       list(variable = "neotreeoutcome", operator = "in", value = c("LAMA", "Absconded"))
     )

7. Re-run run_subsample_maker.R.  Section [4b] of the subsample report
   confirms how many rows each filter removed.


================================================================================
RELATIONSHIP TO OTHER SCRIPTS
================================================================================

run_data_profiler.R           -- utility: profile any CSV, no pipeline dependency
run_sample_maker.R            -- Pipeline 1: produces master_joined files
run_subsample_maker.R         -- Pipeline 2: reads master files, applies filters
config_subsample_maker.R      -- Pipeline 2 configuration (sub_exclusion_filters
                                 is set here, informed by the profiler output)
run_anonymizer.R              -- Pipeline 3: de-identifies output files


================================================================================
REQUIREMENTS
================================================================================

  R version  : >= 4.0
  Packages   : base R only (no external packages)

================================================================================
