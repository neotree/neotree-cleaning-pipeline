# Module 00a: PII Detection and Removal

## Purpose

Loads the raw CSV, removes the columns that hold personally identifiable information (PII), blanks individual values that look like PII, and writes an audit report and a completion marker.

## When it runs

After Module 00 and before Module 01. It is the only module that reads the raw CSV in full.

## What it does

The file is read with every column as text. Column names are normalised first: surrounding whitespace is trimmed, spaces around dots are removed, all remaining whitespace and underscores are removed, and the name is converted to lower case. `Unique Key` and `unique_key` both become `uniquekey`.

Any completion marker left by an earlier run is deleted before the file is read.

### Tier 1: columns flagged in the dictionary

Every column named in `cfg$pii_columns` is removed. These are the value and label columns of the variables flagged `confidential` in the dictionary.

### Tier 2: columns matched by name

Every remaining column whose name matches a pattern in `PII_TIER2_PATTERNS` is removed. The list is the union of the patterns in the dictionary sheet `PII_Patterns` and the built-in defaults in `00_setup.r`. Matching ignores case. If the sheet cannot be read, only the built-in defaults apply and a warning is logged.

The built-in defaults cover these kinds of column:

| Kind | Columns matched |
|------|-----------------|
| Personal names | names ending in `name.value` |
| Telephone numbers | names ending in `cell.value` or `phone.value` |
| Addresses | names ending in `address.value` |
| Hospital numbers | names containing `hospnum` |
| Record identifiers | names containing `neotreeid`; names ending in `uidbid.value` or `uiddc.value` |
| Staff identifiers | names containing `hcwid` or `stuid`; names ending in `drid.value`; `firm` and `concall` (consultant on call), `hcwsigdis` (discharge signature), `dataentryname` and `dataentrynameother` (person entering the data), value and label |
| Mother's date of birth | `motherdob` and its variants, value and label; the yes/no field `motherdobyn` is kept |

### Quasi-identifiers

Columns whose names match one of the patterns below are listed in the audit report and kept in the data.

`village`, `district`, `province`, `address`, `matagedate` anywhere in the name; `tribe.value`, `ethnicity.value`, `religion.value` at the end of the name.

### Tier 3: values matched by pattern

Each value in the remaining columns is trimmed and tested against every pattern in `PII_VALUE_PATTERNS` (phone numbers, email addresses, a three-part number pattern, and the two national identity number shapes; see the Module 00 README). A matching value is set to `NA`.

### Exempt key and system columns

The columns in `PII_VALUE_SCAN_EXEMPT` are tested in the same way but never changed: `uid`, `facility`, `uniquekey`, `startedat`, `completedat`, `ingestedat`, `startedatdischarge`, `completedatdischarge`, `ingestedatdischarge`, `scriptversion`, `scriptid`. A match in one of them is logged as a warning and counted in the audit report.

### Completion marker and guard

After removal and redaction, the module builds a run id from the clock and the process id, calls `write_pii_marker()` to write `00a_pii_removal_complete.dcf` in the run folder, and attaches the run id to the data frame as the attribute `neotree_pii_run_id`. The marker describes the raw input file, whether or not the de-identified copy is saved.

The guard `assert_pii_removed()` in `00_setup.r` reads the marker back. Module 01 calls it with `check_run_id = TRUE` before using `df_raw`, and the modules that write row-level data call it before writing. It stops the run if the marker is missing or does not describe the current input and dictionary, or if a Tier 1 or Tier 2 column or a Tier 3 value is present.

### Audit report

The report holds column names and counts only; no cell values are written.

- Country, dataset, detected export style and source file.
- Number of columns removed by the dictionary flag and by name patterns, number flagged, number of values redacted, and number of columns remaining.
- The names of the removed columns, marked `[dict]` or `[pattern]`.
- The names of the quasi-identifier columns.
- For each column with redacted values, the number redacted.
- The exempt columns present and, for each one with matches, the pattern name and the number of matching values.

## Inputs

| Object / file | Description |
|---------------|-------------|
| Raw CSV at `cfg$csv_filepath` | Read with all columns as character |
| `cfg$pii_columns` | Column names for Tier 1 |
| `PII_TIER2_PATTERNS`, `PII_VALUE_PATTERNS`, `PII_VALUE_SCAN_EXEMPT` | Defined in `00_setup.r` |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df_raw`, `df_raw_deidentified` | De-identified data frame with normalised column names and the attributes `neotree_pii_n_removed`, `neotree_pii_n_redacted` and `neotree_pii_run_id` |
| `reports/00a_pii_audit_report.txt` | Audit report; not written when reports are suppressed |
| `00a_pii_removal_complete.dcf` | Completion marker, in the run folder |
| `<file stem>_deidentified.csv` | Written to the run folder only when `cfg$save_deidentified` is `TRUE`; `cfg$csv_filepath` is then set to this file |

## Functions

`clean_name_simple(name)` returns the normalised column name.

`remove_pii(df, pii_columns = character(0), report_filepath = NULL)` returns the de-identified data frame, with the number of columns removed and values redacted as attributes.

## Configuration

| Setting | Effect |
|---------|--------|
| `SAVE_DEIDENTIFIED` | `TRUE` writes the de-identified CSV. PII removal runs in either case. |
| `REPORT_DIR` | Location of the audit report; no report when reports are suppressed. |
