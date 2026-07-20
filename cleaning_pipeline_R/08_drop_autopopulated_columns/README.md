# Module 08: Drop Auto-Populated Columns

## Purpose

This module is a deliberate **no-op**: the data frame passes through unchanged and all DC-suffix columns are preserved alongside their admission-form counterparts.

---

## Background -- Why the Module No Longer Drops

DC-suffix columns (e.g. `apgar1dc`, `gestationdc`, `hivtestresultdc`, `modedeliverydc`, `bwdc`, `dateadmissiondc`) were previously assumed to be auto-populated copies of admission variables carried across by the Neotree app for reference. Investigation of the MWI discharge data showed this assumption is incorrect:

- **DC columns are exclusive to discharge files.** They do not appear in admissions raw data.
- **There is zero row overlap** between every DC column and its admission counterpart -- no single record has both filled in simultaneously. They capture data from different form sections completed at different clinical moments.
- **They represent independent discharge-form entries** -- values recorded (or re-assessed) by the clinician at the time of discharge, not auto-filled copies.
- **Dropping them causes real data loss.** In MWI discharges, `hivtestresultdc` is the primary HIV test result source (16,109 non-null values vs 112 for `hivtestresult`). The other DC columns together cover thousands of additional records.

The correct interpretation of a DC-suffix column is: *this variable measured at discharge*, as opposed to the same variable measured at admission. Both columns are clinically meaningful and should be retained independently.

---

## Behaviour

The data frame is returned unchanged. A report file is written to record the decision.

---

## When It Runs

After Module 07 (label column drop), before Module 09 (data type assignment).

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 07 |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame unchanged -- all DC columns preserved |
| `reports/08_autopopulated_columns_report.txt` | Audit record noting zero columns dropped |

---

## Impact by Dataset

| Dataset | DC columns retained | Key note |
|---------|-------------------|----------|
| MWI DB discharges | 8 | `hivtestresultdc` is the primary HIV source (16,109 records) |
| MWI MB discharges | 8 | Same columns, same data |
| ZIM DB discharges | 1 (`dateadmissiondc`) | Column is empty -- no data loss either way |
| ZIM MB discharges | 1 (`dateadmissiondc`) | Same |
| All admissions | 0 | DC columns do not exist in admission files |

---

## Comparison with the Python Pipeline

The Python `drop_unwanted_columns` function groups columns by prefix and keeps one representative per group. Because `Apgar1DC` and `Apgar1` have different prefixes, Python has always retained both independently -- not by design, but because it has no DC-dropping logic. The R pipeline now matches this behaviour intentionally and for documented clinical reasons.
