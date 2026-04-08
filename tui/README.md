# Skills Manager TUI

A keyboard-first terminal UI for Skills Manager, built with Blessed.

Current status:
- **Blessed** is the primary runtime
- **Ink** remains in the repo only as historical reference / backup

## Features

- three-panel terminal UI
- keyboard-first navigation
- local skill and plugin resource discovery
- Discover integration via [skills.sh](https://skills.sh/)
- install / uninstall / star
- version history, diff, and rollback
- open local source files and Discover source pages
- source filtering in Discover

## Run

```bash
npm install
npm run build
npm exec skills-manager
```

For local development:

```bash
npm start
```

To expose a global command from your machine:

```bash
npm link
skills-manager
```

## Keybindings

- `h/l` — switch panels
- `j/k` or `↑/↓` — move
- `g/G` — first / last
- `i` — install
- `x` — uninstall
- `s` — star / unstar
- `H` — local version history
- `d` — Discover detail overlay
- `o` — open source file
- `O` — open Discover source page
- `/` — search current view
- `f/F` — switch Discover source
- `0` — reset Discover source
- `r` — refresh Discover directory
- `R` — full refresh
- `q` / `Ctrl+C` — quit

## Notes

- Ghostty is normalized to `xterm-256color` on startup to avoid Blessed terminfo capability errors.
- Mouse interaction is intentionally disabled for now; the UI is keyboard-first.

## Docs

- `BLESSED.md` — implementation notes and behavior details
- `docs/blessed-engine.md` — engineering notes

## License

MIT
