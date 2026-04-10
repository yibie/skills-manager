# Skills Manager — Development Progress

## Phase 1 ✅ COMPLETE (prior session)

MVP: local skill management + version tracking.

- SwiftUI three-column NavigationSplitView (Sidebar / SkillList / Detail)
- `ClaudeCodeAdapter`: scans `~/.claude/skills/` and `~/.claude/plugins/`
- `SkillParser`: parses SKILL.md with YAML frontmatter
- `SkillStore` (@Observable @MainActor): central state, merges SwiftData records
- `SkillDetailView`: Markdown preview, Open in Editor (NSWorkspace), version history
- `VersionHistoryView` + `GitService`: git log, diff, rollback
- `FileWatcher` (FSEvents): live-reload on file change
- Star/favorite with SwiftData persistence (`SkillRecord`)
- Inline action buttons (Install / Uninstall / Try stub / More menu)
- `SidebarFilter`: All, Installed, Starred, Trial, Agent, Source

---

## Phase 2 ✅ COMPLETE

Discover foundations + local plugin-cache management.

### Delivered
- Initial Discover plumbing in the macOS app
- Local plugin-cache scanning so plugin-bundled skills can be managed as normal local entries once present on disk
- Install / uninstall flows for local skill management
- `SidebarFilter.discover` routing in `ContentView`
- `SkillStore` wired to real filesystem data and SwiftData state
- Proper startup loading and error alert binding in `ContentView`

### Current status after later refactors
- Discover no longer uses the Claude plugin index as its source of truth
- Discover now loads from `https://skills.sh/`
- Plugin-contained skills are still manageable locally after scanning, but they are not used as Discover results
- Star toggle persists via SwiftData `SkillRecord`

---

## Phase 3 ✅ COMPLETE

Try Sandbox: LLM-powered skill testing with A/B slot comparison.

### Delivered
- `AppSettings` enum: `claudeApiKeyKey`, `sandboxModelKey`, `defaultModel`
- `SettingsView`: macOS Settings scene (⌘,), `SecureField` for API key, model picker (haiku/sonnet/opus)
- `LLMService` actor: Claude Messages API (`/v1/messages`), POST with `x-api-key` + `anthropic-version: 2023-06-01`
- `SandboxSlot` @Observable class: per-slot state (`skill`, `output`, `isLoading`, `error`)
- `SandboxView`: prompt input + Run (⌘↵), horizontal scroll of SlotCards, Add Slot, Keep/Discard
- Try button in `SkillListView` → `onTry` callback → `ContentView` sets `sandboxSkill` → `.sheet` opens SandboxView

### Key design decisions
- API key stored in UserDefaults (@AppStorage) — intentional MVP tradeoff, comment documents Keychain path
- LLM calls: independent `Task` per slot, each suspends at URLSession, truly concurrent
- `@AppStorage` properties captured as locals before first `await` (Swift 6 MainActor isolation)

---

## TUI Track ✅ COMPLETE (2026-04)

Blessed-based terminal UI is now considered complete for the current product scope.

### Delivered
- Blessed TUI is the primary terminal implementation; the older Ink version is kept only as historical reference and is no longer the target runtime
- Three-panel keyboard-first layout (Sidebar / List / Detail) with focus switching and stable cursor behavior
- Discover integration via `https://skills.sh/` with async detail loading, source filtering, install flow, and source-page opening
- Local library management: install, uninstall, star, version history, diff, rollback, source-file opening, full refresh
- Search overlay, discover detail overlay, version history overlay, and agent selection overlay
- Local vs plugin-source differentiation in both sidebar and list/detail views
- Expanded agent/resource scanning in the TUI layer:
  - Claude Code local skills + plugin cache
  - Codex local skills + plugin cache
  - Pi skills
  - Pi package resources and extensions, surfaced in the UI as plugin resources
- Keyboard semantics normalized (`i` install, `x` uninstall, `o` open source file, `O` open discover source page, `R` full refresh)
- Mouse interactions disabled intentionally to avoid partial or misleading behavior; current TUI is keyboard-first by design

### Scope decision
- TUI is complete for the current phase and should be treated as a maintained Blessed implementation, not an active Ink migration project
- Future work can improve polish or add new product capabilities, but the core TUI implementation itself is no longer considered in-progress

---

## Phase 4 — PENDING

Multi-agent support per original spec:
- `CursorAdapter` + skill format conversion (.mdc)
- Project-local skills discovery and promotion to global
- Other agent adapter extensions (Copilot CLI, Codex, Gemini CLI)

---

## Architecture snapshot (current)

```
SkillsManagerApp.swift          — App entry, ModelContainer, Settings scene
Models/
  Skill.swift                   — Skill struct + SkillRecord @Model + SkillSource + InstallState
  DiscoverSkill.swift           — DiscoverSkill model for skills.sh entries
  SidebarFilter.swift           — SidebarFilter enum (all/installed/starred/trial/agent/source/discover)
  AppSettings.swift             — API key constants
  SandboxSlot.swift             — @Observable slot state for Try Sandbox
  Skill+Mock.swift              — #if DEBUG mock data for previews
Adapters/
  ClaudeCodeAdapter.swift       — scans ~/.claude/skills/ + plugins/
Services/
  SkillStore.swift              — @Observable @MainActor central state
  SkillsDirectoryService.swift  — skills.sh directory + detail loading
  InstallService.swift          — legacy file retained as a note; Discover installs now use `npx skills add ... --skill ...`
  LLMService.swift              — Claude Messages API actor
  GitService.swift              — git log/diff/rollback via Process
  FileWatcher.swift             — FSEvents file change detection
  SkillParser.swift             — SKILL.md + YAML frontmatter parsing
Views/
  ContentView.swift             — NavigationSplitView, sheet routing, error alert
  SidebarView.swift             — sidebar with counts
  SkillListView.swift           — filtered list + action buttons
  DiscoverView.swift            — skills.sh browse, search, source filter, shared detail column
  SkillDetailView.swift         — markdown preview, star, version history
  SandboxView.swift             — LLM sandbox with slot comparison
  SettingsView.swift            — API key + model config
  VersionHistoryView.swift      — git commit list + diff
```
