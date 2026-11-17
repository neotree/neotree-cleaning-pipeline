# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 05: Forward Fill Common Placeholder Values
# =============================================================================
# PURPOSE:
#   Recovers values that are present in a .label column while the paired
#   .value column is empty.
#
# METHOD:
#   1. Label-to-value rules (cfg$label_value_rules, set in 00_setup.r).  For
#      each configured field, the parser named in the rule reads the .value
#      and .label columns of the field and fills .value where it holds no
#      valid value and the label gives one.  A valid .value is never changed.
#      Parser "anc_visit_count" (antenatal care visits):
#        - a valid whole-number .value is kept;
#        - otherwise "N ANC visit(s)" or a plain number gives N, and "None"
#          gives 0;
#        - "More than 4 ANC visits" and "More than 8 ANC visits" give no
#          count (the row is marked raw_range_label for Module 15);
#        - any other label ("Not sure", "ANC visits", question text) gives
#          no count.
#      A .value that is not a valid count and has no label count is set to NA
#      and counted.  A conflict between a valid .value and a label count is
#      counted and the .value is kept.  The parser writes <field>_source, one of
#      raw_numeric_value, raw_exact_label, raw_range_label or unresolved.
#   2. For each .value/.label and .valuedischarge/.labeldischarge pair, a label
#      that is one of PLACEHOLDER_VALUES ("None", "Normal", "Norm", "True",
#      "False", "Yes", "No", "Y", "N" and case variants) is copied into the value
#      column where the value is NA.  Fields handled by step 1 are skipped.
#
# INPUTS:
#   df  - data.frame after Module 04
#
# OUTPUTS:
#   df      - data.frame with values recovered into .value columns, and the
#             <field>_source column of each rule
#   Report  - cfg$report_dir/05_forward_fill_placeholder_report.txt
#
# USAGE:
#   source("00_setup/00_setup.r")
#   source("05_forward_fill_placeholders/05_forward_fill_placeholders.r")
# =============================================================================

source("00_setup/00_setup.r")

PLACEHOLDER_VALUES <- c(
  "None", "Normal", "Norm",
  "none", "normal", "norm",
  "NONE", "NORMAL", "NORM",
  "True", "False", "TRUE", "FALSE",
  "Yes", "No", "YES", "NO", "Y", "N"
)

# -- Label-to-value parsers ----------------------------------------------------
# A parser takes the .value and .label vectors of one field and returns
#   count      numeric   the parsed value (NA where none)
#   from_label logical   TRUE where the count comes from the label
#   invalid    logical   TRUE where .value holds text that is not a valid count
#   source     character provenance, written to <field>_source
#   outcome    character class of each row, used in the report
#   conflict   logical   a valid .value and a label count that disagree

# Whole non-negative number or NA.
anc_count <- function(x) {
  n <- suppressWarnings(as.numeric(trimws(as.character(x))))
  n[!is.finite(n) | n < 0 | n != floor(n)] <- NA_real_
  n
}

parse_anc_visit_count <- function(value, label) {
  value_count <- anc_count(value)
  label <- trimws(as.character(label))
  label[is.na(label)] <- ""
  lower <- tolower(label)

  label_count <- rep(NA_real_, length(label))
  label_count[lower == "none"] <- 0
  exact <- grepl("^[0-9]+[[:space:]]+anc[[:space:]]+visits?$", lower)
  label_count[exact] <- as.numeric(sub("[[:space:]].*$", "", lower[exact]))
  numeric_label <- grepl("^[0-9]+([.]0+)?$", lower)
  label_count[numeric_label] <- anc_count(lower[numeric_label])
  range_label <- grepl("^more than (4|8)[[:space:]]+anc[[:space:]]+visits$", lower)

  value_blank <- is.na(value) | trimws(as.character(value)) == ""
  invalid     <- !value_blank & is.na(value_count)

  count      <- value_count
  from_label <- is.na(count) & !is.na(label_count)
  count[from_label] <- label_count[from_label]

  source <- ifelse(!is.na(value_count), "raw_numeric_value",
            ifelse(from_label, "raw_exact_label",
            ifelse(range_label, "raw_range_label", "unresolved")))
  outcome <- ifelse(!is.na(value_count), "valid_value",
             ifelse(from_label & lower == "none", "label_none_as_zero",
             ifelse(from_label, "label_exact_count",
             ifelse(range_label, "label_more_than_n",
             ifelse(lower == "not sure", "unresolved_not_sure",
             ifelse(lower == "anc visits", "unresolved_no_number",
             ifelse(grepl("[?]$", lower), "unresolved_question_text",
             ifelse(lower == "", "unresolved_no_answer",
                    "unresolved_other"))))))))
  list(count      = count,
       from_label = from_label,
       invalid    = invalid,
       source     = source,
       outcome    = outcome,
       conflict   = !is.na(value_count) & !is.na(label_count) &
                    value_count != label_count)
}

LABEL_PARSERS <- list(anc_visit_count = parse_anc_visit_count)

