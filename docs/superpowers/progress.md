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

Marketplace discovery + install/uninstall.

### Delivered
- `MarketplacePlugin` model (`PluginSourceType`: localPath, gitURL, gitSubdir, remoteURL)
- `MarketplaceService` actor: reads `~/.claude/plugins/known_marketplaces.json` + local marketplace cache; `syncAllMarketplaces()` fetches from GitHub Contents API in parallel
- `InstallService` actor: install (localPath copy or git clone), uninstall, updates `installed_plugins.json`
- `DiscoverView`: search + category chips, Install/Uninstall per plugin, Refresh button (GitHub sync)
- `SidebarFilter.discover` → routes to DiscoverView in ContentView
- `SkillStore` wired to real data: `reloadSkills()`, `reloadDiscoverablePlugins()`, `install(plugin:)`, `uninstall(plugin:)`
- `ContentView` rewritten: real SkillStore, parallel startup load, proper error alert binding

### Bugs fixed post-completion
- Star toggle didn't persist → now writes to SwiftData `SkillRecord` via ContentView callback
- Discover sidebar count hardcoded 0 → wired to `store.discoverablePlugins.count`
- Alert used `.constant()` binding → replaced with real `Binding(get:set:)`
- `installService` was not `private` → fixed
- `.discover` case in `SkillListView.filteredSkills` returned full list → returns `[]` with comment

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

## Phase 4 — PENDING

Multi-agent support per original spec:
- `CursorAdapter` + skill format conversion (.mdc)
- Project-local skills discovery and promotion to global
- Other agent adapter extensions (Copilot CLI, Codex, Gemini CLI)

---

## Architecture snapshot (as of Phase 3)

```
SkillsManagerApp.swift          — App entry, ModelContainer, Settings scene
Models/
  Skill.swift                   — Skill struct + SkillRecord @Model + SkillSource + InstallState
  MarketplacePlugin.swift       — MarketplacePlugin + PluginSourceType + InstalledPluginsFile
  SidebarFilter.swift           — SidebarFilter enum (all/installed/starred/trial/agent/source/discover)
  AppSettings.swift             — API key constants
  SandboxSlot.swift             — @Observable slot state for Try Sandbox
  Skill+Mock.swift              — #if DEBUG mock data for previews
Adapters/
  ClaudeCodeAdapter.swift       — scans ~/.claude/skills/ + plugins/
Services/
  SkillStore.swift              — @Observable @MainActor central state
  MarketplaceService.swift      — local cache read + GitHub API sync
  InstallService.swift          — plugin install/uninstall, installed_plugins.json
  LLMService.swift              — Claude Messages API actor
  GitService.swift              — git log/diff/rollback via Process
  FileWatcher.swift             — FSEvents file change detection
  SkillParser.swift             — SKILL.md + YAML frontmatter parsing
Views/
  ContentView.swift             — NavigationSplitView, sheet routing, error alert
  SidebarView.swift             — sidebar with counts
  SkillListView.swift           — filtered list + action buttons
  DiscoverView.swift            — marketplace browse, search, category filter
  SkillDetailView.swift         — markdown preview, star, version history
  SandboxView.swift             — LLM sandbox with slot comparison
  SettingsView.swift            — API key + model config
  VersionHistoryView.swift      — git commit list + diff
```
