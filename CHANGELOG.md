# Changelog

All notable changes to Skills Manager will be documented in this file.

## [2.0.0] - 2026-08-04

### Changed

- Added the Collections Control Center and the `Library → Collection → Mount` lifecycle, including per-agent mount intent and explicit reapply behavior.
- Added agent home pages, conflict diagnosis, full-site Discover search, provider-aware updates and removal, and shared stars across the macOS and Blessed terminal interfaces.
- Made OpenCode a first-class XDG-aware install target and expanded registry-based detection across supported coding agents.
- Formalized the 2.0 release line around stable identity, collection recovery, takeover recovery, and honest prerelease packaging.
- Release automation now validates an existing main-line tag, tests and analyzes the macOS app, builds the TUI, and stages only an unsigned prerelease artifact for an environment-gated publish job.

### Fixed

- Shared roots such as `~/.agents/skills` are no longer attributed to OpenClaw, so Codex and other agents retain their real ownership labels.
- Copy ID, Copy Path, and Show in Finder actions now perform their advertised clipboard and Finder operations from both row and context menus.
- Collection mounting no longer hides missing or partially diverged state.
- Skills CLI takeover recovery now avoids unsafe repair when provenance is ambiguous.
- The maintained TUI dependency lock no longer contains known high-severity production advisories.
