# Neotree Data Pipeline

R pipelines for cleaning, validating and subsampling neonatal clinical data
collected through [Neotree](https://www.neotree.org) deployments in **Malawi**
and **Zimbabwe**.

The repository contains two pipelines that run in sequence:

1. **`cleaning_pipeline_R/`** — cleans and validates raw data exported from the
   Neotree PostgreSQL database (directly or via Metabase) into a faithful,
   typed, harmonised master dataset.
2. **`sample_maker_R/`** — joins, deduplicates, probabilistically matches and
   subsamples the cleaned output into analysis-ready, anonymised data packages
   for specific research requests.

```
cleaning_pipeline_R   →   cleaned master dataset   →   sample_maker_R   →   shareable subsample
   (validate & type)        (output/ CSV + RDS)         (join & subsample)     (anonymised package)
```

---

## Repository structure

```
neotree-data-pipeline/
├── README.md                  ← this file
├── MANUAL.txt                 ← every README in one searchable document
├── CHANGELOG.md
├── LICENSE                    ← MIT
├── .gitignore
├── CONTRIBUTING.md
│
├── cleaning_pipeline_R/       ← Pipeline 1: cleaning & validation
│   ├── run_pipeline.r             single-file runner
│   ├── run_all.r                  batch runner (all files in input/)
│   ├── install_packages.r         CRAN installer
│   ├── install_packages_dsh.r     UCL Data Safe Haven (Artifactory) installer
│   ├── 00_build_dictionary/       builds the data dictionaries the pipeline reads
│   ├── 00_setup/ … 16_na_reason_coding/   numbered modules (run in order)
│   ├── dictionaries/              generated v8 data dictionaries (.xlsx)
│   ├── og_dictionaries/           2024 public Neotree dictionary (00e input)
│   ├── user_dictionaries/         researcher-facing variable dictionaries
│   ├── neotree_data_keys/         downloaded Neotree data keys (MWI / ZIM)
│   ├── neotree_scripts/           Neotree form definitions (metadata + data keys)
│   ├── input/                     ← drop raw CSV exports here (git-ignored)
│   ├── readme.md                  full pipeline documentation
│   └── how_to_run.md              step-by-step run guide
│
└── sample_maker_R/            ← Pipeline 2: join & subsample
    ├── run_all.R                  batch runner (recommended entry point)
    ├── run_sample_maker.R         Pipeline 1: join admissions ↔ discharges
    ├── run_subsample_maker.R      Pipeline 2: date/facility/variable subsets
    ├── run_anonymizer.R           anonymise outputs
    ├── run_data_profiler.R        variable profiling
    ├── run_subsample_user_dict.R  build researcher data-dictionary workbook
    ├── install_packages.r         CRAN installer (mostly base R)
    ├── install_packages_dsh.r     UCL Data Safe Haven (Artifactory) installer
    ├── config_*.R                 configuration + TEMPLATE config files
    ├── modules/                   pipeline modules (loader, joiner, matcher, …)
    ├── README_files/              detailed documentation
    └── subsamples/                ← per-request outputs written here (git-ignored)
```

---

## Requirements

- **R ≥ 4.0**
- The **cleaning pipeline** uses 12 CRAN packages (jsonlite, readr, readxl,
  writexl, dplyr, tidyr, stringr, lubridate, purrr, logger, janitor, tibble).
- The **sample maker** runs on base R; only `openxlsx` (Excel export) and
  `rstudioapi` (interactive use) are optional.

### Installing packages

Standard environment (CRAN reachable):

```r
# from cleaning_pipeline_R/
source("install_packages.r")

# from sample_maker_R/
source("install_packages.r")
```

Inside the **UCL Data Safe Haven (DSH)**, CRAN is not directly reachable and
packages are mirrored through Artifactory. Use the `_dsh` variant instead, after
pasting your personal Artifactory Bearer token into the placeholder at the top
of the script:

```r
source("install_packages_dsh.r")
```

> **Never commit a real Artifactory token.** The committed scripts must keep the
> `YOUR_ARTIFACTORY_TOKEN_HERE` placeholder.

---

## Quick start

```bash
# 1. Clean raw data
cd cleaning_pipeline_R
# place raw CSV exports in input/  (see readme.md for the naming convention)
Rscript run_all.r            # processes every matching file in input/

# 2. Build subsamples from the cleaned output
cd ../sample_maker_R
# copy the cleaning pipeline's output/ folder here and rename it input/
Rscript run_all.R            # builds master joined datasets
Rscript run_subsample_maker.R   # filter to a specific request
```

---

## Documentation

Every module ships a README next to its code, so documentation sits beside the
thing it describes. The same content is also compiled into a single file:

**[`MANUAL.txt`](MANUAL.txt)** — the complete manual. Every README from both
pipelines, in reading order, with a table of contents. Use it to search the
whole documentation set at once, or to read/print it as one document.

Start here depending on what you need:

| You want to… | Read |
|---|---|
| Run the cleaning pipeline | `cleaning_pipeline_R/how_to_run.md` |
| Understand what the cleaning pipeline does and why | `cleaning_pipeline_R/readme.md` |
| Run or configure the sample maker | `sample_maker_R/README_files/README_PIPELINE.txt` |
| Understand one module | the `README` in that module's folder |
| Search everything at once | `MANUAL.txt` |

### Known issues in the source data — read before analysing

`MANUAL.txt` **Part VII** is a catalogue of known variable-level problems in the
raw Neotree exports themselves, not in this code. Most stem from one cause:
several versions of the Neotree app have been deployed at each site over the
years, and the database export concatenates records from all of them, so a
single column can carry more than one encoding of the same clinical concept.

The catalogue states, per variable, what the problem is, whether the pipeline
already fixes it, and what an analyst must still handle. Read it before using
any cleaned or master dataset for analysis.

---

## Data governance

This repository ships **code, reference dictionaries and documentation only**.
It contains **no patient-level data**.

- Raw CSV exports go in `cleaning_pipeline_R/input/` and are git-ignored.
- Subsample outputs are written to `sample_maker_R/subsamples/` and `outputs/`,
  both git-ignored.
- The cleaning pipeline removes personally identifying information as its first
  step (module `00a_pii_detection_removal`); the sample maker additionally
  anonymises shared extracts.

Do not commit any file containing patient data, free-text identifiers, database
credentials or access tokens. See `.gitignore` for the enforced exclusions.

---

## Provenance

Developed by **David de Lorenzo**, UCL Great Ormond Street Institute of Child
Health (Population, Policy & Practice), for the Neotree project.

Two deployment targets are supported from a single codebase: a standard
environment (CRAN) and the UCL Data Safe Haven (Artifactory). The behaviour of
the pipelines is identical; only the package-installation method differs.
