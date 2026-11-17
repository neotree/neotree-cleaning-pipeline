# =============================================================================
# NEOTREE CLEANING PIPELINE
# Module 10 helper: episode mode (baby ID and stay number)
# =============================================================================
# PURPOSE:
#   Replaces Stage 2 for admissions and discharges (main and PHC files) and
#   for births (ZIM maternal_outcomes, MWI combined_maternity_outcomes) when
#   cfg$dedup_mode is "episode".  Births: repeats are collapsed as below
#   (baby details also include birth outcome and birth order) and every other
#   record is a baby of its own; no stay_no, no key file.  Rows are collapsed only when they are the same event, and
#   every kept row receives a baby ID and a stay number.  The uid is not
#   changed.
#
# METHOD:
#   1. Records.  Rows sharing uid + facility are the same event, and are
#      collapsed, only when all of these hold:
#        - event times are within EP_WINDOW_HOURS;
#        - no identity field disagrees: sex, birth weight (more than
#          EP_BW_TOL_G apart), gestation (more than EP_GA_TOL_WK apart);
#        - the readmission flags do not differ.
#      Clock: admissions - admission date-time, else form start time.
#      Discharges - form start time, else discharge date-time.
#      The most complete row of a record is kept (highest uniquekey on a tie).
#   2. Babies (admissions).  Records sharing a uid in the file are taken in
#      date order; each joins the first baby under that uid it belongs to:
#        identity differs                         -> not that baby
#        flagged as a readmission                 -> same baby
#        same uid at another site, two or more
#        identity fields agree                    -> same baby (transfer)
#        other fields differ                      -> not that baby (probable)
#        other fields agree                       -> same baby (probable)
#        nothing to compare                       -> unresolved: own letter
#      Other fields: Apgar at 5 minutes, mode of delivery, birth facility,
#      maternal age.  Babies are lettered A, B, C in date order.
#   3. Stays.  The admission records of one baby are numbered 1, 2, 3 in date
#      order.
#   4. Discharges take the baby ID and stay number of the admission they fit,
#      read from the key file written by the admissions run:
#        first by the admission date-time carried on the discharge (within 1
#        hour, or exactly 2 hours), then by identity fields (two or more
#        disagreeing means no fit), then by the order of dates.
#        Two admissions fit equally -> the earlier one, flagged.
#        No admission fits          -> placed among the babies of the uid
#                                      with a stay of its own, flagged.
#      Several discharge forms for one stay are all kept; the form started
#      last (most complete on a tie) is marked as the primary form.
#
# COLUMNS ADDED:
#   baby_id            uid, a full stop and a letter (A, B, ...)
#   stay_no            1, 2, 3 ... within baby_id (not for births)
#   dedup_rows_merged  rows collapsed into this row (1 = none)
#   dedup_basis        why the baby_id and stay_no were given
#   dedup_flag         "none", or one or more of: unresolved, probable,
#                      ambiguous_link, link_doubt, no_admission,
#                      outcome_conflict, same_day_pair (births: another
#                      baby recorded the same day under the same UID),
#                      collapsed_no_identity (rows
#                      collapsed although no identity field could be
#                      compared), no_uid (separated by ";")
#   stay_form_primary  discharges only: TRUE for one form per baby_id + stay_no
# =============================================================================

EP_WINDOW_HOURS <- 1
EP_BW_TOL_G     <- 100
EP_GA_TOL_WK    <- 1
EP_DEATH_CODES  <- c("NND", "NND<24", "NND>24", "BID", "STB")

# Datasets covered by episode mode and the role each plays.  A discharges
# dataset reads the key file of its paired admissions dataset.
EP_ROLES <- c(admissions = "admissions", discharges = "discharges",
              phc_admissions = "admissions", phc_discharges = "discharges",
              maternal_outcomes = "births", combined_maternity_outcomes = "births")

# Datasets covered in some countries only.  The Malawi maternal_outcomes file
# is a component of combined_maternity_outcomes and keeps the current rule.
EP_ROLE_COUNTRIES <- list(maternal_outcomes = "ZIM", combined_maternity_outcomes = "MWI")

