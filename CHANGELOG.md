# Changelog

All notable changes to the Neotree Cleaning Pipeline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Repository releases are published as git tags / GitHub releases, starting at
v1.0.0. (The data dictionaries packaged in this release are versioned
separately by Neotree as "v8".)

## [v1.1.0] — 2026-08

A maintenance release. One defect suppressed all output for two dataset types;
the same defect class was removed pipeline-wide, batch failure reporting was
added so a repeat cannot pass unnoticed, and the pipeline's derived maternal-age
columns are now documented in the dictionaries.

### Fixed

- **Module 15 aborted silently for two Malawi maternity datasets, producing no
  output at all.** `derive_maternal_age_columns()` formatted its maternal-age
  disagreement warning with its own `sprintf()` and passed the finished string to
  `log_warn()`. Because `00_setup.r` sets `log_formatter(formatter_sprintf)`, the
  logger formatted it a second time: the first pass renders `%.1f%%` as a literal percent sign
  (e.g. `(12.5%);`), the second hits `%)` and R throws `Error: too few arguments`. Any
  dataset reaching that branch — in practice `combined_maternity_outcomes` and
  `dhis2_maternal_outcomes`, the only ones where both maternal-age sources are
  populated and can disagree — produced no `*_cleaned.csv`, no `*_cleaned.rds` and
  no `15b_maternal_age_summary.txt`. This was a data-availability failure only: no
  value was ever computed incorrectly. Anyone who ran an earlier version should
  re-run the pipeline before using either dataset.
- **The same double-formatting construction was removed pipeline-wide** (21 call
  sites). Two were live rather than latent hazards, because they interpolate
  rejected raw data values into the log message, so a single `%` in a source cell
  would have aborted those modules identically: `12_boolean_validation.r` and
  `14_datetime_validation.r`. The rule now applied throughout: never pass a
  pre-formatted string to `log_info`/`log_warn`/`log_error`/`log_debug` — pass the
  format string and its arguments and let the logger format once.

### Changed

- **`run_all.r` now reports per-file failures.** It previously caught an error,
  printed it mid-run and moved on without recording it, which is why the above went
  unnoticed. It now captures each error message and prints a failure summary at the
  end listing the file, its dataset and the error — or
  `Failure summary: none - every file completed the full pipeline.` when the batch
  is clean. Check this line before treating a run as successful.

### Added

- **The derived maternal-age columns are now documented in the dictionaries.**
  `mat_age_years_combined` and `mat_age_source` (module 15) and
  `mat_age_date_years` (module 11) were written to every cleaned file but
  registered nowhere, so they appeared in the data with no definition anywhere in
  the dictionary set. All three are now registered in `DERIVED_VARIABLES`
  (`00_build_dictionary.r`) and surfaced in the researcher-facing user dictionary
  via `00d`. Documentation only — verified by re-running the pipeline and
  confirming the cleaned output is byte-for-byte identical.
- `00d_build_user_dictionary.r` keeps its own `DERIVED_KEYS` list, which had
  drifted from `DERIVED_VARIABLES`; a key registered in one but not the other is
  silently absent from the user dictionary. The two lists are now aligned and the
  requirement to keep them in step is documented at both sites.

### Documentation

- The manual and README now state explicitly that this repository documents the
  **code only**. The appendix cataloguing known issues in the source data has been
  removed: it described Neotree study data rather than this software, and is
  maintained separately by the Neotree team.

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

### Packaging
- CRAN installer (`install_packages.r`) and UCL Data Safe Haven / Artifactory
  installer (`install_packages_dsh.r`).
- MIT licence, contribution guide, and `.gitignore` that excludes all
  patient-level data, run artifacts and credentials.

[v1.1.0]: https://github.com/neotree/neotree-cleaning-pipeline/releases/tag/v1.1.0
[v1.0.0]: https://github.com/neotree/neotree-cleaning-pipeline/releases/tag/v1.0.0
