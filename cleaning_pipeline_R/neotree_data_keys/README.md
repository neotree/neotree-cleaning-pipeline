# Data-key exports

## Purpose

This folder holds the data-key exports of the Neotree web editors. The dictionary build (`00_build_dictionary/00_build_dictionary.r`) reads them to build the dictionaries in `dictionaries/` and `user_dictionaries/`.

## Getting the files

The exports are downloaded from the Neotree web editors, https://webeditor.neotree.org/ and https://zim-webeditor.neotree.org:10243/, with a Neotree account. Each country has its own folder:

| Folder | Files read by the build |
|--------|-------------------------|
| `downloaded/neotree_data_keys_zimbabwe/` | `data-keys-metadata.json`, `data-keys-usage.xlsx` |
| `downloaded/neotree_data_keys_malawi/` | `data-keys-metadata.json`, `data-keys-usage.xlsx` |

A file name may start with a prefix such as `zim-` or `mwi-` (for example `mwi-data-keys-usage.xlsx`); each folder must hold one file of each kind. `data-keys-metadata.xlsx`, also part of the export, is not read. The folder names are set in `DOWNLOADED_KEYS_BASE` and `COUNTRY_FOLDERS` in `00_build_dictionary/00_build_dictionary.r`.

## Not in the repository

Some answer options in the exports are the names of health workers. The exports are therefore not part of the published repository; `.gitignore` excludes everything in this folder except this file. The dictionary build does not write those names to any dictionary (see `00_build_dictionary/README.md`).