#' Role of a dataset in episode mode: "admissions", "discharges", "births"
#' or NA when the dataset (in that country) is not covered
ep_role <- function(dataset, country = NULL) {
  r <- unname(EP_ROLES[dataset])
  if (!is.null(country)) {
    for (i in seq_along(dataset)) {
      lim <- EP_ROLE_COUNTRIES[[dataset[i]]]
      if (!is.null(lim) && !(toupper(country) %in% lim)) r[i] <- NA_character_
    }
  }
  r
}

.ep_col <- function(df, nm) if (nm %in% names(df)) df[[nm]] else rep(NA, nrow(df))
.ep_time <- function(x) {
  if (inherits(x, "POSIXt")) return(as.POSIXct(x, tz = "UTC"))
  if (inherits(x, "Date"))   return(as.POSIXct(x, tz = "UTC"))
  x <- sub("Z$", "", sub("T", " ", as.character(x)))
  suppressWarnings(as.POSIXct(x, tz = "UTC", optional = TRUE,
                              tryFormats = c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%d %H:%M", "%Y-%m-%d")))
}
.ep_num   <- function(x) suppressWarnings(as.numeric(as.character(x)))
.ep_range <- function(x, lo, hi) { x[!is.na(x) & (x < lo | x > hi)] <- NA; x }
.ep_sex   <- function(x) {
  s <- toupper(substr(trimws(as.character(x)), 1, 1))
  ifelse(s %in% c("M", "F"), s, NA_character_)
}
.ep_yes <- function(x) {
  s <- tolower(trimws(as.character(x)))
  ifelse(is.na(s) | s == "", NA, s %in% c("y", "yes", "true", "1"))
}
.ep_hours  <- function(x, y) as.numeric(difftime(x, y, units = "hours"))
.ep_first  <- function(x) x[!is.na(x)][1]
.ep_difnum <- function(a, b, tol) !is.na(a) & !is.na(b) & abs(a - b) > tol
.ep_difchr <- function(a, b) !is.na(a) & !is.na(b) & a != b
.ep_both   <- function(a, b) !is.na(a) & !is.na(b)
.ep_letter <- function(k) ifelse(k <= 26, LETTERS[pmin(k, 26)], paste0("Z", k))

.ep_v <- function(x, nm) { v <- x[[nm]]; if (is.null(v)) rep(NA, nrow(x)) else v }
.ep_id_dis  <- function(a, b) .ep_difchr(a$sex, b$sex) + .ep_difnum(a$bw, b$bw, EP_BW_TOL_G) +
  .ep_difnum(a$ga, b$ga, EP_GA_TOL_WK) +
  .ep_difchr(.ep_v(a, "oc"), .ep_v(b, "oc")) + .ep_difchr(.ep_v(a, "ord"), .ep_v(b, "ord"))
.ep_id_comp <- function(a, b) .ep_both(a$sex, b$sex) + .ep_both(a$bw, b$bw) + .ep_both(a$ga, b$ga) +
  .ep_both(.ep_v(a, "oc"), .ep_v(b, "oc")) + .ep_both(.ep_v(a, "ord"), .ep_v(b, "ord"))
.ep_ot_dis  <- function(a, b) (.ep_difnum(a$apgar5, b$apgar5, 0) + .ep_difchr(a$mode, b$mode) +
                                 .ep_difchr(a$birthf, b$birthf) + .ep_difnum(a$matage, b$matage, 1)) > 0
.ep_ot_comp <- function(a, b) (.ep_both(a$apgar5, b$apgar5) + .ep_both(a$mode, b$mode) +
                                 .ep_both(a$birthf, b$birthf) + .ep_both(a$matage, b$matage)) > 0

.ep_outcome_class <- function(x) {
  s <- toupper(gsub("[^A-Za-z]", "", as.character(x)))
  dplyr::case_when(s %in% c("LB", "LIVEBIRTH", "ENND") ~ "live",
                   s %in% c("STB", "STBM", "STBF", "SB", "SBF", "SBM") | grepl("^STILLBIRTH", s) ~ "still",
                   s == "MISC" ~ "misc", TRUE ~ NA_character_)
}
.ep_birth_order <- function(x) { s <- trimws(as.character(x)); ifelse(grepl("^(Tw|Tr)[0-9]$", s), s, NA_character_) }

#' Standard comparison frame, one line per row of df.  role "births" reads the
#' maternal-file fields: baby sex, birth weight, gestation, birth outcome
#' (live birth, stillbirth, miscarriage), birth order, and the maternal
#' admission date-time as the clock.
ep_frame <- function(df, role = "admissions") {
  d <- data.frame(
    .row      = seq_len(nrow(df)),
    uid       = as.character(df$uid),
    facility  = as.character(df$facility),
    uniquekey = as.character(.ep_col(df, "uniquekey")),
    miss      = rowSums(is.na(df[, setdiff(names(df), c("uid", "facility")), drop = FALSE])),
    t_adm     = .ep_time(.ep_col(df, "datetimeadmission.value")),
    t_start   = .ep_time(.ep_col(df, "startedat")),
    t_dis     = dplyr::coalesce(.ep_time(.ep_col(df, "datetimedischarge.value")),
                                .ep_time(.ep_col(df, "datetimedeath.value")),
                                .ep_time(.ep_col(df, "datedischvitals.value")),
                                .ep_time(.ep_col(df, "datedischweight.value")),
                                .ep_time(.ep_col(df, "startedat"))),
    sex       = dplyr::coalesce(.ep_sex(.ep_col(df, "gender.value")), .ep_sex(.ep_col(df, "sexdis.value"))),
    bw        = dplyr::coalesce(.ep_range(.ep_num(.ep_col(df, "birthweight.value")), 300, 7000),
                                .ep_range(.ep_num(.ep_col(df, "bw.value")), 300, 7000),
                                .ep_range(.ep_num(.ep_col(df, "bwdc.value")), 300, 7000)),
    ga        = dplyr::coalesce(.ep_range(.ep_num(.ep_col(df, "gestation.value")), 20, 46),
                                .ep_range(.ep_num(.ep_col(df, "gestationdc.value")), 20, 46)),
    readm     = .ep_yes(.ep_col(df, "readmission.value")),
    apgar5    = .ep_num(.ep_col(df, "apgar5.value")),
    mode      = as.character(.ep_col(df, "modedelivery.value")),
    birthf    = as.character(.ep_col(df, "birthfacility.value")),
    matage    = .ep_num(.ep_col(df, "matageyrs.value")),
    outcome   = trimws(as.character(.ep_col(df, "neotreeoutcome.value"))),
    oc        = NA_character_,
    ord       = NA_character_,
    stringsAsFactors = FALSE
  )
  if (identical(role, "births")) {
    d$t_adm <- .ep_time(.ep_col(df, "dateadmission.value"))
    d$sex   <- dplyr::coalesce(.ep_sex(.ep_col(df, "sexdis.value")), .ep_sex(.ep_col(df, "sex.value")))
    d$bw    <- dplyr::coalesce(.ep_range(.ep_num(.ep_col(df, "bwtdis.value")), 300, 7000),
                               .ep_range(.ep_num(.ep_col(df, "birthweight.value")), 300, 7000),
                               .ep_range(.ep_num(.ep_col(df, "bwt.value")), 300, 7000))
    d$ga    <- .ep_range(.ep_num(.ep_col(df, "gestation.value")), 20, 46)
    d$oc    <- .ep_outcome_class(.ep_col(df, "neotreeoutcome.value"))
    d$ord   <- .ep_birth_order(.ep_col(df, "typebirth.value"))
    d$readm <- NA
  }
  d
}

#' Step 1: collapse rows into records (one kept row per record)
ep_records <- function(d, clock = c("admission", "form")) {
  clock <- match.arg(clock)
  d$t_clock <- if (clock == "admission") dplyr::coalesce(d$t_adm, d$t_start) else dplyr::coalesce(d$t_start, d$t_dis)
  d$key_ts  <- grepl("^\\d{4}-\\d{2}-\\d{2}T", d$uniquekey)
  d <- d %>% dplyr::arrange(uid, facility, t_clock, miss) %>%
    dplyr::group_by(uid, facility) %>% dplyr::mutate(g_n = dplyr::n()) %>% dplyr::ungroup()
  d$comp <- 1L
  d$no_id_ev <- FALSE
  g   <- which(d$g_n > 1)
  idx <- split(g, paste(d$uid[g], d$facility[g], sep = "\r"))
  for (ix in idx) {
    m  <- length(ix)
    cb <- utils::combn(seq_len(m), 2)
    a <- d[ix[cb[1, ]], ]; b <- d[ix[cb[2, ]], ]
    h <- if (clock == "admission") {
      h1 <- abs(.ep_hours(a$t_adm, b$t_adm)); ifelse(is.na(h1), abs(.ep_hours(a$t_start, b$t_start)), h1)
    } else {
      h1 <- abs(.ep_hours(a$t_start, b$t_start)); ifelse(is.na(h1), abs(.ep_hours(a$t_dis, b$t_dis)), h1)
    }
    readm_differs <- xor(a$readm %in% TRUE, b$readm %in% TRUE)
    on <- !is.na(h) & h <= EP_WINDOW_HOURS & .ep_id_dis(a, b) == 0 & !readm_differs
    ok <- matrix(FALSE, m, m)
    ok[cbind(cb[1, ], cb[2, ])] <- on
    ok <- ok | t(ok)
    ev <- matrix(FALSE, m, m)
    ev[cbind(cb[1, ], cb[2, ])] <- .ep_id_comp(a, b) >= 1
    ev <- ev | t(ev)
    # A row joins a record only when it is compatible with every row already
    # in that record (no chaining through a third row).
    comp <- integer(m); n_comp <- 0L
    for (i in seq_len(m)) {
      fit <- 0L
      for (k in seq_len(n_comp)) if (all(ok[i, which(comp == k)])) { fit <- k; break }
      if (fit == 0L) { n_comp <- n_comp + 1L; fit <- n_comp }
      comp[i] <- fit
    }
    d$comp[ix] <- comp
    for (k in which(tabulate(comp) > 1)) {
      mk <- which(comp == k)
      if (!any(ev[mk, mk])) d$no_id_ev[ix[mk]] <- TRUE
    }
  }
  d %>% dplyr::arrange(uid, facility, comp, miss, key_ts, dplyr::desc(uniquekey)) %>%
    dplyr::group_by(uid, facility, comp) %>%
    dplyr::summarise(keep_row = dplyr::first(.row), uniquekey = dplyr::first(uniquekey),
                     miss = dplyr::first(miss), n_rows = dplyr::n(), no_id_ev = any(no_id_ev),
                     t_adm = .ep_first(t_adm), t_start = .ep_first(t_start), t_dis = .ep_first(t_dis),
                     sex = .ep_first(sex), bw = .ep_first(bw), ga = .ep_first(ga),
                     readm = any(readm %in% TRUE),
                     apgar5 = .ep_first(apgar5), mode = .ep_first(mode), birthf = .ep_first(birthf),
                     matage = .ep_first(matage), outcome = .ep_first(outcome),
                     oc = .ep_first(oc), ord = .ep_first(ord), .groups = "drop")
}

.ep_relation <- function(r, members) {
  if (any(.ep_id_dis(members, r) >= 1)) return("different: identity differs")
  if (isTRUE(r$readm)) return("same: flagged readmission")
  if (all(members$facility != r$facility) && any(.ep_id_comp(members, r) >= 2))
    return("same: same UID at another site")
  if (any(.ep_ot_dis(members, r))) return("different: other fields differ")
  if (any(.ep_ot_comp(members, r))) return("same: other fields agree")
  "unresolved"
}

.ep_place <- function(r, pool) {
  if (nrow(pool) == 0) return(list(k = 1L, basis = "first record under this UID"))
  ks  <- sort(unique(pool$letter_k))
  rel <- vapply(ks, function(k) .ep_relation(r, pool[pool$letter_k == k, , drop = FALSE]), character(1))
  same <- which(startsWith(rel, "same"))
  if (length(same)) return(list(k = ks[same[1]], basis = sub("^same: ", "same baby: ", rel[same[1]])))
  basis <- if (any(rel == "unresolved")) "unresolved: own letter"
           else if (any(rel == "different: other fields differ")) "different baby: other fields differ"
           else "different baby: identity differs"
  list(k = max(ks) + 1L, basis = basis)
}

#' Steps 2 and 3: baby letters and stay numbers for admission records
ep_assign_babies <- function(A) {
  A$t_event <- dplyr::coalesce(A$t_adm, A$t_start)
  A <- A %>% dplyr::arrange(uid, t_event, facility) %>% dplyr::group_by(uid) %>%
    dplyr::mutate(u_n = dplyr::n()) %>% dplyr::ungroup()
  A$letter_k <- 1L
  A$basis    <- "only record under this UID"
  multi <- split(which(A$u_n > 1), A$uid[A$u_n > 1])
  for (ix in multi) {
    for (pos in seq_along(ix)) {
      res <- .ep_place(A[ix[pos], ], A[ix[seq_len(pos - 1)], , drop = FALSE])
      A$letter_k[ix[pos]] <- res$k
      A$basis[ix[pos]]    <- res$basis
    }
  }
  A %>% dplyr::group_by(uid, letter_k) %>% dplyr::arrange(t_event, .by_group = TRUE) %>%
    dplyr::mutate(stay = dplyr::row_number()) %>% dplyr::ungroup() %>%
    dplyr::mutate(baby_id = paste0(uid, ".", .ep_letter(letter_k)), adm_row = dplyr::row_number())
}

#' Births: every record left after collapsing repeats is a different baby
#' (a birth happens once), lettered in date order under its UID.  A record
#' within 24 hours of an earlier one under the same UID whose baby details
#' differ is flagged as a same-day pair; one in which nothing differs from an
#' earlier record is unresolved.
ep_assign_births <- function(R) {
  R$t_event <- dplyr::coalesce(R$t_adm, R$t_start)
  R <- R %>% dplyr::arrange(uid, t_event, facility) %>% dplyr::group_by(uid) %>%
    dplyr::mutate(u_n = dplyr::n(), letter_k = dplyr::row_number()) %>% dplyr::ungroup()
  R$basis <- ifelse(R$u_n == 1, "only record under this UID", "first record under this UID")
  multi <- split(which(R$u_n > 1), R$uid[R$u_n > 1])
  for (ix in multi) {
    for (pos in seq_along(ix)[-1]) {
      a <- R[ix[pos], ]; prev <- R[ix[seq_len(pos - 1)], , drop = FALSE]
      h   <- abs(.ep_hours(prev$t_event, a$t_event))
      dfr <- .ep_id_dis(prev, a) >= 1
      sd  <- !is.na(h) & h <= 24
      R$basis[ix[pos]] <- if (any(sd)) {
        if (all(dfr[sd])) "different baby: same day, baby details differ" else "unresolved: same day, nothing differs"
      } else {
        if (all(dfr)) "different baby: another day" else "unresolved: another day, nothing differs"
      }
    }
  }
  R %>% dplyr::mutate(baby_id = paste0(uid, ".", .ep_letter(letter_k)))
}

#' Step 4: discharges take the baby ID and stay of the admission they fit
ep_link_discharges <- function(D, A) {
  D$dis_row <- seq_len(nrow(D))
  D$letter_k <- NA_integer_; D$stay <- NA_integer_; D$baby_id <- NA_character_
  D$link_basis <- NA_character_; D$adm_row <- NA_integer_
  pr <- dplyr::inner_join(D %>% dplyr::select(dis_row, uid, facility, t_adm, t_dis, sex, bw, ga) %>%
                            dplyr::rename_with(~ paste0(.x, "_d"), -c(uid, facility)),
                          A %>% dplyr::select(adm_row, uid, facility, t_adm, sex, bw, ga) %>%
                            dplyr::rename_with(~ paste0(.x, "_a"), -c(uid, facility)),
                          by = c("uid", "facility"), relationship = "many-to-many")
  if (nrow(pr) > 0) {
    pr <- pr %>%
      dplyr::mutate(adm_gap   = abs(.ep_hours(t_adm_d, t_adm_a)),
                    confirmed = !is.na(adm_gap) & (adm_gap <= 1 | abs(adm_gap - 2) <= 0.02),
                    n_id      = .ep_difchr(sex_d, sex_a) + .ep_difnum(bw_d, bw_a, EP_BW_TOL_G) +
                                .ep_difnum(ga_d, ga_a, EP_GA_TOL_WK),
                    strong    = n_id >= 2,
                    doubt     = strong | n_id == 1 |
                                (!is.na(t_dis_d) & !is.na(t_adm_a) & .ep_hours(t_dis_d, t_adm_a) < -24) |
                                (!is.na(adm_gap) & adm_gap > 24))
    # Within a tier, candidates are ranked by fewest identity disagreements,
    # then the smallest admission-time gap, then the earliest admission.
    best <- function(flag, row, nid, gap, t) {
      ok <- which(flag); if (!length(ok)) return(NA_integer_)
      row[ok[order(nid[ok], gap[ok], t[ok], na.last = TRUE)][1]]
    }
    ties <- function(flag, nid) {
      ok <- which(flag); if (!length(ok)) return(0L)
      sum(nid[ok] == min(nid[ok]))
    }
    per <- pr %>% dplyr::group_by(dis_row_d) %>%
      dplyr::summarise(n_conf = ties(confirmed & !strong, n_id), n_clean = ties(!doubt, n_id),
                       n_soft = ties(!strong, n_id),
                       to_conf  = best(confirmed & !strong, adm_row_a, n_id, adm_gap, t_adm_a),
                       to_clean = best(!doubt, adm_row_a, n_id, adm_gap, t_adm_a),
                       to_soft  = best(!strong, adm_row_a, n_id, adm_gap, t_adm_a), .groups = "drop") %>%
      dplyr::mutate(link_basis = dplyr::case_when(
                      n_conf == 1  ~ "matched: admission date-time on the discharge form",
                      n_conf >= 2  ~ "ambiguous: closest admission used (earlier on a tie)",
                      n_clean == 1 ~ "matched: only admission that fits",
                      n_clean >= 2 ~ "ambiguous: closest admission used (earlier on a tie)",
                      n_soft == 1  ~ "matched with a doubt",
                      n_soft >= 2  ~ "ambiguous: closest admission used (earlier on a tie)",
                      TRUE         ~ NA_character_),
                    adm_row = dplyr::case_when(n_conf >= 1 ~ to_conf, n_clean >= 1 ~ to_clean,
                                               n_soft >= 1 ~ to_soft, TRUE ~ NA_integer_))
    m <- match(D$dis_row, per$dis_row_d)
    D$link_basis <- per$link_basis[m]
    D$adm_row    <- per$adm_row[m]
    ma <- match(D$adm_row, A$adm_row)
    D$letter_k <- A$letter_k[ma]; D$stay <- A$stay[ma]; D$baby_id <- A$baby_id[ma]
  }

  pool_all <- A %>% dplyr::select(uid, facility, sex, bw, ga, readm, apgar5, mode, birthf, matage,
                                  letter_k, stay)
  loose <- D %>% dplyr::filter(is.na(adm_row)) %>% dplyr::arrange(uid, dplyr::coalesce(t_dis, t_start))
  had_adm_here <- paste(loose$uid, loose$facility) %in% paste(A$uid, A$facility)
  pool_by_uid <- split(seq_len(nrow(pool_all)), pool_all$uid)
  extra <- list()
  for (i in seq_len(nrow(loose))) {
    r <- loose[i, ]
    r$readm <- NA
    ix   <- pool_by_uid[[r$uid]]
    pool <- if (is.null(ix)) pool_all[0, ] else pool_all[ix, , drop = FALSE]
    if (!is.null(extra[[r$uid]])) pool <- rbind(pool, extra[[r$uid]])
    res    <- .ep_place(r, pool)
    joined <- nrow(pool) > 0 && res$k %in% pool$letter_k
    st     <- if (joined) max(pool$stay[pool$letter_k == res$k]) + 1L else 1L
    basis  <- if (joined) "discharge only: fits a baby already under this UID"
              else if (had_adm_here[i]) "discharge only: does not fit the admissions under this UID"
              else "discharge only: no admission under this UID at this site"
    k <- D$dis_row == r$dis_row
    D$letter_k[k] <- res$k; D$stay[k] <- st; D$link_basis[k] <- basis
    D$baby_id[k]  <- paste0(r$uid, ".", .ep_letter(res$k))
    extra[[r$uid]] <- rbind(extra[[r$uid]],
                            data.frame(uid = r$uid, facility = r$facility, sex = r$sex, bw = r$bw, ga = r$ga,
                                       readm = NA, apgar5 = r$apgar5, mode = r$mode, birthf = r$birthf,
                                       matage = r$matage, letter_k = res$k, stay = st,
                                       stringsAsFactors = FALSE))
  }
  D
}

.ep_flags <- function(...) {
  m <- cbind(...)
  apply(m, 1, function(x) { x <- x[!is.na(x)]; if (length(x)) paste(x, collapse = ";") else "none" })
}

#' Episode mode for one file
#'
#' @param df        data.frame after Module 09 (Stage 1 is not applied in
#'                  episode mode: identical repeats are collapsed here, after
#'                  the identity check).
#' @param dataset   "admissions" or "discharges".
#' @param adm_keys  for discharges: the record table written by the
#'                  admissions run (ep_assign_babies output).
#' @return list(df = kept rows with the new columns, keys = admission record
#'         table (admissions only), summary = named counts)
ep_dedup <- function(df, dataset, adm_keys = NULL) {
  stopifnot(dataset %in% c("admissions", "discharges", "births"))
  d <- ep_frame(df, dataset)
  no_uid <- which(is.na(d$uid) | trimws(d$uid) == "")
  if (length(no_uid)) d <- d[-no_uid, , drop = FALSE]

  if (dataset == "births") {
    R <- ep_assign_births(ep_records(d, "admission"))
    basis <- R$basis
    flag  <- .ep_flags(ifelse(startsWith(basis, "unresolved"), "unresolved", NA),
                       ifelse(grepl("same day, baby details differ", basis), "same_day_pair", NA),
                       ifelse(R$no_id_ev, "collapsed_no_identity", NA))
    out <- df[R$keep_row, , drop = FALSE]
    out$baby_id <- R$baby_id
    out$dedup_rows_merged <- as.integer(R$n_rows)
    out$dedup_basis <- basis
    out$dedup_flag  <- flag
    keys <- NULL
  } else if (dataset == "admissions") {
    R <- ep_assign_babies(ep_records(d, "admission"))
    basis <- R$basis
    flag  <- .ep_flags(ifelse(startsWith(basis, "unresolved"), "unresolved", NA),
                       ifelse(grepl("other fields", basis), "probable", NA),
                       ifelse(R$no_id_ev, "collapsed_no_identity", NA))
    out <- df[R$keep_row, , drop = FALSE]
    out$baby_id <- R$baby_id
    out$stay_no <- as.integer(R$stay)
    out$dedup_rows_merged <- as.integer(R$n_rows)
    out$dedup_basis <- basis
    out$dedup_flag  <- flag
    keys <- R %>% dplyr::select(adm_row, uid, facility, uniquekey, t_adm, t_start, sex, bw, ga, readm,
                                apgar5, mode, birthf, matage, letter_k, stay, baby_id)
  } else {
    if (is.null(adm_keys)) stop("ep_dedup: discharges need the admissions key table.")
    R <- ep_link_discharges(ep_records(d, "form"), adm_keys)
    R <- R %>% dplyr::group_by(baby_id, stay) %>%
      dplyr::mutate(forms = dplyr::n(),
                    died_any = any(outcome %in% EP_DEATH_CODES),
                    alive_any = any(!is.na(outcome) & outcome != "" & !(outcome %in% EP_DEATH_CODES)),
                    ord = rank(-as.numeric(dplyr::coalesce(t_start, t_dis)) * 1e6 + miss,
                               ties.method = "first", na.last = TRUE),
                    primary = ord == 1) %>%
      dplyr::ungroup()
    basis <- R$link_basis
    flag  <- .ep_flags(ifelse(startsWith(basis, "ambiguous"), "ambiguous_link", NA),
                       ifelse(basis == "matched with a doubt", "link_doubt", NA),
                       ifelse(startsWith(basis, "discharge only"), "no_admission", NA),
                       ifelse(R$forms > 1 & R$died_any & R$alive_any, "outcome_conflict", NA),
                       ifelse(R$no_id_ev, "collapsed_no_identity", NA))
    out <- df[R$keep_row, , drop = FALSE]
    out$baby_id <- R$baby_id
    out$stay_no <- as.integer(R$stay)
    out$dedup_rows_merged <- as.integer(R$n_rows)
    out$dedup_basis <- basis
    out$dedup_flag  <- flag
    out$stay_form_primary <- R$primary
    keys <- NULL
  }

  if (length(no_uid)) {
    extra <- df[no_uid, , drop = FALSE]
    extra$baby_id <- NA_character_
    if (dataset != "births") extra$stay_no <- NA_integer_
    extra$dedup_rows_merged <- 1L
    extra$dedup_basis <- "no uid: row kept as it is"
    extra$dedup_flag  <- "no_uid"
    if (dataset == "discharges") extra$stay_form_primary <- NA
    out <- rbind(out, extra)
  }

  rk <- paste(out$uid, out$facility, out$uniquekey, sep = "\r")
  summary <- c(
    rows_in            = nrow(df),
    rows_out           = nrow(out),
    rows_collapsed     = nrow(df) - nrow(out),
    distinct_uids      = dplyr::n_distinct(out$uid),
    distinct_babies    = dplyr::n_distinct(out$baby_id, na.rm = TRUE),
    distinct_stays     = if (dataset == "births") NA_integer_
                         else nrow(dplyr::distinct(out[!is.na(out$baby_id), ], baby_id, stay_no)),
    rows_without_uid   = length(no_uid),
    rows_flagged       = sum(out$dedup_flag != "none"),
    rows_sharing_uid_facility_uniquekey = sum(rk %in% rk[duplicated(rk)])
  )
  list(df = out, keys = keys, summary = summary,
       basis_counts = table(out$dedup_basis, useNA = "ifany"),
       flag_counts  = table(unlist(strsplit(out$dedup_flag[out$dedup_flag != "none"], ";"))))
}

#' Files that shape the admissions key table, relative to the pipeline
#' folder `root`: the R code of the dictionary build and of Modules 00a to
#' 10 with the setup, and the dictionary workbooks.
ep_code_files <- function(root = ".") {
  dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  dirs <- dirs[grepl("^(00_setup|00_build_dictionary|00a_|0[1-9]_|10_)", basename(dirs))]
  sort(c(list.files(dirs, pattern = "\\.r$", full.names = TRUE),
         list.files(file.path(root, "dictionaries"), pattern = "\\.xlsx$", full.names = TRUE)))
}

#' Fingerprint of those files and of the rule's settings
.ep_code_hash <- function(root = ".") {
  f <- ep_code_files(root)
  if (!length(f)) stop("Module 10 (episode mode): no pipeline code found to fingerprint.")
  c(basename(f), unname(tools::md5sum(f)), EP_WINDOW_HOURS, EP_BW_TOL_G, EP_GA_TOL_WK)
}

#' Write the admissions key table with a fingerprint of its input file
#' (md5 of the file), of the code and settings that built it, and of the
#' dictionary the admissions run read (path, and md5 taken when setup read
#' it; the key file is not written if the dictionary has changed since)
#'
#' The file is written to a temporary name and renamed, so a half-written
#' key file is never read.
ep_write_keys <- function(keys, path, source_csv, dict_file, dict_md5, root = ".") {
  if (is.null(dict_file) || !file.exists(dict_file) ||
      !identical(unname(tools::md5sum(dict_file)), dict_md5))
    stop("Module 10 (episode mode): the dictionary is missing or changed during the run; key file not written.")
  dict <- list(path = normalizePath(dict_file), md5 = dict_md5)
  obj  <- list(keys = keys, mode = "episode", source = basename(source_csv),
               md5 = unname(tools::md5sum(source_csv)), code = .ep_code_hash(root),
               dict = dict)
  tmp  <- paste0(path, ".tmp")
  saveRDS(obj, tmp)
  if (!file.rename(tmp, path)) stop(sprintf("Could not write %s.", path))
  invisible(path)
}

#' Read the admissions key table, refusing one made from another input file
#' or by other code
ep_read_keys <- function(path, source_csv, root = ".") {
  if (!file.exists(path))
    stop(sprintf(paste("Module 10 (episode mode): %s not found.",
                       "Run the admissions file %s in episode mode first."),
                 path, basename(source_csv)))
  obj  <- readRDS(path)
  ok <- is.list(obj) && identical(obj$mode, "episode") && identical(obj$source, basename(source_csv)) &&
    identical(obj$md5, unname(tools::md5sum(source_csv))) && identical(obj$code, .ep_code_hash(root)) &&
    !is.null(obj$dict) && file.exists(obj$dict$path) &&
    identical(obj$dict$md5, unname(tools::md5sum(obj$dict$path)))
  if (!ok)
    stop(sprintf(paste("Module 10 (episode mode): %s was not made from the current %s",
                       "with the current code.",
                       "Run the admissions file in episode mode again."),
                 path, basename(source_csv)))
  obj$keys
}
