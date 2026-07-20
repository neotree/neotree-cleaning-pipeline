# Module 04: Dictionary-Based Value Cleaning

## Purpose
Corrects "label contamination" -- a common data quality issue where the descriptive text label of a question (e.g. `"Normal tone, movement in all limbs"`) appears in the data value column instead of the expected short code (e.g. `"Norm"`). Uses the v8 data dictionary to replace labels with their correct canonical codes.

Also normalises multi-select encoding: Neotree app versions and database export pipelines store multi-select fields in two formats (`{DCC,S2S}` brace format and `["DCC","S2S"]` JSON-array format). This module converts all JSON-array encoded values to the canonical brace format before validation runs.

---

## When It Runs
After Module 03 (duplicate column merging). Dictionary corrections must be applied before forward-filling and type assignment.

---

## Logic

The module uses `cfg$value_map_list` -- a nested list built in Module 00 from the dictionary's `ValueMaps` sheet. Each entry maps a `question_key` to:
- `allowed_codes` -- the set of valid raw codes for that variable.
- `canonical_codes` -- the set of canonical codes (the harmonisation *targets* this module emits).
- `label_to_code` -- a lookup from display labels (or question text) to their canonical code.
- `code_to_canonical` -- a lookup from raw code to canonical code (added 2026-06-12; lets the module convert a raw code to canonical and underpins case-insensitive matching).

The module runs three passes in order:

**Step 0 -- Multi-select encoding normalisation (`normalise_multiselect_encoding`)**

Neotree exports contain multi-select values in two formats depending on app version and export pipeline:

| Format | Example |
|--------|---------|
| Brace format (canonical) | `{DCC,S2S}` |
| JSON-array format (older) | `["DCC","S2S"]` |

This step converts all JSON-array values to the canonical brace format. It targets any column whose base name appears in `cfg$value_map_list`, plus a hardcoded list of known multi-select columns (`resus`, `delivinter`). After normalisation, the rest of the module sees a single consistent representation.

To add a newly introduced multi-select field, append its column name to `MULTISELECT_COLS` inside `normalise_multiselect_encoding()`.

**Step 1 -- Dictionary-based canonical harmonisation (`clean_values_using_dict`)**

> **Rewritten 2026-06-12 (categorical harmonisation work).** Previously this step
> only rewrote a value if it *exactly* matched a canonical code or an *exact*
> option-label string; every other value fell through untouched. That let case
> variants (`UNK` vs `Unk`), legacy boolean encodings (`true`/`false`/`Yes`/`No`),
> case differences inside multi-selects (`{BP,GENT}` vs `{BP,Gent}`), and free-text
> all pass through into the cleaned outputs. The audit of the 10 June 2026 extract
> found 292 categorical variables affected (~1.12M cell values). The function now
> resolves each value to its **canonical code** wherever it can do so *unambiguously*.

For each `.value` or `.valuedischarge` column whose base name exists in the value map,
every unique non-null value is resolved in this order (a helper `resolve_token()`
applies rules 1--5 to a single token):

1. **Already canonical** -- value is in `canonical_codes` -> left unchanged.
2. **Canonical match ignoring case** -- e.g. `unk` -> `Unk`; emits the dictionary's spelling.
3. **Raw code (any case)** -- via `code_to_canonical` -> emits the canonical code.
4. **Option label (any case)** -- via `label_to_code` -> emits the canonical code.
   If the label maps to an empty/NA code (question-text contamination) -> value **set to NA**.
5. **Legacy boolean** -- `true/yes/t/y` -> `Y`, `false/no/f/n` -> `N`, **only** when the
   variable's canonical set is a subset of `{Y, N, U}` (i.e. a genuine yes/no field).
6. **Multi-select `{A,B,C}`** -- each token is resolved by rules 1--5 (so case-only
   variants inside braces are corrected, e.g. `{BP,GENT}` -> `{BP,Gent}`); the value is
   only rewritten if **every** token resolves, otherwise it is left untouched.

**Decision-free guarantee.** Any value that does not resolve by the rules above is
**left untouched -- never guessed, never coerced to a nearby code**. These "unresolved"
values are tallied and written to the report under *"Unresolved values left untouched"*;
they are the candidates for clinical-team review. This makes the pass safe and
reversible: it only ever replaces a value with a canonical code the dictionary already
defines for that variable.

#### Information-preservation guarantee (two protections, no lossy merges)

Every change this step makes is a *representational* normalisation (encoding / case /
label->code / multi-select case) of the **same** value -- it never collapses two
genuinely distinct categories into one. This is guaranteed by two protections, needed
because a few variables have codes/labels that differ ONLY by case yet mean different
things (e.g. `tribe` `Ch`=Chewa vs `CH`=Chinyanja; `curprob` `Pn`=Pain vs
`PN`=Pneumonia; `plan` `CEF`=Ceftriaxone vs `Cef`=Ceftriaxone (surgical);
`hcwsig` two different staff members):

1. **Exact match always wins (existing codes are never merged).** Rule 1 returns any
   value that is already an exact canonical code unchanged, *before* any case-insensitive
   logic runs. So `PN` stays `PN` and `Pn` stays `Pn` -- two distinct valid codes are
   never folded together.
