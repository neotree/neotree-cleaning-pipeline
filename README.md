# Neotree cleaning pipeline

An R pipeline that cleans raw Neotree data exports for Zimbabwe and Malawi. For each input CSV it removes personal data, standardises columns and values against a data dictionary, assigns a type to every column, validates the values, and writes a cleaned dataset with reports and a reason code for every empty cell.

## Contents of the repository

```
README.md               this file
CHANGELOG.md            releases
CONTRIBUTING.md         how to propose a change
LICENSE                 MIT licence
VERSION                 version of the release
MANUAL.txt              the documentation files in one document

cleaning_pipeline_R/
  run_all.r             batch runner: every recognised file in input/
  run_pipeline.r        single-file runner
  install_packages.r    installs the required CRAN packages
  readme.md             overview of the pipeline
  how_to_run.md         run guide
  00_setup/ ... 16_na_reason_coding/
                        one folder per module, each with its script and README.md
  00_build_dictionary/  scripts that build and check the dictionaries
  dictionaries/         data dictionaries read by the pipeline
  user_dictionaries/    dictionaries for data users
  og_dictionaries/      public data dictionary read by the dictionary build
  neotree_data_keys/    data-key exports read by the dictionary build (downloaded, see below)
  neotree_scripts/      Neotree script metadata (downloaded, see below)
  tests/                test scripts
  input/                raw CSV files to clean
```

## Quick start

1. Install R, then install the packages:

   ```
   cd cleaning_pipeline_R
   Rscript install_packages.r
   ```

2. Place the raw CSV exports in `cleaning_pipeline_R/input/`, named `<country>_<dataset>_<date>.csv`, for example `zim_admissions_2026-01-31.csv`.

3. Run the batch:

   ```
   Rscript run_all.r
   ```

4. Read the results in `cleaning_pipeline_R/output/<file stem>/`: the cleaned CSV and RDS, the NA-reason files, the log and the `reports/` folder.

## Documentation

| Subject | File |
|---------|------|
| What the pipeline does, its inputs and outputs | `cleaning_pipeline_R/readme.md` |
| Installing, running, settings, tests | `cleaning_pipeline_R/how_to_run.md` |
| Rules applied by one module | `README.md` in the folder of that module |
| Dictionary sheets and columns | `cleaning_pipeline_R/dictionaries/README.md` |
| Building the dictionaries | `cleaning_pipeline_R/00_build_dictionary/README.md` |
| All of the above in one document | `MANUAL.txt` |

## Data

The repository contains code, dictionaries and documentation. It contains no study data. `cleaning_pipeline_R/input/` and `cleaning_pipeline_R/output/` are excluded from version control by `.gitignore`.

The data-key exports (`cleaning_pipeline_R/neotree_data_keys/`) and the script metadata (`cleaning_pipeline_R/neotree_scripts/`) are not included either, because they contain the names of health workers. They are downloaded from the Neotree web editors, https://webeditor.neotree.org/ and https://zim-dev-webeditor.neotree.org/, with a Neotree account. They are needed to rebuild the dictionaries and for Module 16 (the NA-reason codes); the README file in each folder says which files to place there. The dictionaries in the repository are already built and contain no staff names, so the pipeline runs without them, apart from Module 16.

The pipeline removes personal data as its first step and stops before writing any output if that step has not run for the input file.

## Licence

MIT. See `LICENSE`.
