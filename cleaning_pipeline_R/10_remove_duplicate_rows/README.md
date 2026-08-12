# Module 10: Remove Duplicate Rows

## Purpose
Applies two-stage deduplication after first-stage cleaning. Stage 2 (patient-level) can be disabled for longitudinal datasets where multiple rows per patient are by design. Optionally saves a stage-1 checkpoint RDS (controlled by `SAVE_STAGE1_CHECKPOINT`, default `FALSE`) so the pipeline can resume from this point without re-running Modules 01-09.

---

## When It Runs
After Module 09 (data type assignment). This is the last step of first-stage cleaning. Modules 11-14 (validation) all read from the data frame produced here.

---

## Logic

Deduplication is applied in two stages:

**Stage 1 - Visit-level deduplication:** Records are grouped by `uid`, `facility`, and any visit-date columns present (`startedat`, `startedatdischarge`, `datetimeadmission.value`, `dateadmission.value`, `datebct.value`, `completedat`, `completedatdischarge`). Within each group, the record with the fewest missing values across non-key columns is retained (most-complete record per unique visit). When two records in the same group are equally complete (tied NA count), a pre-sort ensures the row with an **alphanumeric** `uniquekey` is preferred over a **timestamp-format** key (e.g. `2020-12-20T12:41:39.867Z`). Alphanumeric UUIDs are the canonical Neotree identifiers; timestamp keys are a legacy fallback used in older app versions and batch re-imports, and should not take precedence when clinical content is identical.

**Stage 2 - Patient-level deduplication:** Among the records that survive Stage 1 (potentially spanning different visit dates for the same patient), the single most complete record per `(uid, facility)` pair is kept -- the one with the fewest missing values across all non-key columns. Tie-break: if two records are equally complete, the one with the latest `uniquekey` value is kept (most recent submission).

**Stage 2 skip (longitudinal datasets):** Stage 2 is automatically disabled when `cfg$skip_dedup_stage2 = TRUE`. This is set automatically by `00_setup.r` for `infections` and `neolab` datasets, where multiple rows per patient are by design:

- `infections` (ZIM): NeoInfect serial review form -- one row per clinical review visit. Collapsing to one row per patient would discard all but the last review record, losing the longitudinal trajectory of infection management.
- `neolab` (ZIM, MWI): NeoLab blood culture form -- one row per culture event. A patient can have multiple cultures taken on different days with different organisms and results.

Stage 1 still runs for these datasets to handle true same-visit duplicates (connection-drop retransmissions that share identical visit timestamps).

**Rationale for this strategy:** The Neotree app occasionally loses its connection mid-transmission and sends an incomplete record to the database. It then retransmits the full record, which may carry a new timestamp. The retransmitted copy is the authoritative record. Keeping the earliest record would systematically retain the truncated version; keeping the most complete record ensures the correct, fully-transmitted copy is used. This was confirmed by observing that systematic `neotreeoutcome` discrepancies between the R and Python pipelines were caused by R retaining the older (incomplete) record while Python retained the more complete one.

After deduplication, a stage-1 checkpoint is optionally saved as an RDS file in the run's output subfolder (controlled by `SAVE_STAGE1_CHECKPOINT`, default `FALSE`).

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 09 with correctly typed columns |

---

## Outputs

| Object / File | Default | Description |
|---------------|---------|-------------|
| `df` | always | Deduplicated data frame -- end of first-stage cleaning |
| `output/<file_stem>/<file_stem>_cleaned_stage1.rds` | **off** | R binary checkpoint. Controlled by `SAVE_STAGE1_CHECKPOINT` (default `FALSE`). |
| `output/<file_stem>/reports/10_duplicate_row_removal_report.txt` | always | Row counts per stage, retention rate |

---

## Key Function

**`remove_duplicate_rows(df, skip_stage2 = FALSE, report_filepath = NULL)`**

- Stage 1: groups by `uid + facility + visit_date_cols`, uses `dplyr::slice_min()` on missing-value count.
- Stage 2: pre-sorts by `uniquekey` descending (latest first), then uses `dplyr::slice_min()` on missing-value count to keep the most complete record per `(uid, facility)`. Skipped entirely when `skip_stage2 = TRUE`.
- Returns the cleaned data frame.

After the function returns, the module saves the stage-1 checkpoint RDS if `cfg$save_stage1_checkpoint` is `TRUE`; otherwise it logs a skip message and continues.

---

## Notes

- Deduplication here uses both visit-level and patient-level keys. A final value-level deduplication on the merged output is also applied in Module 15.
- The stage-1 checkpoint (`*_cleaned_stage1.rds`) is saved into the run's output subfolder (`output/<file_stem>/`) when `SAVE_STAGE1_CHECKPOINT = TRUE`. Set this flag in `00_setup.r` or inject it from `run_all.r` to enable it for specific runs.
- If the checkpoint cannot be saved (e.g. write permission error), a warning is logged and the pipeline continues.
- The Stage 2 strategy was changed from "keep earliest visit date" to "keep most complete record" following the discovery that systematic `neotreeoutcome` discrepancies between the R and Python pipelines were caused by R retaining the original truncated transmission while Python retained the fully-transmitted retransmission. See `REPORTS/neotreeoutcome_discrepancy_root_cause_analysis.md` for full analysis.
- **UIDs repaired by Module 02 can create a duplicate pair here.** When Module 02 repairs a mistyped-hyphen uid (e.g. `"F55F/0700"` -> `"F55F-0700"`) and the hyphenated form already exists in the same file, the two rows stop looking like two patients and become a duplicate pair for this module to collapse. Stage 1 does catch it -- verified on the 4 August 2026 MWI discharges extract, where the pair shares `facility`, `unique_key`, and has all four applicable visit-date columns NA on both rows, so the Stage 1 group keys agree once the uid matches. Because it is caught at Stage 1, this also holds for datasets running with `skip_dedup_stage2 = TRUE`. Module 02's report flags such a repair as `[also present in this file -- likely duplicate submission]`.
- **The tie-break has no verdict when completeness ties.** In the MWI case above both rows carry exactly 50 non-NA fields but differ in 9 of them (`DischHR`, `DischSats`, `DischWeight`, `DateTimeDischarge`, ...). The Stage 1 rationale below -- prefer the retransmission because it is more complete -- does not discriminate here, so `slice_min(with_ties = FALSE)` keeps whichever row comes first in frame order, which is the **earlier-ingested** copy. That is the opposite of the "retransmission is authoritative" principle, arrived at by default rather than by decision. Unresolved; raised 2026-08-12.
- **Open clinical question:** The "most complete record" tie-breaking rule has not been validated against clinical notes or medical records. This strategy affects 79 outcome classifications in ZIM discharges and 87 in MWI discharges, including DC<->NND reclassifications. Clinicians should review the affected pairs before using discharge outcome data for analysis or publication. See `REPORTS/Neotree_Master_Dataset_Protocol_v2.docx`, Section 9.5 for full context and scale.
