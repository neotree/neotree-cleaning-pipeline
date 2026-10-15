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
| `reports/10_duplicate_row_removal_report.txt` | Rows before and after, rows removed at each stage, retention rate, the visit-date columns used, whether Stage 2 ran and, when it did not, the number of rows sharing `uid`, `facility` and `uniquekey`. Counts and column names only. |

## Function

`remove_duplicate_rows(df, skip_stage2 = FALSE, report_filepath = NULL)` returns the deduplicated data frame.

## Configuration

| Setting | Effect |
|---------|--------|
| `SKIP_DEDUP_STAGE2` (`cfg$skip_dedup_stage2`) | `TRUE` skips Stage 2. Unless set by the user, it is `TRUE` for the `infections` and `neolab` datasets, which hold several rows per patient, and `FALSE` for all others. |
| `SAVE_STAGE1_CHECKPOINT` (`cfg$save_stage1_checkpoint`) | `TRUE` writes the checkpoint RDS. Default `FALSE`. |
