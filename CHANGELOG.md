# Changelog

All notable changes to the Neotree Cleaning Pipeline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Repository releases are published as git tags / GitHub releases, starting at
v1.0.0. (The data dictionaries packaged in this release are versioned
separately by Neotree as "v8".)

## [v1.0.0] — 2026-07

First public, version-controlled release of the R data pipeline (packaging the
v8 Neotree data dictionaries).

### Cleaning pipeline (`cleaning_pipeline_R/`)
- Numbered, sequential modules from `00_setup` through `16_na_reason_coding`,
  each self-documented with its own `README.md`.
- PII detection and removal as the first processing step (`00a`), ahead of any
  cleaning.
- v8 data dictionaries (Malawi and Zimbabwe) and dictionary-builder scripts.
- Categorical value harmonisation to dictionary **canonical codes**
  (case-insensitive code/label matching). The harmonisation is decision-free:
  values that do not resolve are left untouched and logged, never guessed.
- Clinically confirmed legacy→canonical mappings encoded as `VALUEMAP_PATCHES`
  in the dictionary build, covering the high-volume categorical fields
  (`inorout`, `modedelivery`, `admittedfrom`, `admreason`, `diagdis1`, and
  others). Values with no current target remain unresolved pending clinical
  confirmation.
- Dictionary documentation enrichment from the 2024 public Neotree dictionary
  (`00e_enrich_from_public_dictionary.r`), adding meaning, data type, dependency,
  range, historical variable name and change-timeline columns. Documentation
  only — cleaning behaviour is unaffected.
- Canonical derived weight columns in module 15: `birthweight_g`,
  `admission_weight_g` and `discharge_weight_g`, resolving the three distinct
  weight concepts that successive form versions stored under different names.
  Source columns are preserved untouched.
- Two-stage deduplication (visit-level then patient-level) keeping the most
  complete record, with patient-level dedup disabled for longitudinal datasets
  (`neolab`, `infections`).
- Definitional-bound numeric validation (Apgar, Thompson, SpO2), boolean,
  categorical and datetime validation modules.
- NA-reason coding (module 16) with a per-variable skip-logic reference, so a
  value that is missing because the form never asked for it is distinguishable
  from one that is genuinely absent.

### Repository scope
- The sample maker (joining, deduplication, probabilistic matching and
  subsampling) now lives in its own repository,
  [neotree-sample-maker](https://github.com/neotree/neotree-sample-maker), so
  that each half can be versioned, released and depended on independently. It
  was briefly published alongside the cleaning pipeline in this repository
  before the split.

### Documentation
- `MANUAL.txt`: every README in this repository compiled into one searchable
  document with a table of contents.
- Appendix (`MANUAL.txt` Part IV): catalogue of known variable-level issues in
  the raw Neotree exports, stating for each whether the pipeline fixes it or the
  analyst must handle it.

### Packaging
- CRAN installer (`install_packages.r`) and UCL Data Safe Haven / Artifactory
  installer (`install_packages_dsh.r`).
- MIT licence, contribution guide, and `.gitignore` that excludes all
  patient-level data, run artifacts and credentials.

[v1.0.0]: https://github.com/neotree/neotree-cleaning-pipeline/releases/tag/v1.0.0
