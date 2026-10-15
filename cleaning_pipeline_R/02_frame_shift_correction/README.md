# Module 02: Frame Shift Correction

## Purpose

Repairs `uid` values in which another character was typed in place of the hyphen, and removes rows whose `uid` is empty.

## When it runs

After Module 01.

## What it does

If the data frame has no `uid` column, it is returned unchanged. Otherwise the `uid` values are trimmed and handled in this order.

### 1. Repair of separators

A `uid` made of 3 to 6 letters or digits, one of the characters in `cfg$uid_repair_separators`, and then one or more letters or digits is repaired by replacing that character with a hyphen. With the default separators, `XXXX,0001` and `XXXX/0001` both become `XXXX-0001`.

### 2. Removal of empty UIDs

A row is removed when its `uid` is `NA`, empty, or one of `na`, `null`, `nan`, `none`, `n/a`, `<na>` in any case. No other row is removed.

### 3. Confirmation of repairs

When at least one `uid` was repaired, the `uid` and `facility` columns of the paired admissions or discharges file (`cfg$paired_csv_filepath`) are read, and each repair is given a status. The repair is applied whatever the status.

| Status | Meaning |
|--------|---------|
| `confirmed` | The repaired `uid` is in the paired file with the same facility. |
| `confirmed (other facility)` | The repaired `uid` is in the paired file with a different facility. |
| `unconfirmed` | The repaired `uid` is not in the paired file. |
| `unchecked` | There is no paired file, or it could not be read, or it lacks a `uid` or `facility` column. |

A repair is also marked when the repaired `uid` and facility already occur on another row of the same file that was not repaired. The rows are left as they are.

### 4. UIDs without a hyphen

Rows whose `uid` has no hyphen are kept and reported in two groups.

| Group | Rule | Example |
|-------|------|---------|
| Standard length | Exactly 8 letters or digits | `XXXX0001` |
| Other | Any other value without a hyphen | `XX01` |

## Inputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame from Module 01 |
| `cfg$uid_repair_separators` | Characters treated as a mistyped hyphen |
| `cfg$paired_csv_filepath` | Paired raw CSV, or `NULL`. Only its `uid` and `facility` columns are read, and only when a repair was made. |

## Outputs

| Object / file | Description |
|---------------|-------------|
| `df` | Data frame with repaired `uid` values and without the empty-`uid` rows |
| `reports/02_frame_shift_report.txt` | Separator set and paired file used; rows on entry, repaired, removed and remaining; number of repairs by status; one line per distinct repair with the original and repaired `uid`, facility, separator, number of rows and status; the `uid` values of the removed rows; the UIDs without a hyphen, by group. |
| `reports/02_frame_shift_dirty_rows.csv` | The removed rows. Written only when at least one row is removed, after `assert_pii_removed()` has checked them. |

## Functions

`remove_frame_shift(df, separators = NULL, paired_csv_filepath = NULL, report_filepath = NULL, csv_filepath = NULL)` returns the corrected data frame. When `separators` is `NULL`, `cfg$uid_repair_separators` is used, or comma and slash if `cfg` is not available.

`.uid_separator_class(seps)` returns a regular-expression character class built from the separator characters, or `NULL` if there are none, in which case no `uid` is repaired.

`.read_paired_uids(paired_path)` returns a data frame of the trimmed `uid` and `facility` columns of the paired file, or `NULL` if the file is unavailable.

## Configuration

| Setting | Effect |
|---------|--------|
| `UID_REPAIR_SEPARATORS` | The characters repaired to a hyphen. Adding a character to the vector makes the module repair it. |
