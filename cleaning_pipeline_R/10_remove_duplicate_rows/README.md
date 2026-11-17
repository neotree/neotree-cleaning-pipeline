# Module 10: Remove Duplicate Rows

## Purpose

Removes duplicate rows in two stages, keeping the most complete record each time, and optionally saves a checkpoint of the result.

## When it runs

After Module 09. Modules 11 to 14 each read the data frame produced here.

## What it does

### Stage 1: one row per visit

Rows are grouped by `uid`, `facility` and whichever of these visit-date columns are present: `startedat`, `startedatdischarge`, `datetimeadmission.value`, `dateadmission.value`, `datebct.value`, `completedat`, `completedatdischarge`.

Within each group the row with the fewest missing values in the remaining columns is kept. When rows are equally complete, a row whose `uniquekey` is not in timestamp form (`YYYY-MM-DDT...`) is kept ahead of one whose `uniquekey` is; otherwise the first row in the data frame is kept.

### Stage 2: one row per patient

Rows are grouped by `uid` and `facility`. Within each group the row with the fewest missing values in all other columns is kept. When rows are equally complete, the row with the highest `uniquekey` (text order) is kept.

Stage 2 is skipped when `skip_stage2` is `TRUE`. Stage 1 still runs.

When Stage 2 is skipped, the module counts the rows that share `uid`, `facility` and `uniquekey` with another row. Modules 11 to 15 keep one row per such key, so these rows would be merged. The count is written to the report, and a warning is logged when it is above zero or when there is no `uniquekey` column.

### Stage 2, episode mode (admissions and discharges, main and PHC; maternal files)

When `DEDUP_MODE` is `"episode"` (the default), admissions and discharges (`admissions` and `discharges`, and the PHC files `phc_admissions` and `phc_discharges`) use episode mode instead of Stages 1 and 2 (`episode_ids.r`). Stage 1 is not applied, because rows with identical visit dates can belong to different babies.

1. **Same event.** Rows sharing `uid` and `facility` are collapsed only when their event times are within 1 hour, sex, birth weight (more than 100 g apart) and gestation (more than 1 week apart) do not disagree, and their readmission flags do not differ. A row joins a collapsed record only when it meets these conditions against every row already in it. The event time is the admission date-time (else the form start time) for admissions, and the form start time (else the discharge date-time) for discharges. The most complete row is kept.
2. **Baby.** Admission records sharing a `uid` are taken in date order; each joins the first baby under that `uid` it belongs to: identity differs means another baby; a readmission flag, or the same `uid` at another facility with two or more identity fields agreeing, means the same baby; otherwise Apgar at 5 minutes, mode of delivery, birth facility and maternal age decide (`probable`); with nothing to compare the record gets its own letter (`unresolved`).
3. **Stay.** The admission records of one baby are numbered 1, 2, 3 in date order.
4. **Discharges** take the baby and stay of the admission they fit under the same `uid` and `facility`: first the admission date-time carried on the discharge (within 1 hour, or exactly 2 hours), then the identity fields (two or more disagreeing means no fit), then the order of dates. If two admissions fit equally, the earlier is used (`ambiguous_link`). A discharge that fits no admission gets a stay of its own (`no_admission`). All discharge forms of one stay are kept; the form started last is marked `stay_form_primary`.

**Maternal files (births).** For Zimbabwe `maternal_outcomes` and Malawi `combined_maternity_outcomes`, one row is one baby at birth and `uid` is the baby's Neotree ID. Rows are collapsed by the rule in step 1, with birth outcome (live birth, stillbirth, miscarriage) and birth order (`typebirth`: Tw1, Tw2, Tr1 ...) added to the baby details and the maternal admission date-time as the clock. A birth happens once, so every record left is a baby of its own and gets its own letter under its `uid`; there is no `stay_no` and no key file. A record within 24 hours of an earlier one under the same `uid` is flagged `same_day_pair` when the baby details differ and `unresolved` when nothing differs; a later record in which nothing differs is also `unresolved`. The Malawi component files (`maternal_outcomes`, `dhis2_maternal_outcomes`, `maternity_completeness`) keep the current rule.

