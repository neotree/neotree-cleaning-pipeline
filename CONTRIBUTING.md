# Contributing

Thanks for helping improve the Neotree Cleaning Pipeline.

## Ground rules

1. **Never commit data or secrets.** No patient-level records, no free-text
   identifiers, no database passwords, no Artifactory tokens. The `.gitignore`
   enforces the common cases, but check your staged changes before committing
   (`git diff --cached`).
2. **Keep the two installation methods in sync.** If you change the package set,
   update both `install_packages.r` (CRAN) and `install_packages_dsh.r`
   (Artifactory).
3. **Document module changes** in that module's `README.md`.
4. **Regenerate `MANUAL.txt`** after editing any README, or the compiled manual
   and the source documentation drift apart.

## Workflow

1. Branch from the default branch.
2. Make your change; run the affected pipeline end-to-end on test data.
3. Keep paths relative or configurable — no machine-specific absolute paths
   (e.g. `/Users/...`, `/Volumes/...`) in committed code.
4. Open a pull request describing the change and how you tested it.

## Style

- R scripts use `snake_case` for objects and 2-space indentation, matching the
  existing modules.
- Comments explain *why*, not *what*.
- UK English in prose; ASCII-only in code.

## Relationship to the sample maker

Downstream joining and subsampling lives in
[neotree-sample-maker](https://github.com/neotree/neotree-sample-maker). The
coupling is deliberately loose: this pipeline writes cleaned datasets to
`output/`, and the sample maker reads whatever it is given.

If you change the output directory naming convention
(`{country}_{source}_{dataset}_{date}/`), update `modules/pipeline_file_resolver.R`
and `modules/file_finder.R` in that repository to match.
