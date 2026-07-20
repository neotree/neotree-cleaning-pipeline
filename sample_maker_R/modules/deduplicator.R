################################################################################
# Neotree Sample Maker -- Module 01: Join Admissions & Discharges
# FILE:    modules/deduplicator.R
# PURPOSE: Detect and resolve duplicate uid+facility matching keys in admissions
#          and discharges data frames.
#
# STRATEGY
#   When a uid+facility key appears more than once in a file, keep the row with
#   the fewest NA values (i.e. the most complete record).  All duplicate groups
#   are logged to a DUPLICATES_LOG CSV for manual review.
#
#   Possible genuine readmissions (same uid+facility, different admission
#   datetimes) are flagged in the log with possible_readmission = TRUE.  These
#   are not excluded automatically -- the clinician should review the log.
#
# FUNCTION EXPORTED
#   resolve_duplicates(df, label)
#     -> returns list(df, log, n_dup_keys, n_removed)
################################################################################

resolve_duplicates <- function(df, label) {

  dup_keys <- unique(df$match_key[duplicated(df$match_key)])

  if (length(dup_keys) == 0) {
    cat(sprintf("[dedup]   %s: no duplicate keys found\n", label))
    return(list(
      df          = df,
      log         = data.frame(),
      n_dup_keys  = 0L,
      n_removed   = 0L
    ))
  }

  cat(sprintf(
    "[dedup]   WARNING: %d duplicate uid+facility key(s) in %s -- resolving...\n",
    length(dup_keys), label
  ))

  log_rows       <- list()
  rows_to_remove <- integer(0)

  for (key in dup_keys) {
    idx       <- which(df$match_key == key)
    na_counts <- vapply(idx, function(i) sum(is.na(df[i, ])), integer(1))
    keep      <- idx[which.min(na_counts)]
    remove    <- setdiff(idx, keep)

    # Flag if more than one row has a non-NA admission datetime
    # (possible genuine readmission rather than data-entry duplicate)
    if ("datetimeadmission" %in% names(df)) {
      adm_dates          <- df$datetimeadmission[idx]
      genuine_readmission <- sum(!is.na(adm_dates) & nchar(trimws(as.character(adm_dates))) > 0) > 1
    } else {
      genuine_readmission <- FALSE
    }

    if (genuine_readmission) {
      cat(sprintf(
        "[dedup]     *** POSSIBLE READMISSION: %s (%d rows with non-NA admission datetime -- review manually)\n",
        key, sum(!is.na(df$datetimeadmission[idx]))
      ))
    }

    for (r in idx) {
      log_rows[[length(log_rows) + 1]] <- data.frame(
        source               = label,
        match_key            = key,
        row_index_in_file    = r,
        na_count             = na_counts[which(idx == r)],
        action               = ifelse(r == keep, "KEPT", "REMOVED"),
        possible_readmission = genuine_readmission,
        stringsAsFactors     = FALSE
      )
    }

    rows_to_remove <- c(rows_to_remove, remove)
  }

  if (length(rows_to_remove) > 0) {
    df <- df[-rows_to_remove, ]
  }

  log_df <- do.call(rbind, log_rows)

  cat(sprintf(
    "[dedup]   %s: %d duplicate key(s) resolved -- %d row(s) removed\n",
    label, length(dup_keys), length(rows_to_remove)
  ))

  list(
    df         = df,
    log        = log_df,
    n_dup_keys = length(dup_keys),
    n_removed  = length(rows_to_remove)
  )
}
