# Build asset contract refactor

Scope: behavior-preserving build structure; no comment cleanup or test pruning.

## Problems and decisions

- Put the required bundle asset list and validation in one standalone command.
  - `build.sh` owns a list of two JSON assets and the QueryConfigs directory.
  - `scripts/validate-sdk26.sh` repeats the same list independently.
  - `scripts/verify_macho_installation.sh` repeats it a third time.
  - Adding a mandatory bundle asset currently requires editing all three callers.
- Keep validation policy explicit at the call site.
  - Source checks require regular JSON files, including empty files, matching existing behavior.
  - Installed-package checks require nonempty JSON files, matching existing behavior.
  - Both require QueryConfigs to be a directory.
  - Installed-package gzip and build provenance checks remain package-specific.

## Design

`scripts/verify_bundle_assets.sh BUNDLE_DIR [--nonempty]` owns the contract.
It validates source bundles by default and accepts `--nonempty` for installed
packages. Missing-asset failures use a common diagnostic and a nonzero exit.
Callers retain their workflow setup, successful validation messages, and all
validation beyond the common asset contract.

## Deliberately retained boundaries

SDK configuration spans Make, shell and GitHub Actions. It was inspected but
is not combined with assets: SDK selection and bundle contents change for
different reasons. Package provenance and Mach-O checks also remain independent.
