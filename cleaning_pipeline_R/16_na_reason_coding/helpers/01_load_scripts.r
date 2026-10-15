# =============================================================================
# MODULE 16 -- HELPER 01: Load and Parse Neotree Script JSON Files
# =============================================================================
# PURPOSE:
#   Reads all Neotree script JSON files from the neotree_scripts directory and
#   builds a flat lookup table of (script_id, field_key, effective_condition).
#
#   The "effective condition" for a field is the combination of the screen-level
#   condition and the field-level condition.  Both must be TRUE for the field to
#   have been shown to the data collector.  If either is FALSE, the field was
#   skipped and any resulting NA should be coded -7 (not applicable).
#
#   CONDITION PRECEDENCE:
#     screen_condition takes priority -- if it is FALSE the field is never shown
#     regardless of field_condition.  The effective condition stored here is
#     therefore: screen_condition AND field_condition (where both are non-empty).
#
# OUTPUT:
#   script_conditions  -- data.frame with columns:
#     script_id        : UUID of the script
#     script_title     : Human-readable script name
#     field_key        : Field key as it appears in the script (original case)
#     field_key_lower  : Lowercase field key (for case-insensitive matching)
#     screen_condition : Raw condition string for the screen (may be "")
#     field_condition  : Raw condition string for the field (may be "")
#     effective_condition : Combined condition string used for evaluation
#
#   script_index -- data.frame with one row per script:
#     script_id, script_title, country, file_path
# =============================================================================

#' Parse a Single Neotree Script JSON File
#'
#' @param json_path  Absolute path to the metadata.json file.
#' @param country    "ZIM" or "MWI".
#' @return           List with $conditions (data.frame) and $meta (named list).
parse_script_json <- function(json_path, country) {

  raw   <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)
  script <- if (is.list(raw) && !is.null(raw$scriptId)) raw else raw[[1]]

  script_id    <- script$scriptId   %||% ""
  script_title <- script$title      %||% ""
  screens      <- script$screens    %||% list()

  rows <- list()

  for (screen in screens) {
    screen_cond  <- trimws(screen$condition %||% "")
    screen_title <- trimws(screen$title     %||% "")
    fields       <- screen$fields           %||% list()

    for (fld in fields) {
      fkey       <- fld$key       %||% ""
      field_cond <- trimws(fld$condition %||% "")

      # Build effective condition: combine screen + field conditions
      eff_cond <- build_effective_condition(screen_cond, field_cond)

      rows[[length(rows) + 1]] <- list(
        script_id           = script_id,
        script_title        = script_title,
        country             = country,
        screen_title        = screen_title,
        field_key           = fkey,
        field_key_lower     = tolower(gsub("[^A-Za-z0-9]", "", fkey)),
        screen_condition    = screen_cond,
        field_condition     = field_cond,
        effective_condition = eff_cond
      )
    }
  }

  if (length(rows) == 0) {
    return(list(
      conditions = data.frame(),
      meta = list(script_id = script_id, script_title = script_title,
                  country = country, file_path = json_path)
    ))
  }

  df <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  list(
    conditions = df,
    meta = list(script_id = script_id, script_title = script_title,
                country = country, file_path = json_path)
  )
}

#' Combine Screen-Level and Field-Level Conditions
#'
#' In Neotree, a field is shown only when BOTH its screen condition AND its
#' field condition are TRUE.  This function produces a single combined string.
#'
#' @param screen_cond  Screen condition string (may be "").
#' @param field_cond   Field condition string (may be "").
#' @return             Combined condition string, or "" if both are empty.
build_effective_condition <- function(screen_cond, field_cond) {
  # Normalise embedded newlines (some conditions span lines in the JSON)
  screen_cond <- gsub("[\r\n]+", " ", screen_cond)
  field_cond  <- gsub("[\r\n]+", " ", field_cond)
  screen_cond <- trimws(screen_cond)
  field_cond  <- trimws(field_cond)

  if (screen_cond == "" && field_cond == "") return("")
  if (screen_cond == "") return(field_cond)
  if (field_cond  == "") return(screen_cond)

  # Wrap each in parentheses to preserve operator precedence when combining
  paste0("(", screen_cond, ") and (", field_cond, ")")
}

#' Load All Neotree Scripts from the scripts Directory
#'
#' Scans both zim-scripts/ and mwi-scripts/ sub-directories.
#'
#' @param scripts_dir  Path to the neotree_scripts root directory.
#' @return             List with $conditions (combined data.frame) and
#'                     $index (one row per script).
load_all_scripts <- function(scripts_dir) {

  country_dirs <- list(
    ZIM = file.path(scripts_dir, "zim-scripts"),
    MWI = file.path(scripts_dir, "mwi-scripts")
  )

  all_conditions <- list()
  all_meta       <- list()

  for (country in names(country_dirs)) {
    dir_path <- country_dirs[[country]]
    if (!dir.exists(dir_path)) {
      log_warn("Scripts directory not found: %s", dir_path)
      next
    }

    json_files <- list.files(dir_path, pattern = "metadata\\.json$",
                             full.names = TRUE)
    if (length(json_files) == 0) {
      log_warn("No script JSON files found in: %s", dir_path)
      next
    }

    for (jf in json_files) {
      result <- tryCatch(
        parse_script_json(jf, country),
        error = function(e) {
          log_warn("Failed to parse script JSON: %s -- %s", basename(jf), e$message)
          NULL
        }
      )
      if (!is.null(result)) {
        if (nrow(result$conditions) > 0) all_conditions[[length(all_conditions) + 1]] <- result$conditions
        all_meta[[length(all_meta) + 1]] <- result$meta
      }
    }
  }

  conditions_df <- if (length(all_conditions) > 0)
    do.call(rbind, all_conditions) else data.frame()

  index_df <- if (length(all_meta) > 0) {
    do.call(rbind, lapply(all_meta, function(m) {
      data.frame(script_id = m$script_id, script_title = m$script_title,
                 country = m$country, file_path = m$file_path,
                 stringsAsFactors = FALSE)
    }))
  } else data.frame()

  n_scripts <- nrow(index_df)
  n_fields  <- nrow(conditions_df)
  n_with_cond <- if (n_fields > 0)
    sum(conditions_df$effective_condition != "", na.rm = TRUE) else 0

  log_info("Loaded %d script(s), %d field entries, %d with skip conditions.",
           n_scripts, n_fields, n_with_cond)

  list(conditions = conditions_df, index = index_df)
}

# Null-coalescing operator
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1]) && a[1] != "") a else b
