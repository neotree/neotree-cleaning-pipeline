# Data Dictionaries

This folder contains the v8 data dictionaries used by the cleaning pipeline.
Each dictionary is an `.xlsx` workbook with three sheets:

| Sheet | Contents |
|---|---|
| `Variables` | One row per clinical variable: question key, raw column names, data type, r_type, section, harmonised name, use_in_analysis flag, confidentiality flag, PII tier/category, plausible range, cleaning notes |
| `ValueMaps` | Allowed raw codes and label-to-code mappings for every categorical/object field; used by Module 04 (dictionary value cleaning) and Module 13 (categorical validation) |
| `PII_Patterns` | Regex patterns used by Module 00a as a fallback for detecting PII column names not already flagged via `confidential = TRUE` |

Dictionaries are rebuilt from the Neotree web-editor export keys by
`00_build_dictionary/00_build_dictionary_v8.r`. The files in this folder are
the **working copies** used at pipeline runtime — hand-edits applied here
(documented below) take effect on the next pipeline run without requiring a
full dictionary rebuild.

---

## PII Classification Criteria

Module 00a drops every column where `confidential = TRUE` in the Variables
sheet. The intended scope of this flag is **direct identifiers** — fields that,
alone or in trivial combination, re-identify a specific person:

- Names (baby, mother, next of kin, parent/guardian)
- Phone and cell numbers
- Residential addresses, villages, landmarks
- Date *and* time of birth (`dobtob`) — the millisecond-precision timestamp
  from the Neotree app is more specific than a plain date of birth

**Clinical outcome and treatment fields are not direct identifiers** even when
they concern sensitive topics (HIV status, HAART treatment, test results). A
reactive HIV test result, or a HAART start trimester, does not identify a
patient on its own. Such fields should use `confidential = FALSE` and, if
needed, be protected at the data-sharing layer (sample maker / access controls)
rather than removed wholesale at cleaning time.

---

## Hand-Edit Change Log

Changes to dictionary files that were applied manually (i.e. not by a
dictionary rebuild) are recorded here. Newest first.

---

### May 2026 — HIV-related field corrections (MWI admissions + discharges)

#### 1. `hivtestresult` — column retention fix

**Problem:** `hivtestresult.value` was present in MWI raw admissions data
(distribution: NR 18,468 · R 1,226 · Non Reactive 727 · Reactive 62 · U 58)
but absent from all cleaned MWI outputs. Root cause: `hivtestresult` was
classified as `confidential = TRUE / pii_tier = 1 / pii_category =
direct_identifier` in both MWI dictionaries, causing Module 00a to drop the
column before any cleaning ran. HIV test result is a clinical outcome field,
not a direct identifier (ZIM retains it — it was absent from the ZIM
dictionary and passed through the non-validated passthrough).

**Fix applied:**
- `dictionary_mwi_admissions.xlsx` Variables row 112: `hivtestresult`
  `confidential TRUE→FALSE`, `pii_tier` and `pii_category` cleared.
- `dictionary_mwi_discharges.xlsx` Variables row 79: `hivtestresult`
  same fix.
- `dictionary_mwi_discharges.xlsx` Variables row 80: `hivtestresultdc`
  same fix.

**Existing ValueMaps (unchanged — already correct):**

| question_key | raw_code | option_label | canonical_code |
|---|---|---|---|
| hivtestresult | R | Reactive | R |
| hivtestresult | NR | Non Reactive | NR |
| hivtestresult | U | Unknown | U |

These maps correctly handle the KCH mixed-label raw values: `Reactive`→`R`,
`Non Reactive`→`NR`; short codes `R`, `NR`, `U` pass through as-is.

---

#### 2. `hivtestresult` — ZIM admissions: field added + ValueMaps added

**Problem:** `hivtestresult` was absent from `dictionary_zim_admissions.xlsx`,
so Module 04 never applied value cleaning to ZIM data even though the raw
ZIM input contains the column.

**Fix applied:**
- `dictionary_zim_admissions.xlsx` Variables: new row added —
  `question_key = hivtestresult`, `r_type = categorical`,
  `confidential = FALSE`, `use_in_analysis = TRUE`,
  `harmonised_variable_name = hivtest_result`.
- `dictionary_zim_admissions.xlsx` ValueMaps: three rows added:

| raw_code | option_label | canonical_code |
|---|---|---|
| R | Positive | R |
| NR | Negative | NR |
| U | Unknown | U |

ZIM raw values `Positive`→`R`, `Negative`→`NR`; short codes `R`, `NR`, `U`
pass through as allowed codes.

---

#### 3. Four additional MWI fields unblocked from PII filter

**Problem:** A systematic review of all `confidential = TRUE` fields across
MWI and ZIM found four MWI clinical-outcome fields incorrectly classified as
`direct_identifier`. ZIM already exposes `mathivstat` as
`confidential = FALSE`; the other three are absent from ZIM dictionaries.

