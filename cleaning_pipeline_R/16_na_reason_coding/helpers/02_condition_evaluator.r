# =============================================================================
# MODULE 16 -- HELPER 02: Neotree Condition Evaluator
# =============================================================================
# PURPOSE:
#   Evaluates Neotree screen/field condition strings against a patient's
#   recorded values to determine whether a field would have been shown to
#   the data collector.
#
# NEOTREE CONDITION SYNTAX:
#   Conditions are expressions using the following elements:
#
#   Variables   : $FieldKey  -- references a field value from earlier in the form
#   Equality    : $Key = 'value'  or  $Key = true  or  $Key = false
#   Inequality  : $Key != 'value'
#   Comparisons : $Key > N,  $Key < N,  $Key >= N  (numeric fields)
#   Logical     : expr and expr,  expr or expr
#   Negation    : !$Key = 'value'  (equivalent to $Key != 'value')
#   Grouping    : (expr)
#
#   String values are enclosed in single quotes: 'Y', 'STD', 'NND<24'
#   Booleans are bare: true, false
#   Numbers are bare: 37, 2.6, 1799.99
#
# EVALUATION STRATEGY:
#   The Neotree condition is translated to a valid R expression:
#     $Key        -> looked up in patient_values named list
#     = (not !=)  -> ==
#     'value'     -> "value"
#     true/false  -> TRUE/FALSE
#     and/or      -> &&/||
#     !$Key = 'v' -> !($Key == 'v')
#   The resulting R expression is evaluated with eval(parse(text=...)).
#
#   If evaluation fails (syntax error, missing variable, etc.) the function
#   returns NA, which is treated by the calling code as "cannot determine" and
#   the NA cell is conservatively coded -9 (unknown) rather than -7 (N/A).
#
# IMPORTANT LIMITATIONS:
#   - Field-to-field comparisons (e.g. $DateA > DateB) require both fields
#     to be present in patient_values; if either is missing the result is NA.
#   - Type coercion is attempted but may fail for edge cases; such cells
#     fall back to -9.
#   - Conditions referencing fields from a different script or form section
#     that was not collected may not evaluate correctly.
# =============================================================================

#' Translate a Neotree Condition String to an R Expression
#'
#' @param condition_str  Raw condition string from the Neotree JSON.
#' @return               Character string containing a valid R expression,
#'                       or NA if the input is empty.
translate_condition <- function(condition_str) {
  if (is.na(condition_str) || trimws(condition_str) == "") return(NA_character_)

  expr <- condition_str

  # -- Normalise whitespace and newlines ------------------------------------
  expr <- gsub("[\r\n\t]+", " ", expr)
  expr <- trimws(expr)

  # -- Handle prefix-negation:  !$Key = 'val'  ->  !(env[["key"]] == "val")
  # This must happen before the general $Key substitution
  expr <- gsub("!\\s*\\$(\\w+)", "!.(\\1)", expr, perl = TRUE)

  # -- Replace $Key with env lookups  ($Key -> .("key")) -------------------
  # Using a helper function call syntax so we can do case-insensitive lookup
  expr <- gsub("\\$(\\w+)", '.("\\L\\1")', expr, perl = TRUE)

  # -- Restore prefix negation placeholder  !.(  ->  !(. ----------------
  expr <- gsub("!\\.(", "!(.", expr, fixed = TRUE)

  # -- String literals: single quotes -> double quotes --------------------
  expr <- gsub("'([^']*)'", '"\\1"', expr, perl = TRUE)

  # -- Boolean literals ---------------------------------------------------
  expr <- gsub("\\btrue\\b",  "TRUE",  expr, perl = TRUE)
  expr <- gsub("\\bfalse\\b", "FALSE", expr, perl = TRUE)

  # -- Logical operators --------------------------------------------------
  expr <- gsub("\\band\\b", "&&", expr, perl = TRUE)
  expr <- gsub("\\bor\\b",  "||", expr, perl = TRUE)

  # -- Equality: lone = (not part of !=, <=, >=) -> ==  ------------------
  expr <- gsub("(?<![!<>])=(?!=)", "==", expr, perl = TRUE)

  expr
}

#' Evaluate a Neotree Condition Against a Patient's Recorded Values
#'
#' @param condition_str   Raw condition string from the Neotree JSON.
#' @param patient_values  Named list or named vector: field_key_lower -> value.
#'                        Keys should be lowercase, stripped of non-alphanumeric
#'                        characters (matching field_key_lower in script_conditions).
#' @return  TRUE  if the condition is satisfied (field was shown),
#'          FALSE if the condition is not satisfied (field was skipped -> -7),
#'          NA    if the condition cannot be evaluated (fall back to -9).
evaluate_condition <- function(condition_str, patient_values) {

  if (is.na(condition_str) || trimws(condition_str) == "") return(TRUE)

  r_expr <- translate_condition(condition_str)
  if (is.na(r_expr)) return(TRUE)

  # Build a lookup function used inside the translated expression
  # .(key) returns the patient's value for that key, or NA if not found
  lookup <- function(key) {
    val <- patient_values[[key]]
    if (is.null(val) || length(val) == 0) return(NA_character_)
    as.character(val[[1]])
  }

  # Wrap . as the lookup function in a local environment
  env <- new.env(parent = baseenv())
  env[["."]] <- lookup

  result <- tryCatch(
    eval(parse(text = r_expr), envir = env),
    error   = function(e) NA,
    warning = function(w) {
      suppressWarnings(
        tryCatch(eval(parse(text = r_expr), envir = env), error = function(e) NA)
      )
    }
  )

  if (length(result) == 0 || is.null(result)) return(NA)
  result <- result[[1]]
  if (is.na(result)) return(NA)
  isTRUE(result)
}

#' Vectorised Condition Evaluation for a Single Field Across Many Rows
#'
#' More efficient than calling evaluate_condition() row-by-row for a field
#' whose condition only involves a small number of other fields.
#'
#' @param condition_str   Raw condition string.
#' @param df_values       data.frame where column names are field_key_lower and
#'                        rows are patients.  Only columns referenced in the
#'                        condition need be present.
#' @return  Logical vector (length = nrow(df_values)).
#'          NA where evaluation fails.
evaluate_condition_vectorised <- function(condition_str, df_values) {
  vapply(
    seq_len(nrow(df_values)),
    function(i) {
      patient_vals <- as.list(df_values[i, , drop = FALSE])
      evaluate_condition(condition_str, patient_vals)
    },
    logical(1)
  )
}
