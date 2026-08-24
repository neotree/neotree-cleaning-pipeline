# Changelog

All notable changes to the Neotree Cleaning Pipeline are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Repository releases are published as git tags / GitHub releases, starting at
v1.0.0. (The data dictionaries packaged in this release are versioned
separately by Neotree as "v8".)

## [v1.2.1] — 2026-08

Two silent data-completeness defects in the MWI PHC datasets, found via a
raw-vs-cleaned completeness audit after a data-quality report.

### Fixed

- **Module 09 dropped a numeric field's values when they were recorded with a
  coded or free-text variant of the same number** (e.g. a "number of visits"
  field recorded as `"4"` on some records and `"ANC4"` or `"4 visits"` on
  others, depending on how the form was completed). A plain `as.numeric()`
  coercion silently turned every non-bare-digit variant into `NA` -- about 70%
  of that field's captured values were lost this way. Module 09 now retries a
  failed numeric parse by extracting the first embedded digit run before
  giving up; this only recovers values that already failed to parse, so it
  cannot overwrite a value that parsed correctly, and applies pipeline-wide,
  not just to the field that surfaced it.

- **A raw data field named `Facility` was silently and completely discarded**
  when its standardised column name collided with the reserved system
  `facility` key column. Module 07's duplicate-column logic groups columns by
  name and always keeps whichever twin has more non-missing data; the
  always-populated system column won every time, so the genuine clinical
  field (name of the discharging/referral facility) never appeared in the
  cleaned output under any name, with no warning. Module 01 now renames any
  raw column listed in a new `cfg$reserved_column_renames` map (per dataset,
  set in `00_setup.r`) immediately after name standardisation, before Module
  07 can see the collision. The field is registered in the dictionary via
  `LEGACY_VARIABLES` (it was also absent from the web-editor export) so the
  fix survives a dictionary rebuild.

  **Anyone who has run the MWI `phc_admissions` or `phc_discharges` cleaning
  step on an earlier version should re-run it** -- both are read silently, not
  loud failures, so a prior run gives no indication anything was lost.

## [v1.2.0] — 2026-08

A defect in PII redaction was deleting three real patient records from Zimbabwe
discharge output on every run. Module 02's uid repair was extended and made
configurable, and its report now says how much evidence stands behind each
repair. The packaged data dictionaries are brought up to date with the internal
build for the first time since v1.0.0.

### Fixed

- **Module 00a redacted all-numeric UIDs, and Module 02 then deleted those
  patients.** The value-level PII scan applied every pattern to every remaining
  column, including the `uid` key column. `phone_international`
  (`^\+?[0-9]{7,15}$`) matches any 7–15 digit string, so three legitimate ZIM
  discharge UIDs consisting only of digits (`26530019`, `26530047`, `26530054`,
  all SMCH) were redacted to `NA`; Module 02 then removed those rows as
  empty-uid frame shifts. Three real patients disappeared from the cleaned
  output on every run, recorded only as `uid : 3 value(s)` in the audit report —
  indistinguishable from a genuine redaction. This was a data-availability
  failure, not a correctness one: no value was ever cleaned wrongly.

  Key and system columns (`uid`, `facility`, `uniquekey`, the system timestamps,
  `scriptversion`, `scriptid`) are now listed in `PII_VALUE_SCAN_EXEMPT` and are
  **exempt from redaction, not from detection** — they are still scanned, and any
  match is reported in a new audit-report section rather than acted on, so a real
  identifier leaking into a key column is surfaced rather than passed through
  silently. Counts only are reported, never the values.

  All 15 raw files in the 4 August 2026 extract were checked: `uid` in ZIM
  discharges is the only key/system column matched by any pattern in any dataset.
  **Anyone who has run an earlier version should re-run the pipeline before using
  ZIM discharge data — their output is three patient records short.**

### Added

- **Module 02 uid repair now handles a configurable set of separators.** A uid of
  the form `XXXX<sep>YYYY` is repaired to `XXXX-YYYY`. Previously only a comma was
  recognised; slash is now included, and the set is configuration rather than code
  (`UID_REPAIR_SEPARATORS` in `00_setup.r`, surfaced as
  `cfg$uid_repair_separators`), so recognising a further character is a one-line
  change. Space and backslash were checked across the ZIM and MWI admission and
  discharge files and occur zero times in any uid, so they are deliberately
  excluded.
- **Repairs are now reported as confirmed or unconfirmed.** A repair is
  `confirmed` when the corrected uid also exists in the paired
  admissions/discharges file for the same country, and `unconfirmed` when it does
  not — in which case the repair rests on the facility's uid naming pattern alone.
  `unchecked` means the paired file was unavailable and must never be read as a
  negative result. Unconfirmed repairs are still applied; the distinction is
  reported, not acted on.
- **Paired-file resolution in `00_setup.r`** (`cfg$paired_dataset`,
  `cfg$paired_csv_filepath`), mapping admissions ↔ discharges and
  phc_admissions ↔ phc_discharges. It resolves a path only; the file is read by
  Module 02 (two columns) and only when a repair needs confirming. Extracts are
  dumped per table and their date stamps often differ, so resolution prefers the
  same stamp and falls back to the most recent extract of the paired dataset for
  the same country and source.
- **Repairs that reveal a duplicate submission are flagged.** Where a repaired uid
  matches another row in the same file, the report marks it as a likely duplicate
  submission rather than a plain typo. Module 02 does not collapse it —
  deduplication remains Module 10's responsibility.

### Changed

- **Module 02's "non-standard UIDs retained" report section is split in two**:
  standard-length hyphen-less UIDs (8-character alphanumeric, a formatting variant
  of a well-formed uid) are now counted and listed separately from other
  non-standard UIDs (truncated or incomplete submissions with no recoverable
  structure). They are different problems and a single number hid the distinction.
- **Packaged data dictionaries updated to match the internal build.** The
  dictionaries shipped since v1.0.0 had fallen months behind, missing the
  `hivtestresult` and `lengthhaart` fixes and still carrying the pre-rename
  `signsdehydrations` key. All 37 files are now current. Dictionary content is
  schema only — variable names, labels, types, plausible ranges, value maps and
  PII column-name patterns — and carries no study data.

### Documentation

- Module 02 and Module 00a READMEs rewritten for the above, including why a
  broad value-level pattern is hazardous (it is applied to every non-exempt
  column, so a loose pattern silently deletes legitimate clinical values) and why
  the exemption list is not a way to retain a column that genuinely holds PII.
- `00_setup` README documents the new configuration and `cfg` fields; its
  "Output file flags" section is renamed and corrected, having claimed five
  boolean flags while listing seven, two of which are behaviour settings.
- Module 10 README records that a repaired uid can create a duplicate pair, that
  Stage 1 catches it, and that the completeness tie-break reaches no verdict when
  two records are equally complete.

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
