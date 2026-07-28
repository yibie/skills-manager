# Changelog

All notable changes to Skills Manager will be documented in this file.

## [2.0.0] - 2026-07-29

### Changed

- Formalized the 2.0 release line around stable identity, collection recovery, takeover recovery, and honest prerelease packaging.
- Release automation now validates an existing main-line tag, tests and analyzes the macOS app, builds the TUI, and stages only an unsigned prerelease artifact for an environment-gated publish job.

### Fixed

- Collection mounting no longer hides missing or partially diverged state.
- Skills CLI takeover recovery now avoids unsafe repair when provenance is ambiguous.
- The maintained TUI dependency lock no longer contains known high-severity production advisories.
