# Changelog

Releases are tagged in the repository.

## [v2.0.3]

HIV and syphilis clinical fields are kept in the cleaned files. The web-editor data keys flag them confidential, and Module 00a removes every confidential column; until now the dictionary build cleared the flag only for six fields in Malawi admissions and discharges. `HIV_CLINICAL_KEYS` in `00_build_dictionary/00_build_dictionary.r` now lists the fields for both countries (Malawi: `hivtestresult`, `hivtestresultdc`, `datehivtest`, `haart`, `lengthhaart`, `mathivstat`; Zimbabwe: `hivtestresult`, `datehivtest`, `haart`, `lengthhaart`, `mahaart`, `hivmeds`, `vlnumber`, `hivpcrinfr`, `isthebabyhivexposed`, `mathivpr`, `dnapcrresult`, `matpart`, `matrprr`, `matrprt`, `prophylaxis`) and clears the flag in admissions, discharges, PHC admissions and PHC discharges. Zimbabwe `ethnicity2` is also kept (`OTHER_KEPT_KEYS`). Names, contact details and dates of birth stay confidential. The Zimbabwe and Malawi PHC dictionaries and both user dictionaries are rebuilt; no other dictionary changes. The dictionary build warns when a field whose name looks HIV- or syphilis-related is still confidential. A new test, `tests/test_hiv_fields_kept.r`, covers the dictionaries.

## [v2.0.2]

Module 10 has an episode mode, set by `DEDUP_MODE` in `00_setup/00_setup.r` and `RUN_ALL_DEDUP_MODE` in `run_all.r`; it is the default. It applies to admissions, discharges, PHC admissions and discharges, Zimbabwe maternal outcomes and Malawi combined maternity outcomes. Rows with the same `uid` and facility are merged only when they are within one hour and sex, birth weight, gestation and the readmission flag do not disagree (in the maternal files, also birth outcome and birth order). Every row gets `baby_id` (the `uid` plus a letter); admissions and discharges also get `stay_no`, and discharges `stay_form_primary`. The columns `dedup_rows_merged`, `dedup_basis` and `dedup_flag` record what was merged and which rows need review. Discharges are linked to admission stays through a key file, `<stem>_episode_keys.rds`, written by the admissions run. Modules 11, 12, 14, 15 and 16 identify rows by `uid`, facility and `uniquekey` in episode mode. `DEDUP_MODE <- "current"` restores the previous rule. A new test, `tests/test_dedup_episode.r`, covers the rule.

## [v2.0.1]

Module 05 reads configured fields from their label column into the value column when the value column holds no valid value (`LABEL_VALUE_RULES` in `00_setup/00_setup.r`). The rule is set for the number of antenatal care visits in Malawi admissions. It adds the columns `antenatalcare_source` and `antenatalcare_category` to the cleaned Malawi admissions file. A new test, `tests/test_label_value_recovery.r`, covers the rule. The Malawi admissions dictionaries and the Malawi user dictionary list the two new columns.

The dictionary build accepts data-key files whose names start with a country prefix, such as `mwi-data-keys-usage.xlsx`, and stops if a country folder holds more than one file of a kind.

## [v2.0.0]

First release of this repository. It contains the cleaning modules, the dictionary build scripts, the dictionaries, the tests and the documentation.
