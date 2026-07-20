# Contributing

Thanks for helping improve the Neotree Data Pipeline.

## Ground rules

1. **Never commit data or secrets.** No patient-level records, no free-text
   identifiers, no database passwords, no Artifactory tokens. The `.gitignore`
   enforces the common cases, but check your staged changes before committing
   (`git diff --cached`).
2. **Keep the two installation methods in sync.** If you change the package set,
   update both `install_packages.r` (CRAN) and `install_packages_dsh.r`
   (Artifactory) in the affected pipeline.
3. **Document module changes** in the relevant module `README.md` (cleaning) or
   `README_files/` (sample maker).

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
