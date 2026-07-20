# Neotree Cleaning Pipeline

R pipeline for cleaning and validating neonatal clinical data collected through
[Neotree](https://www.neotree.org) deployments in **Malawi** and **Zimbabwe**.

It takes raw data exported from the Neotree PostgreSQL database (directly or via
Metabase) and produces a faithful, typed, dictionary-conformant cleaned dataset.

```
raw Neotree export   →   cleaning_pipeline_R   →   cleaned dataset   →   neotree-sample-maker
    (CSV / Metabase)      (validate & type)        (output/ CSV + RDS)     (separate repository)
```

Downstream work — joining admissions to discharges, building master datasets and
cutting analysis-ready subsamples — lives in a separate repository:
**[neotree-sample-maker](https://github.com/neotree/neotree-sample-maker)**.

The two are loosely coupled: this pipeline writes cleaned datasets to `output/`,
and the sample maker reads whatever it is given. Neither requires the other to
be present to run.

---

## What it does

Sequential, numbered modules, each self-documented and runnable in order:

| Stage | Modules | What happens |
|---|---|---|
| Preparation | `00_build_dictionary`, `00_setup` | Build the data dictionaries the pipeline validates against |
| De-identification | `00a_pii_detection_removal` | PII detected and removed **first**, ahead of any cleaning |
| Structural repair | `00b`–`03` | Harmonise column names, correct frame shifts, merge duplicate columns |
| Value cleaning | `04`–`08` | Reduce values to dictionary canonical codes, forward-fill, drop label and autopopulated columns |
| Typing and validation | `09`–`14a` | Assign data types, remove duplicate rows, validate numeric, boolean, categorical and datetime fields |
| Output | `15`, `16` | Final merge, derived canonical columns, NA-reason coding |

Two design decisions worth knowing before you use the output:

**Categorical harmonisation is decision-free.** Values are reduced to the
dictionary's canonical codes by case-insensitive code and label matching. A
value that does not resolve is left untouched and logged — never guessed, never
coerced to a nearby code.

**Only definitional bounds are enforced.** Numeric validation rejects values that
are impossible by definition (an Apgar score above 10, a percentage above 100).
Clinically implausible but definitionally possible values are retained, so the
cleaned dataset stays a faithful record of what was collected. Clinical
plausibility filtering belongs downstream, before data is shared.

---

## Repository structure

```
neotree-cleaning-pipeline/
├── README.md                  ← this file
├── MANUAL.txt                 ← every README in one searchable document
├── CHANGELOG.md
├── LICENSE                    ← MIT
├── CONTRIBUTING.md
│
└── cleaning_pipeline_R/
    ├── run_all.r                  batch runner (all files in input/) — start here
    ├── run_pipeline.r             single-file runner
    ├── install_packages.r         CRAN installer
    ├── install_packages_dsh.r     UCL Data Safe Haven (Artifactory) installer
    │
    ├── 00_build_dictionary/       builds the dictionaries the pipeline reads
    ├── 00_setup/ … 16_na_reason_coding/   numbered modules (run in order)
    │
    ├── dictionaries/              generated v8 data dictionaries (.xlsx)
    ├── og_dictionaries/           2024 public Neotree dictionary (00e input)
    ├── user_dictionaries/         researcher-facing variable dictionaries
    ├── neotree_data_keys/         downloaded Neotree data keys (MWI / ZIM)
    ├── neotree_scripts/           Neotree form definitions (metadata + data keys)
    │
    ├── input/                  ← drop raw CSV exports here (git-ignored)
    ├── readme.md                  full pipeline documentation
    └── how_to_run.md              step-by-step run guide
```

---

## Requirements

- **R ≥ 4.0**
- 12 CRAN packages: jsonlite, readr, readxl, writexl, dplyr, tidyr, stringr,
  lubridate, purrr, logger, janitor, tibble.

### Installing packages

Standard environment (CRAN reachable):

```r
# from cleaning_pipeline_R/
source("install_packages.r")
```

Inside the **UCL Data Safe Haven (DSH)**, CRAN is not directly reachable and
packages are mirrored through Artifactory. Use the `_dsh` variant instead, after
pasting your personal Artifactory Bearer token into the placeholder at the top
of the script:

```r
source("install_packages_dsh.r")
```

> **Never commit a real Artifactory token.** The committed script must keep the
> `YOUR_ARTIFACTORY_TOKEN_HERE` placeholder.

---

## Quick start

```bash
cd cleaning_pipeline_R

# place raw CSV exports in input/  (see readme.md for the naming convention)
Rscript run_all.r            # processes every matching file in input/
```

Cleaned datasets are written to `output/`, one subdirectory per dataset, each
with its own per-module reports. To carry on into subsampling, copy those
subdirectories into the sample maker's `input/` folder — see
[neotree-sample-maker](https://github.com/neotree/neotree-sample-maker).

---

## Documentation

Every module ships a README next to its code. The same content is also compiled
into a single file:

**[`MANUAL.txt`](MANUAL.txt)** — the complete manual. Every README from this
pipeline, in reading order, with a table of contents. Use it to search the whole
documentation set at once, or to read and print it as one document.

| You want to… | Read |
|---|---|
| Run the pipeline | `cleaning_pipeline_R/how_to_run.md` |
| Understand what it does and why | `cleaning_pipeline_R/readme.md` |
| Understand one module | the `README` in that module's folder |
| Search everything at once | `MANUAL.txt` |

### Known issues in the source data — read before analysing

`MANUAL.txt` **Part IV** is a catalogue of known variable-level problems in the
raw Neotree exports themselves, not in this code. Most stem from one cause:
several versions of the Neotree app have been deployed at each site over the
years, and the database export concatenates records from all of them, so a
single column can carry more than one encoding of the same clinical concept.

The catalogue states, per variable, what the problem is, whether the pipeline
already fixes it, and what an analyst must still handle. Read it before using
any cleaned dataset for analysis — several issues survive cleaning by design.

---

## Data governance

This repository ships **code, reference dictionaries and documentation only**.
It contains **no patient-level data**.

- Raw CSV exports go in `cleaning_pipeline_R/input/` and are git-ignored.
- Cleaned output is written to `cleaning_pipeline_R/output/`, also git-ignored.
- The pipeline removes personally identifying information as its first step
  (module `00a_pii_detection_removal`).

Do not commit any file containing patient data, free-text identifiers, database
credentials or access tokens. See `.gitignore` for the enforced exclusions.

---

## Provenance

Developed by **David de Lorenzo**, UCL Great Ormond Street Institute of Child
Health (Population, Policy & Practice), for the Neotree project.

Two deployment targets are supported from a single codebase: a standard
environment (CRAN) and the UCL Data Safe Haven (Artifactory). The behaviour of
the pipeline is identical; only the package-installation method differs.