| field | dict(s) | type | label |
|---|---|---|---|
| `datehivtest` | MWI adm + dis | datetime | When was this test? |
| `haart` | MWI adm + dis | categorical | Mother on HAART? |
| `lengthhaart` | MWI adm + dis | categorical | Mother on HAART since when? |
| `mathivstat` | MWI adm | categorical | Mother's HIV status? |

**Fix applied:** `confidential` set to `FALSE`, `pii_tier` and `pii_category`
cleared for all four fields in the relevant dictionaries.

**ValueMaps (unchanged — already present and correct):**

`haart`: Y→Y (Yes) · N→N (No)

`lengthhaart`: 1stTrim · 2ndTrim · 3rdTrim · Late · U

`mathivstat`: R→R (Reactive) · NR→NR (Non Reactive) · U→U (Unknown)

`datehivtest`: no ValueMaps needed (datetime field).

---

### May 2026 — `mecpresent` and `mecthickthin` canonical code alignment

**Problem:** ZIM discharges used different canonical codes for two shared
fields, preventing cross-site alignment when files are joined.

| field | ZIM dis canonical (before) | all other dicts canonical |
|---|---|---|
| `mecpresent` Y | Y | Yes |
| `mecpresent` N | N | No |
| `mecpresent` U | U | UNK |
| `mecthickthin` U | U | UNK |

**Fix applied** in `dictionary_zim_discharges.xlsx` ValueMaps:
- `mecpresent` N canonical `N`→`No`
- `mecpresent` U canonical `U`→`UNK`
- `mecpresent` Y canonical `Y`→`Yes`
- `mecthickthin` U canonical `U`→`UNK`

---

### May 2026 — `lengthhaart` duplicate ValueMaps row removed (MWI adm + dis)

**Problem:** Both MWI dictionaries had `3rdTrim` appearing twice in the
`lengthhaart` ValueMaps — once with label "3rd Trimester more than 1 month
before delivery" and once with the shorter label "3rd Trimester". Duplicate
`question_key` + `raw_code` pairs cause non-deterministic behaviour in
`value_map_list` construction (the later entry silently overwrites the first in
the named-list merge).

**Fix applied:** The shorter duplicate "3rd Trimester" row removed from
`dictionary_mwi_admissions.xlsx` (was row 513) and
`dictionary_mwi_discharges.xlsx` (was row 585).

Retained entry: `3rdTrim` · "3rd Trimester more than 1 month before delivery"
· canonical `3rdTrim`.

---

### May 2026 — 7 boolean fields reclassified to categorical in MWI dicts

**Problem:** The fields below were typed `boolean` (`r_type = boolean`) in MWI
dictionaries but `categorical` in ZIM. Module 12 (boolean validation) converts
booleans to R `logical` (TRUE/FALSE), while Module 13 (categorical validation)
keeps raw Y/N/U character codes. In the joined output, MWI and ZIM values for
the same field are therefore in different formats and cannot be compared or
pooled.

| field | MWI adm | MWI dis | ZIM adm | ZIM dis |
|---|---|---|---|---|
| `mathivtest` | boolean → **categorical** | boolean → **categorical** | categorical | categorical |
| `birthplacesame` | boolean → **categorical** | boolean → **categorical** | categorical | categorical |
| `dysmorphic` | boolean → **categorical** | — | categorical | — |
| `feversr` | boolean → **categorical** | — | categorical | — |
| `ortolani` | boolean → **categorical** | — | categorical | — |
| `inorout` | categorical (unchanged) | boolean → **categorical** | categorical | categorical |
| `phototherapy` | — | boolean → **categorical** | — | categorical |

**Fix applied:** `r_type` changed from `boolean` to `categorical` for each
field in the relevant dictionary. ValueMaps added where absent:

| field | ValueMaps added |
|---|---|
| `mathivtest` | Y→Y (Yes) · N→N (No) · U→U (Unknown) |
| `birthplacesame` | Y→Y (Yes) · N→N (No) · U→U (Unknown) |
| `dysmorphic` | Y→Y (Yes) · N→N (No) |
| `feversr` | Y→Y (Yes) · N→N (No) |
| `ortolani` | Y→Y (Yes) · N→N (No) |
| `inorout` | In→In (Within PHC) · Out→Out (Outside PHC) |
| `phototherapy` | Y→Y (Yes) · N→N (No) |

**Site-specific notes:**
- `ortolani`: ZIM uses `YesOrto`/`NoOrto` as raw codes; MWI raw data contains
  `Y`/`N`. Both are now categorical but codes differ by site — document in
  cross-site analysis.
- `dysmorphic`: ZIM carries an extended set of specific dysmorphic features
  (CleftLip, Micro, HYDR, NTD, …) not present on the MWI form. MWI ValueMaps
  contain only Y/N.
- `birthplacesame` ZIM ValueMaps contain a duplicate `U` row with two
  different labels ("Known" and "Unknown", both canonical `U`). This is a
  pre-existing ZIM dict issue; not modified here.

---

*All hand-edits applied by Python/openpyxl script; changes verified by
re-reading dictionaries after save.*
