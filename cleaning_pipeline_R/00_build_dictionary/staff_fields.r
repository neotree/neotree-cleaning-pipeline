# =============================================================================
# NEOTREE CLEANING PIPELINE -- dictionary build: staff fields
# =============================================================================
# PURPOSE:
#   Defines the question keys whose answer options are the names or codes of
#   health workers.  Sourced by 00_build_dictionary.r and
#   00d_build_user_dictionary.r, which do not write the answer options of
#   these fields to any dictionary.
# =============================================================================

# Matched case-insensitively against the whole key.
STAFF_KEY_PATTERN <- paste0(
  "^(hcwsig|hcwsigdis|signature|eqhcwsig|dataentryname|dataentrynameother|",
  "otherclinicians|eqdqc|concall|firm|delhcwname|hcwname|hcwid|hcwiddis|",
  "drid|reviewid)$"
)

# Written in place of the value list of a staff field.
STAFF_VALUES_NOTE <- "Not listed (staff identifier)"

# TRUE for keys of staff fields.  Harmonised names (for example hcwsig_dis)
# and .value / .label suffixes are accepted.
is_staff_key <- function(k) {
  k <- gsub("_", "", sub("(\\.value|\\.label)$", "", as.character(k)))
  !is.na(k) & grepl(STAFF_KEY_PATTERN, k, ignore.case = TRUE)
}
