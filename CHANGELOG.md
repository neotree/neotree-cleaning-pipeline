# Changelog

Releases are tagged in the repository.

## [v2.0.1]

Module 05 reads configured fields from their label column into the value column when the value column holds no valid value (`LABEL_VALUE_RULES` in `00_setup/00_setup.r`). The rule is set for the number of antenatal care visits in Malawi admissions. It adds the columns `antenatalcare_source` and `antenatalcare_category` to the cleaned Malawi admissions file. A new test, `tests/test_label_value_recovery.r`, covers the rule. The Malawi admissions dictionaries and the Malawi user dictionary list the two new columns.

The dictionary build accepts data-key files whose names start with a country prefix, such as `mwi-data-keys-usage.xlsx`, and stops if a country folder holds more than one file of a kind.

## [v2.0.0]

First release of this repository. It contains the cleaning modules, the dictionary build scripts, the dictionaries, the tests and the documentation.
