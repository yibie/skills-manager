# Contributing

Issues and PRs are welcome. This document covers the development setup and the conventions that keep the project easy to review.

## Repository layout

- `SkillsManager/` — the macOS app (SwiftUI, Swift 6, SwiftData, macOS 14+)
  - `Models/` — data models and settings
  - `Services/` — business logic (SkillStore is the central state hub)
  - `Adapters/` — agent registry and per-agent scanners
  - `Views/` — SwiftUI views
- `tui/` — the terminal UI (blessed; see `tui/docs/blessed-engine.md` before touching keyboard handling)
- `Tests/` — swift-testing suites for the app

## Build and run

The app:

```bash
open SkillsManager.xcodeproj   # then ⌘R
```

Run `xcodegen generate` after changing `project.yml`.

The TUI:

```bash
cd tui
npm install
npm exec skills-manager
```

## Tests

Run the full test suite before opening a PR:

```bash
xcodebuild \
  -project SkillsManager.xcodeproj \
  -scheme SkillsManager \
  -destination 'platform=macOS' \
  test
```

If you change install/uninstall, scanning, or settings behavior, add or update a test in `Tests/SkillsManagerTests`.

## Conventions

- Keep file system writes inside services (`SkillStore`, `SymlinkInstaller`, …); views stay free of direct I/O, force unwraps, and `try!`.
- API keys and other secrets go to the Keychain via `KeychainService` — never UserDefaults.
- The TUI follows the blessed rules in `CLAUDE.md`: let blessed lists handle their own navigation, don't maintain a parallel `selectedIndex`.
- Update `README.md` when you add, remove, or change user-facing behavior — the README is treated as a promise about what the code actually does.

## Pull requests

- Keep PRs focused: one fix or one feature per PR.
- Describe user-visible changes in the PR description, and note any changes to supported agents or install behavior.