#' Apply the Label-to-Value Rules
#'
#' @param df    A data.frame.
#' @param rules Named character vector, field -> parser name (or NULL).
#' @return      List: df, value_cols (value columns handled), report (lines).
apply_label_value_rules <- function(df, rules) {
  out <- list(df = df, value_cols = character(0), report = character(0))
  if (is.null(rules) || length(rules) == 0) return(out)

  for (field in names(rules)) {
    parser <- LABEL_PARSERS[[rules[[field]]]]
    if (is.null(parser))
      stop(sprintf("Unknown label-to-value parser '%s' for field '%s'.",
                   rules[[field]], field))
    vc <- paste0(field, ".value")
    lc <- paste0(field, ".label")
    if (!vc %in% names(df)) {
      log_warn("label-to-value rule skipped: column '%s' not found.", vc)
      next
    }
    label <- if (lc %in% names(df)) df[[lc]] else rep(NA_character_, nrow(df))
    res   <- parser(df[[vc]], label)

    df[[vc]][res$from_label] <- as.character(res$count[res$from_label])
    n_invalid <- sum(res$invalid & !res$from_label)
    df[[vc]][res$invalid & !res$from_label] <- NA_character_
    df[[paste0(field, "_source")]] <- res$source

    n_conflict <- sum(res$conflict)
    if (n_conflict > 0)
      log_warn("label-to-value rule '%s': %d row(s) where the value and the label count disagree; the value was kept.",
               field, n_conflict)
    log_info("  label-to-value rule '%s': %d value(s) filled from '%s'.",
             field, sum(res$from_label), lc)

    counts <- table(factor(res$outcome))
    out$report <- c(out$report,
      sprintf("Field %s (parser %s), %d row(s):", field, rules[[field]], nrow(df)),
      sprintf("  %-34s : %d", names(counts), as.integer(counts)),
      sprintf("  %-34s : %d", "value and label disagree", n_conflict),
      sprintf("  %-34s : %d", "invalid value set to missing", n_invalid),
      "")
    out$value_cols <- c(out$value_cols, vc)
  }
  out$df <- df
  out
}

#' Forward Fill Placeholder Values from .label into .value
#'
#' @param df              A data.frame.
#' @param placeholders    Character vector of valid fill candidates.
#' @param report_filepath Optional path for a text report.
#' @param skip_value_cols Value columns handled by a label-to-value rule.
#' @param rule_report     Report lines from apply_label_value_rules().
#' @return                Updated data.frame with recovered placeholder values.
forward_fill_placeholders <- function(df,
                                      placeholders    = PLACEHOLDER_VALUES,
                                      report_filepath = NULL,
                                      skip_value_cols = character(0),
                                      rule_report     = character(0)) {

  fill_count_total <- 0L
  fill_log         <- character(0)
  col_names        <- names(df)

  process_pair <- function(vc, lc) {
    if (vc %in% skip_value_cols) return(0L)
    if (!lc %in% col_names) return(0L)
    mask   <- is.na(df[[vc]]) & !is.na(df[[lc]]) & (df[[lc]] %in% placeholders)
    n_fill <- sum(mask)
    if (n_fill > 0) {
      df[[vc]][mask] <<- df[[lc]][mask]
      fill_log <<- c(fill_log,
        sprintf("  %-45s <- %-45s : %d value(s) recovered", vc, lc, n_fill))
      log_info("  forward_fill_placeholders: %d values in '%s' recovered from '%s'.",
               n_fill, vc, lc)
    }
    return(n_fill)
  }

  # .value / .label pairs
  for (vc in col_names[grepl("\\.value$", col_names)]) {
    lc <- sub("\\.value$", ".label", vc)
    fill_count_total <- fill_count_total + process_pair(vc, lc)
  }

  # .valuedischarge / .labeldischarge pairs
  for (vc in col_names[grepl("\\.valuedischarge$", col_names)]) {
    lc <- sub("\\.valuedischarge$", ".labeldischarge", vc)
    fill_count_total <- fill_count_total + process_pair(vc, lc)
  }

  log_info("forward_fill_placeholders: %d total placeholder values recovered.",
           fill_count_total)

  if (!is.null(report_filepath) && nzchar(report_filepath)) {
    tryCatch({
      lines <- c(
        "Module 05 - Forward Fill Placeholder Values Report",
        "===================================================",
        sprintf("Run timestamp               : %s",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        sprintf("Country                     : %s", toupper(cfg$country)),
        sprintf("Dataset                     : %s", cfg$dataset),
        "",
        sprintf("Placeholder tokens checked  : %d", length(placeholders)),
        sprintf("Total values recovered      : %d", fill_count_total),
        ""
      )
      if (length(rule_report) > 0) {
        lines <- c(lines, "=== Label-to-Value Rules ===", rule_report)
      }
      if (length(fill_log) > 0) {
        lines <- c(lines, "=== Per-Column Fill Summary ===", fill_log)
      } else {
        lines <- c(lines, "No placeholder values needed recovery.")
      }
      writeLines(lines, report_filepath)
    }, error = function(e) log_warn("Could not write Module 05 report: %s", e$message))
  }

  return(df)
}

# -- Run -----------------------------------------------------------------------
report_path <- if (!is.null(cfg$report_dir))
  file.path(cfg$report_dir, "05_forward_fill_placeholder_report.txt") else NULL

rule_result <- apply_label_value_rules(df, cfg$label_value_rules)
df <- forward_fill_placeholders(
  rule_result$df,
  report_filepath = report_path,
  skip_value_cols = rule_result$value_cols,
  rule_report     = rule_result$report
)
log_info("Module 05 complete. Dimensions: %d rows x %d cols.", nrow(df), ncol(df))
