# Neotree script metadata

## Purpose

This folder holds the metadata of the Neotree scripts (the app forms), one JSON file per script, in `zim-scripts/` and `mwi-scripts/`. It is read by:

| Reader | Use |
|--------|-----|
| `00_build_dictionary/00c_enrich_dictionary_from_scripts.r` | display labels, optional flags, skip conditions |
| `00_build_dictionary/00d_build_user_dictionary.r` | value lists of the user dictionaries |
| Module 16 (`16_na_reason_coding`) | skip conditions for the NA-reason codes |

Module 16 runs only when this folder exists. Without it the cleaned dataset is still written, but the NA-reason and NA-coded files are not.

## Getting the files

The script metadata is downloaded from the Neotree web editors, https://webeditor.neotree.org/ and https://zim-webeditor.neotree.org:10243/, with a Neotree account, and saved as `<script title> - metadata.json` in the folder of its country.

## Not in the repository

Some fields in the scripts list the names of health workers, and some script titles contain names. The script files are therefore not part of the published repository; `.gitignore` excludes everything in this folder except this file. The dictionary build does not write those names to any dictionary (see `00_build_dictionary/README.md`).