2. **Per-key ambiguity guard (no guessing on ambiguous case).** When building the
   case-insensitive lookups, any lowercased key that resolves to more than one distinct
   target is **dropped** (`build_ci()` keeps only unambiguous keys). For those variables
   case-folding is effectively disabled: a stray-case value such as `pn` is left
   *unresolved* (logged) rather than assigned to whichever spelling happened to be listed
   first. A scan of all dictionaries found 15 such variables; the guard removed **zero**
   legitimate harmonisations (the ambiguous stray-case values do not occur in the data),
   so it is pure safety at no cost.

Together these mean the pass improves consistency/cleanliness while preserving
information: distinct categories stay distinct, and anything the pass cannot resolve
unambiguously is left exactly as it was.

> **Caveat -- correctness rests on the dictionary being right.** The two protections
> guarantee the pass never *merges* distinct categories, but the *correctness* of each
> individual mapping (which canonical code a given raw code / label / boolean resolves
> to) is only as good as the `ValueMaps` sheet it reads. If a dictionary row maps a
> label to the wrong canonical code, this module will faithfully propagate that error.
> The 10 June 2026 audit validated the high-volume fields, but the dictionaries
> (especially rows added by the multi-version union and by `VALUEMAP_PATCHES`) should be
> reviewed as part of any release QA. Treat the dictionary as the single source of truth
> to get right; this module only applies it.

**Step 2 -- Post-dictionary recodes**

Handles mixed-version coding not covered by the dictionary:
- `harmonise_modedelivery()` -- converts text labels (e.g. `SVD`, `ECS`) to numeric codes for the `modedelivery` column, which is misnamed relative to its dictionary entry.
- `strip_thompson_labels()` -- strips ` = <label>` suffixes from Thompson score columns (e.g. `"0 = Normal"` -> `"0"`).

---

## Inputs

| Object | Description |
|--------|-------------|
| `df` | Data frame from Module 03 |
| `cfg$value_map_list` | Nested list: `question_key -> list(allowed_codes, canonical_codes, label_to_code, code_to_canonical)` -- built by Module 00 from the dictionary |

---

## Outputs

| Object / File | Description |
|---------------|-------------|
| `df` | Data frame with categorical values harmonised to canonical codes |
| `reports/04_dictionary_cleaning_report.txt` | Per-column list of replacements, deletions, **and unresolved values left untouched** (optional) |

---

## Key Functions

**`normalise_multiselect_encoding(df, value_map_list)`**

- Converts JSON-array encoded multi-select values (`["A","B"]`) to brace format (`{A,B}`).
- Targets columns in `value_map_list` plus the hardcoded `MULTISELECT_COLS` list.
- Logs number of conversions per column to the pipeline log.

**`clean_values_using_dict(df, value_map_list, report_filepath = NULL)`**

- Iterates over columns whose base name appears in `value_map_list`.
- Resolves each value to its canonical code (case-insensitive code/label match,
  raw->canonical, legacy boolean on yes/no fields, multi-select token case-folding).
- Leaves unresolved values untouched (decision-free) and logs them.
- Returns the cleaned data frame.
- Internal helper `resolve_token()` resolves a single scalar token to its canonical
  code or `NA` if it cannot be resolved unambiguously.

**`harmonise_modedelivery(df)`**

- Recodes text-label values for `modedelivery` / `modedelivery.value` to numeric codes.

**`strip_thompson_labels(df)`**

- Strips ` = <label>` suffixes from `thomp*` columns.

---

## Notes

- The `get_base_name()` helper strips `.value` and `.valuedischarge` suffixes before dictionary lookup, so both column forms are handled transparently.
- Only columns with a matching dictionary entry are processed; all other columns pass through unchanged.
- Values not recognised by the dictionary are left in place (decision-free) and logged under "Unresolved values left untouched" in the report; they are not silently removed or guessed here.
- **Coverage depends on the dictionary.** A value is only harmonised if its canonical code / raw code / label is present in the `ValueMaps` sheet. Historical values valid only in *older* Neotree form versions are added to the dictionary by the multi-version option-union step in `00_build_dictionary.r` (added 2026-06-12); without rebuilding the dictionaries, those legacy options remain unresolved here.
- **Information-preservation (no lossy merges).** The pass never collapses two distinct
  categories: exact existing codes are preserved, and case-folding is disabled for keys
  whose codes/labels are case-ambiguous. See *"Information-preservation guarantee (two
  protections)"* under **Logic > Step 1** for the full explanation.
- **Parked clinical decisions.** Genuinely ambiguous legacy values (e.g. `inorout` yes/no vs `In`/`Out`, `modedelivery` numeric `1`, `admittedfrom` `ER`) are intentionally left unresolved pending clinical-team confirmation; the per-run report lists them under *"Unresolved values left untouched"*, and `MANUAL.txt` (Appendix: Variable Issues Catalogue) records the known cases. `harmonise_modedelivery()` still recodes the *text* delivery labels to numeric as before; the numeric-vs-text reconciliation is a parked decision.
- Multi-select normalisation (Step 0) must run before dictionary validation (Step 1) so that brace-format values pass the `allowed_codes` check correctly.
- Known multi-select columns (`resus`, `delivinter`) are handled even if they are absent from the dictionary `value_map_list`, via the `MULTISELECT_COLS` constant in `normalise_multiselect_encoding()`.