Columns added: `baby_id` (`uid`, a full stop and a letter), `stay_no`, `dedup_rows_merged`, `dedup_basis`, `dedup_flag` (`none`, or one or more of `unresolved`, `probable`, `ambiguous_link`, `link_doubt`, `no_admission`, `outcome_conflict`, `same_day_pair`, `collapsed_no_identity` (rows collapsed although no identity field could be compared), `no_uid`, separated by `;`), and on discharges `stay_form_primary`. The maternal files get the same columns without `stay_no`. The original `uid` is not changed. Rows without a `uid` are kept with `dedup_flag` `no_uid`.

The admissions run writes `<file_stem>_episode_keys.rds` to its output folder, with the name and md5 checksum of its input file and md5 checksums of every `.r` file in `00_setup`, `00_build_dictionary`, `00a_pii_detection_removal` and Modules 01 to 10, of every `.xlsx` file directly in `dictionaries/`, and of the dictionary file the admissions run read (its path, and its checksum taken when the setup read it; the key file is not written if the dictionary has changed since), and the rule's settings. The discharges run reads the key file of the paired admissions file and stops if it is missing or if any of these differ, so admissions must run first, and again after any change to that code or to the dictionaries. An admissions run in current mode removes an old key file.

In episode mode `uid` + `facility` is not unique, so Modules 11, 12, 14 and 15 keep one row per `uid` + `facility` + `uniquekey`, and Module 16 matches clean to raw rows on the same key. The run stops if two kept rows share `uid`, `facility` and `uniquekey`.

### Checkpoint

When `cfg$save_stage1_checkpoint` is `TRUE`, the deduplicated data frame is checked by `assert_pii_removed()` (`00_setup.r`) and then saved as an RDS file. A failed check stops the run. A failure to write the file is logged as a warning and the run continues.

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 09 |
| `cfg` | Configuration list; see *Configuration* |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Deduplicated data frame |
| `<file_stem>_cleaned_stage1.rds` | Checkpoint, written beside the cleaned RDS output. Only when `SAVE_STAGE1_CHECKPOINT` is `TRUE`. |
| `reports/10_duplicate_row_removal_report.txt` | Rows before and after, rows removed at each stage, retention rate, the visit-date columns used, whether Stage 2 ran and, when it did not, the number of rows sharing `uid`, `facility` and `uniquekey`. In episode mode also babies, stays, and rows by basis and by flag. Counts and column names only. |
| `<file_stem>_episode_keys.rds` | Admissions in episode mode only: the admission records with their baby and stay, read by the discharges run. Holds `uid` values. |

## Function

`remove_duplicate_rows(df, skip_stage2 = FALSE, report_filepath = NULL, episode_dataset = NULL, adm_keys = NULL)` returns the deduplicated data frame. `episode_dataset` (`"admissions"` or `"discharges"`) turns on episode mode; `adm_keys` is the admissions key table for discharges.

## Configuration

| Setting | Effect |
|---------|--------|
| `SKIP_DEDUP_STAGE2` (`cfg$skip_dedup_stage2`) | `TRUE` skips Stage 2. Unless set by the user, it is `TRUE` for the `infections` and `neolab` datasets, which hold several rows per patient, and `FALSE` for all others. |
| `DEDUP_MODE` (`cfg$dedup_mode`) | `"episode"` (default) or `"current"`. Episode mode applies to the main and PHC admissions and discharges, Zimbabwe `maternal_outcomes` and Malawi `combined_maternity_outcomes`; `cfg$dedup_episode` is `TRUE` when it applies to the current run. In `run_all.r`, set `RUN_ALL_DEDUP_MODE`. |
| `SAVE_STAGE1_CHECKPOINT` (`cfg$save_stage1_checkpoint`) | `TRUE` writes the checkpoint RDS. Default `FALSE`. |
