# Phase 4: Multi-Agent Support Implementation Plan

> **Historical note (2026-04):** This plan references the earlier marketplace-era naming in some snippets. The current product uses **https://skills.sh/** for Discover; plugin-cache skills are only a local Library source.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CursorAdapter with .mdc format support, project-local skill discovery and one-click promotion to global, and "Install to Cursor" action from the skill detail view.

**Architecture:** `CursorAdapter` scans `~/.cursor/rules/*.mdc` and returns skills with `compatibleAgents: ["Cursor"]`; `SkillFormatConverter` converts bidirectionally between SKILL.md and .mdc; `ProjectScanner` scans a user-chosen project directory for `.mdc` and `SKILL.md` files; `ProjectSkillsView` lists them with a Promote button that copies to `~/.claude/skills/`.

**Tech Stack:** Swift 6, SwiftUI macOS 14+, Foundation, NSOpenPanel for project directory selection.

---

## Files

**Create:**
- `SkillsManager/Adapters/CursorAdapter.swift` — scans `~/.cursor/rules/*.mdc`, install/uninstall
- `SkillsManager/Services/SkillFormatConverter.swift` — SKILL.md ↔ .mdc bidirectional conversion
- `SkillsManager/Services/ProjectScanner.swift` — scans project dir for .mdc + SKILL.md
- `SkillsManager/Views/ProjectSkillsView.swift` — project skills list with Promote action

**Modify:**
- `SkillsManager/Models/Skill.swift:40-44` — add `.projectLocal(projectURL: URL)` to `SkillSource`
- `SkillsManager/Models/SidebarFilter.swift` — add `.project` case, title, icon
- `SkillsManager/Services/SkillStore.swift` — add CursorAdapter, project skill management, installToCursor, promoteSkill
- `SkillsManager/Views/ContentView.swift` — Open Project toolbar button, route `.project` to ProjectSkillsView
- `SkillsManager/Views/SidebarView.swift` — Project section with count when project is open
- `SkillsManager/Views/SkillDetailView.swift` — "Install to Cursor" + "Promote to Global" toolbar items
- `SkillsManager/Views/SkillListView.swift:12-14` — add `.project` to `.discover` case in filteredSkills

---

### Task 1: SkillSource.projectLocal + SidebarFilter.project

Foundation changes all later tasks depend on.

**Files:**
- Modify: `SkillsManager/Models/Skill.swift`
- Modify: `SkillsManager/Models/SidebarFilter.swift`
- Modify: `SkillsManager/Views/SkillDetailView.swift`
- Modify: `SkillsManager/Views/SkillListView.swift`

- [ ] **Step 1: Add `.projectLocal` to `SkillSource` in `Skill.swift`**

Replace lines 40-44:
```swift
enum SkillSource: Hashable, Codable, Sendable {
    case local
    case plugin(marketplace: String, pluginName: String)
    case symlinked
    case projectLocal(projectURL: URL)
}
```

- [ ] **Step 2: Add `.project` case to `SidebarFilter.swift`**

Replace full file:
```swift
import Foundation

enum SidebarFilter: Hashable, Sendable {
    case discover
    case all
    case installed
    case starred
    case trial
    case project
    case agent(String)
    case source(String)

    var title: String {
        switch self {
        case .discover:         "Discover"
        case .all:              "All Skills"
        case .installed:        "Installed"
        case .starred:          "Starred"
        case .trial:            "Trial"
        case .project:          "Project"
        case .agent(let name):  name
        case .source(let name): name
        }
    }

    var icon: String {
        switch self {
        case .discover:  "safari"
        case .all:       "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .starred:   "star.fill"
        case .trial:     "flask"
        case .project:   "folder"
        case .agent:     "cpu"
        case .source:    "shippingbox"
        }
    }
}
```

- [ ] **Step 3: Update `sourceBadge` in `SkillDetailView.swift` for `.projectLocal`**

Replace the `sourceBadge` computed property in `DetailContent` (around line 100):
```swift
private var sourceBadge: some View {
    let label: String
    switch skill.source {
    case .local:                          label = "Local"
    case .symlinked:                      label = "Symlinked"
    case .plugin(let marketplace, _):     label = marketplace.capitalized
    case .projectLocal:                   label = "Project"
    }
    return Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
}
```

- [ ] **Step 4: Handle `.project` in `SkillListView.swift` filteredSkills**

Replace the `filteredSkills` computed property (lines 11-35):
```swift
private var filteredSkills: [Skill] {
    switch filter {
    case .discover, .project:
        // ContentView routes these to dedicated views; SkillListView is never shown for these filters
        return []
    case .all:
        return skills
    case .installed:
        return skills.filter { $0.installState == .installed }
    case .starred:
        return skills.filter { $0.isStarred }
    case .trial:
        return skills.filter { $0.installState == .trial }
    case .agent(let name):
        return skills.filter { $0.compatibleAgents.contains(name) }
    case .source(let name):
        return skills.filter { skill in
            switch skill.source {
            case .local:                      name.lowercased() == "local"
            case .symlinked:                  name.lowercased() == "symlinked"
            case .plugin(let marketplace, _): marketplace.lowercased() == name.lowercased()
            case .projectLocal:               false
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify no errors**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add SkillsManager/Models/Skill.swift SkillsManager/Models/SidebarFilter.swift \
        SkillsManager/Views/SkillDetailView.swift SkillsManager/Views/SkillListView.swift
git commit -m "feat: add projectLocal source and project sidebar filter"
```

---

### Task 2: SkillFormatConverter

Pure utility — no state — for converting between SKILL.md and Cursor .mdc formats.

The .mdc format:
```
---
description: Short description
globs: ["*.ts", "*.tsx"]
alwaysApply: true
---

# Title

Body content here...
```

**Files:**
- Create: `SkillsManager/Services/SkillFormatConverter.swift`

- [ ] **Step 1: Create `SkillFormatConverter.swift`**

```swift
import Foundation

enum SkillFormatConverter {

    // MARK: - SKILL.md → .mdc

    /// Converts any Skill to Cursor .mdc format string.
    static func toMDC(skill: Skill) -> String {
        let body = SkillParser.parse(content: skill.markdownContent).body
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let globs: String
        if skill.tags.isEmpty {
            globs = "[]"
        } else {
            globs = "[\(skill.tags.map { "\"\($0)\"" }.joined(separator: ", "))]"
        }
        return """
        ---
        description: \(skill.description)
        globs: \(globs)
        alwaysApply: true
        ---

        \(body)
        """
    }

    // MARK: - .mdc → SKILL.md

    /// Converts .mdc content + a skill name to SKILL.md format string.
    static func toSKILLMD(name: String, mdcContent: String) -> String {
        let parsed = parseMDC(content: mdcContent)
        let description = parsed.frontmatter["description"] ?? ""
        let tags = parseGlobs(parsed.frontmatter["globs"] ?? "[]")
        let tagsLine = tags.isEmpty ? "" : "\ntags: \(tags.joined(separator: ", "))"
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ---
        name: \(name)
        description: \(description)\(tagsLine)
        compatible_agents: [Cursor, Claude Code]
        ---

        \(body)
        """
    }

    // MARK: - Parse .mdc

    /// Parses .mdc content into frontmatter dict and body string.
    /// .mdc frontmatter is identical in structure to SKILL.md frontmatter.
    static func parseMDC(content: String) -> (frontmatter: [String: String], body: String) {
        let result = SkillParser.parse(content: content)
        return (frontmatter: result.frontmatter, body: result.body)
    }

    // MARK: - Private

    private static func parseGlobs(_ raw: String) -> [String] {
        raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/SkillFormatConverter.swift
git commit -m "feat: add SkillFormatConverter for SKILL.md ↔ .mdc conversion"
```

---

### Task 3: CursorAdapter

Scans `~/.cursor/rules/*.mdc` and uses `SkillFormatConverter` for install.

**Files:**
- Create: `SkillsManager/Adapters/CursorAdapter.swift`

- [ ] **Step 1: Create `CursorAdapter.swift`**

```swift
import Foundation

struct CursorAdapter: AgentAdapter {

    let agentName = "Cursor"
    let agentIcon = "cursorarrow"

    var skillsDirectories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/rules")]
    }

    func scanSkills() async throws -> [Skill] {
        scanMDC(in: skillsDirectories[0], source: .local)
    }

    func installSkill(_ skill: Skill) throws {
        let rulesDir = skillsDirectories[0]
        let fm = FileManager.default
        if !fm.fileExists(atPath: rulesDir.path) {
            try fm.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        }
        let content = SkillFormatConverter.toMDC(skill: skill)
        let dest = rulesDir.appendingPathComponent("\(skill.name).mdc")
        try content.write(to: dest, atomically: true, encoding: .utf8)
    }

    func uninstallSkill(_ skill: Skill) throws {
        try FileManager.default.removeItem(at: skill.filePath)
    }

    // MARK: - Internal (also used by ProjectScanner)

    /// Scans a directory for *.mdc files, building Skill structs with the given source.
    func scanMDC(in directory: URL, source: SkillSource) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url -> Skill? in
            guard url.pathExtension == "mdc" else { return nil }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return buildSkill(fileURL: url, content: content, source: source)
        }
    }

    // MARK: - Private

    private func buildSkill(fileURL: URL, content: String, source: SkillSource) -> Skill? {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let parsed = SkillFormatConverter.parseMDC(content: content)
        let description = parsed.frontmatter["description"] ?? ""
        let rawGlobs = parsed.frontmatter["globs"] ?? "[]"
        let tags = rawGlobs
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }

        let idPrefix: String
        if case .projectLocal(let projectURL) = source {
            idPrefix = "project:\(projectURL.lastPathComponent):\(filename)"
        } else {
            idPrefix = "cursor:\(filename)"
        }

        return Skill(
            id: idPrefix,
            name: filename,
            displayName: filename,
            description: description,
            source: source,
            version: nil,
            filePath: fileURL,
            directoryPath: fileURL.deletingLastPathComponent(),
            compatibleAgents: ["Cursor"],
            tags: tags,
            markdownContent: content,
            frontmatter: parsed.frontmatter
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Adapters/CursorAdapter.swift
git commit -m "feat: add CursorAdapter for ~/.cursor/rules/*.mdc scanning and install"
```

---

### Task 4: ProjectScanner

Scans a user-selected project for `.mdc` files in `.cursor/rules/` and `SKILL.md` files anywhere in the project tree (depth-limited to 3 levels).

**Files:**
- Create: `SkillsManager/Services/ProjectScanner.swift`

- [ ] **Step 1: Create `ProjectScanner.swift`**

```swift
import Foundation

struct ProjectScanner {

    /// Scans a project directory for skill files.
    /// Returns .mdc files from .cursor/rules/ and SKILL.md files up to 3 levels deep.
    func scan(projectURL: URL) -> [Skill] {
        var skills: [Skill] = []

        // .cursor/rules/*.mdc
        let cursorRules = projectURL.appendingPathComponent(".cursor/rules")
        let cursorSkills = CursorAdapter().scanMDC(
            in: cursorRules,
            source: .projectLocal(projectURL: projectURL)
        )
        skills.append(contentsOf: cursorSkills)

        // SKILL.md anywhere in the project (depth ≤ 3)
        let skillMDFiles = findSKILLMD(in: projectURL, depth: 0, maxDepth: 3)
        let claudeSkills = skillMDFiles.compactMap {
            buildClaudeSkill(skillFile: $0, projectURL: projectURL)
        }
        skills.append(contentsOf: claudeSkills)

        return skills
    }

    // MARK: - Private

    private func findSKILLMD(in directory: URL, depth: Int, maxDepth: Int) -> [URL] {
        guard depth <= maxDepth else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for entry in entries {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            if isDir.boolValue {
                results.append(contentsOf: findSKILLMD(in: entry, depth: depth + 1, maxDepth: maxDepth))
            } else if entry.lastPathComponent == "SKILL.md" {
                results.append(entry)
            }
        }
        return results
    }

    private func buildClaudeSkill(skillFile: URL, projectURL: URL) -> Skill? {
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let parsed = SkillParser.parse(content: content)
        let fm = parsed.frontmatter
        let dirName = skillFile.deletingLastPathComponent().lastPathComponent
        let displayName = fm["name"] ?? dirName
        let description = fm["description"] ?? ""
        let rawTags = fm["tags"] ?? fm["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let agents = fm["compatible_agents"]
            .map { $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ?? ["Claude Code"]

        return Skill(
            id: "project:\(projectURL.lastPathComponent):\(dirName)",
            name: dirName,
            displayName: displayName,
            description: description,
            source: .projectLocal(projectURL: projectURL),
            version: fm["version"],
            filePath: skillFile,
            directoryPath: skillFile.deletingLastPathComponent(),
            compatibleAgents: agents,
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/ProjectScanner.swift
git commit -m "feat: add ProjectScanner for project-local skill discovery"
```

---

### Task 5: SkillStore — multi-adapter, project skills, installToCursor, promoteSkill

**Files:**
- Modify: `SkillsManager/Services/SkillStore.swift`

- [ ] **Step 1: Replace `SkillStore.swift` with the updated version**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {

    // MARK: - State

    var skills: [Skill] = []
    var discoverablePlugins: [MarketplacePlugin] = []
    var projectSkills: [Skill] = []
    var currentProjectURL: URL?
    var isLoading = false
    var isLoadingPlugins = false
    var isLoadingProject = false
    var isSyncing = false
    var errorMessage: String?

    // MARK: - Services

    private let adapter: ClaudeCodeAdapter
    private let cursorAdapter: CursorAdapter
    private let marketplaceService: MarketplaceService
    private let installService: InstallService

    init() {
        let ms = MarketplaceService()
        self.adapter = ClaudeCodeAdapter()
        self.cursorAdapter = CursorAdapter()
        self.marketplaceService = ms
        self.installService = InstallService(marketplaceService: ms)
    }

    // MARK: - Local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let claudeSkills = adapter.scanSkills()
            async let cursorSkills = cursorAdapter.scanSkills()
            skills = try await claudeSkills + (try await cursorSkills)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(records: [SkillRecord]) {
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.skillID, $0) })
        for index in skills.indices {
            let id = skills[index].id
            if let record = lookup[id] {
                skills[index].isStarred = record.isStarred
                skills[index].installState = InstallState(rawValue: record.installState) ?? .notInstalled
            }
        }
    }

    // MARK: - Marketplace plugins

    func reloadDiscoverablePlugins() async {
        isLoadingPlugins = true
        defer { isLoadingPlugins = false }
        let plugins = await marketplaceService.loadAllCachedPlugins()
        guard let installed = try? await marketplaceService.loadInstalledPlugins() else {
            discoverablePlugins = plugins
            return
        }
        discoverablePlugins = await marketplaceService.mergeInstallState(
            plugins: plugins,
            installed: installed
        )
    }

    func syncAndReloadPlugins() async {
        isSyncing = true
        defer { isSyncing = false }
        await marketplaceService.syncAllMarketplaces()
        await reloadDiscoverablePlugins()
    }

    func install(plugin: MarketplacePlugin) async {
        do {
            try await installService.install(plugin: plugin)
            await reloadDiscoverablePlugins()
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstall(plugin: MarketplacePlugin) async {
        do {
            try await installService.uninstall(plugin: plugin)
            await reloadDiscoverablePlugins()
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Skill-level install/uninstall (state only)

    func installSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .installed
        }
    }

    func uninstallSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .notInstalled
        }
    }

    // MARK: - Install to Cursor

    /// Converts the skill to .mdc format and writes it to ~/.cursor/rules/.
    func installToCursor(skill: Skill) async {
        do {
            try cursorAdapter.installSkill(skill)
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project skills

    func openProject(url: URL) async {
        currentProjectURL = url
        await loadProjectSkills()
    }

    func loadProjectSkills() async {
        guard let projectURL = currentProjectURL else {
            projectSkills = []
            return
        }
        isLoadingProject = true
        defer { isLoadingProject = false }
        projectSkills = ProjectScanner().scan(projectURL: projectURL)
    }

    /// Copies a project-local skill to ~/.claude/skills/.
    /// Converts .mdc → SKILL.md format if needed.
    func promoteSkill(_ skill: Skill) async {
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(skill.name)")
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: skillsDir.path) {
                try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            }
            let destFile = skillsDir.appendingPathComponent("SKILL.md")
            let content: String
            if skill.filePath.pathExtension == "mdc" {
                content = SkillFormatConverter.toSKILLMD(
                    name: skill.name,
                    mdcContent: skill.markdownContent
                )
            } else {
                content = try String(contentsOf: skill.filePath, encoding: .utf8)
            }
            try content.write(to: destFile, atomically: true, encoding: .utf8)
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/SkillStore.swift
git commit -m "feat: integrate CursorAdapter, add installToCursor and project skill support to SkillStore"
```

---

### Task 6: ProjectSkillsView + SidebarView + ContentView wiring

**Files:**
- Create: `SkillsManager/Views/ProjectSkillsView.swift`
- Modify: `SkillsManager/Views/SidebarView.swift`
- Modify: `SkillsManager/Views/ContentView.swift`

- [ ] **Step 1: Create `ProjectSkillsView.swift`**

```swift
import SwiftUI

struct ProjectSkillsView: View {
    let projectURL: URL?
    let skills: [Skill]
    let isLoading: Bool
    @Binding var selectedSkill: Skill?
    let onPromote: (Skill) async -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Scanning project...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if skills.isEmpty {
                emptyState
            } else {
                List(skills, selection: $selectedSkill) { skill in
                    ProjectSkillRow(
                        skill: skill,
                        onPromote: { Task { await onPromote(skill) } }
                    )
                    .tag(skill)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(projectURL.map { "Project: \($0.lastPathComponent)" } ?? "Project")
        .frame(minWidth: 260)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            projectURL == nil ? "No Project Open" : "No Skills Found",
            systemImage: projectURL == nil ? "folder" : "tray",
            description: Text(projectURL == nil
                ? "Click the folder button in the toolbar to open a project."
                : "No SKILL.md or .mdc files found in this project.")
        )
    }
}

// MARK: - Row

private struct ProjectSkillRow: View {
    let skill: Skill
    let onPromote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(skill.filePath.pathExtension == "mdc" ? ".mdc" : "SKILL.md")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(action: onPromote) {
                Label("Promote to Global", systemImage: "arrow.up.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var selected: Skill? = nil
    ProjectSkillsView(
        projectURL: URL(fileURLWithPath: "/Users/user/my-project"),
        skills: [],
        isLoading: false,
        selectedSkill: $selected,
        onPromote: { _ in }
    )
    .frame(width: 300, height: 400)
}
```

- [ ] **Step 2: Update `SidebarView.swift` — add Project section**

Add `projectSkillCount: Int = 0` and `currentProjectURL: URL? = nil` parameters, then add a Project section after the Sources section:

Replace the full file:
```swift
import SwiftUI

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    let skills: [Skill]
    var discoverableCount: Int = 0
    var projectSkillCount: Int = 0
    var currentProjectURL: URL?

    private var allCount: Int      { skills.count }
    private var installedCount: Int { skills.filter { $0.installState == .installed }.count }
    private var starredCount: Int  { skills.filter { $0.isStarred }.count }
    private var trialCount: Int    { skills.filter { $0.installState == .trial }.count }

    private var agentNames: [String] {
        Array(Set(skills.flatMap { $0.compatibleAgents })).sorted()
    }

    private var pluginSources: [String] {
        var sources = Set<String>()
        for skill in skills {
            if case .plugin(let marketplace, _) = skill.source {
                sources.insert(marketplace)
            }
        }
        return sources.sorted()
    }

    private func pluginCount(for marketplace: String) -> Int {
        skills.filter {
            if case .plugin(let m, _) = $0.source { return m == marketplace }
            return false
        }.count
    }

    private func agentCount(for agent: String) -> Int {
        skills.filter { $0.compatibleAgents.contains(agent) }.count
    }

    var body: some View {
        List(selection: $selectedFilter) {
            Section("Library") {
                SidebarRow(filter: .discover,   count: discoverableCount, selectedFilter: selectedFilter)
                SidebarRow(filter: .all,        count: allCount,          selectedFilter: selectedFilter)
                SidebarRow(filter: .installed,  count: installedCount,    selectedFilter: selectedFilter)
                SidebarRow(filter: .starred,    count: starredCount,      selectedFilter: selectedFilter)
                SidebarRow(filter: .trial,      count: trialCount,        selectedFilter: selectedFilter)
            }

            Section("Agents") {
                ForEach(agentNames, id: \.self) { agent in
                    SidebarRow(filter: .agent(agent), count: agentCount(for: agent), selectedFilter: selectedFilter)
                }
                if agentNames.isEmpty {
                    SidebarRow(filter: .agent("Claude Code"), count: 0, selectedFilter: selectedFilter)
                }
            }

            Section("Sources") {
                SidebarRow(filter: .source("Local"), count: skills.filter { $0.source == .local }.count, selectedFilter: selectedFilter)
                ForEach(pluginSources, id: \.self) { marketplace in
                    SidebarRow(filter: .source(marketplace.capitalized), count: pluginCount(for: marketplace), selectedFilter: selectedFilter)
                }
            }

            if currentProjectURL != nil {
                Section("Project") {
                    SidebarRow(filter: .project, count: projectSkillCount, selectedFilter: selectedFilter)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Skills")
    }
}

// MARK: - Row subview

private struct SidebarRow: View {
    let filter: SidebarFilter
    let count: Int
    let selectedFilter: SidebarFilter

    var body: some View {
        Label(filter.title, systemImage: filter.icon)
            .badge(count)
            .tag(filter)
    }
}

#Preview {
    @Previewable @State var filter: SidebarFilter = .all
    SidebarView(
        selectedFilter: $filter,
        skills: Skill.mockSkills,
        discoverableCount: 3,
        projectSkillCount: 2,
        currentProjectURL: URL(fileURLWithPath: "/Users/user/my-project")
    )
    .frame(width: 220, height: 600)
}
```

- [ ] **Step 3: Update `ContentView.swift` — Open Project button + route `.project`**

Replace the full file:
```swift
import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var skillRecords: [SkillRecord]

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sandboxSkill: Skill? = nil

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedFilter: $selectedFilter,
                skills: store.skills,
                discoverableCount: store.discoverablePlugins.count,
                projectSkillCount: store.projectSkills.count,
                currentProjectURL: store.currentProjectURL
            )
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    plugins: store.discoverablePlugins,
                    isLoading: store.isLoadingPlugins,
                    isSyncing: store.isSyncing,
                    onInstall: { plugin in await store.install(plugin: plugin) },
                    onUninstall: { plugin in await store.uninstall(plugin: plugin) },
                    onRefresh: { await store.syncAndReloadPlugins() }
                )
            } else if selectedFilter == .project {
                ProjectSkillsView(
                    projectURL: store.currentProjectURL,
                    skills: store.projectSkills,
                    isLoading: store.isLoadingProject,
                    selectedSkill: $selectedSkill,
                    onPromote: { skill in await store.promoteSkill(skill) }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onTry: { skill in sandboxSkill = skill }
                )
            }
        } detail: {
            SkillDetailView(
                skill: selectedSkill,
                onToggleStar: {
                    guard let skill = selectedSkill else { return }
                    let skillID = skill.id
                    let descriptor = FetchDescriptor<SkillRecord>(
                        predicate: #Predicate { $0.skillID == skillID }
                    )
                    if let record = try? modelContext.fetch(descriptor).first {
                        record.isStarred.toggle()
                    } else {
                        let record = SkillRecord(skillID: skillID, isStarred: true, installState: skill.installState.rawValue)
                        modelContext.insert(record)
                    }
                },
                onInstallToCursor: { skill in await store.installToCursor(skill: skill) },
                onPromote: { skill in await store.promoteSkill(skill) }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Select a project folder to scan for skills"
                    panel.prompt = "Open Project"
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await store.openProject(url: url) }
                    }
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                }
                .help("Open a project folder to scan for local skills")
            }
        }
        .sheet(item: $sandboxSkill) { skill in
            SandboxView(
                initialSkill: skill,
                availableSkills: store.skills,
                onKeep: { skill in await store.installSkill(skill) }
            )
        }
        .task {
            async let skills: Void = store.reloadSkills()
            async let plugins: Void = store.reloadDiscoverablePlugins()
            _ = await (skills, plugins)
            store.merge(records: skillRecords)
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SkillRecord.self, inMemory: true)
        .frame(width: 1100, height: 700)
}
```

Note: `SkillDetailView` now receives `onInstallToCursor` and `onPromote` — these will be added to its signature in Task 7.

Note: The build will show errors until Task 7 updates `SkillDetailView` to accept `onInstallToCursor` and `onPromote`. Do not verify the build here — proceed to Task 7, then verify.

- [ ] **Step 4: Commit**

```bash
git add SkillsManager/Views/ProjectSkillsView.swift \
        SkillsManager/Views/SidebarView.swift \
        SkillsManager/Views/ContentView.swift
git commit -m "feat: add ProjectSkillsView, wire Open Project button and project sidebar section"
```

---

### Task 7: SkillDetailView — Install to Cursor + Promote toolbar items

**Files:**
- Modify: `SkillsManager/Views/SkillDetailView.swift`

The toolbar needs two new conditional buttons:
- **"Install to Cursor"** — shown for skills that are `installed` and not already Cursor-only (i.e., `!skill.compatibleAgents.contains("Cursor") || skill.compatibleAgents.count > 1`). Calls `onInstallToCursor`.
- **"Promote to Global"** — shown only when `skill.source` is `.projectLocal`. Calls `onPromote`.

- [ ] **Step 1: Add `onInstallToCursor` and `onPromote` callbacks to `SkillDetailView`**

Replace the `SkillDetailView` struct declaration and its properties (lines 4-26):
```swift
struct SkillDetailView: View {
    let skill: Skill?
    var onToggleStar: () -> Void = {}
    var onInstallToCursor: (Skill) async -> Void = { _ in }
    var onPromote: (Skill) async -> Void = { _ in }

    @State private var showVersionHistory = false
    @State private var commits: [GitCommit] = []

    var body: some View {
        Group {
            if let skill {
                DetailContent(
                    skill: skill,
                    showVersionHistory: $showVersionHistory,
                    commits: $commits,
                    onToggleStar: onToggleStar,
                    onInstallToCursor: { Task { await onInstallToCursor(skill) } },
                    onPromote: { Task { await onPromote(skill) } }
                )
            } else {
                placeholder
            }
        }
        .frame(minWidth: 320)
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Select a Skill",
            systemImage: "square.grid.2x2",
            description: Text("Choose a skill from the list to view its details.")
        )
    }
}
```

- [ ] **Step 2: Add the new callbacks to `DetailContent`**

Replace `DetailContent` struct declaration and its properties (lines 38-44):
```swift
private struct DetailContent: View {
    let skill: Skill
    @Binding var showVersionHistory: Bool
    @Binding var commits: [GitCommit]
    let onToggleStar: () -> Void
    let onInstallToCursor: () -> Void
    let onPromote: () -> Void
```

- [ ] **Step 3: Add "Install to Cursor" and "Promote" toolbar items in `DetailContent.toolbarContent`**

Replace the `toolbarContent` `@ToolbarContentBuilder` (lines 156-179):
```swift
@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
        Button {
            onToggleStar()
        } label: {
            Label(
                skill.isStarred ? "Unstar" : "Star",
                systemImage: skill.isStarred ? "star.fill" : "star"
            )
        }
        .foregroundStyle(skill.isStarred ? .yellow : .secondary)
        .help(skill.isStarred ? "Remove from starred" : "Add to starred")
    }

    ToolbarItem(placement: .primaryAction) {
        Button {
            showVersionHistory = true
        } label: {
            Label("Version History", systemImage: "clock.arrow.circlepath")
        }
        .help("Show version history")
    }

    // Show "Install to Cursor" for installed Claude Code skills
    if skill.installState == .installed && !skill.compatibleAgents.contains("Cursor") {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onInstallToCursor()
            } label: {
                Label("Install to Cursor", systemImage: "cursorarrow.rays")
            }
            .help("Convert and install this skill to ~/.cursor/rules/")
        }
    }

    // Show "Promote" only for project-local skills
    if case .projectLocal = skill.source {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onPromote()
            } label: {
                Label("Promote to Global", systemImage: "arrow.up.circle")
            }
            .help("Copy this skill to ~/.claude/skills/")
        }
    }
}
```

- [ ] **Step 4: Build to verify**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 5: Manual smoke test**

Run the app and verify:
1. Skills from `~/.cursor/rules/` appear in the skill list under "Agents → Cursor" sidebar filter
2. Clicking "Open Project" (folder icon in toolbar) opens a directory picker
3. After selecting a project with `.cursor/rules/*.mdc` or `SKILL.md` files, "Project" section appears in sidebar
4. Project skills show "Promote to Global" button in list row and toolbar
5. An installed Claude Code skill shows "Install to Cursor" in the detail toolbar

- [ ] **Step 6: Commit**

```bash
git add SkillsManager/Views/SkillDetailView.swift
git commit -m "feat: add Install to Cursor and Promote to Global actions in SkillDetailView"
```

---

## Summary

| Task | Files | What it does |
|------|-------|-------------|
| 1 | Skill.swift, SidebarFilter.swift, SkillDetailView.swift, SkillListView.swift | Foundation: projectLocal source + project filter |
| 2 | SkillFormatConverter.swift | SKILL.md ↔ .mdc conversion |
| 3 | CursorAdapter.swift | Scan ~/.cursor/rules, install/uninstall |
| 4 | ProjectScanner.swift | Scan project for .mdc + SKILL.md |
| 5 | SkillStore.swift | Multi-adapter, installToCursor, promoteSkill |
| 6 | ProjectSkillsView.swift, SidebarView.swift, ContentView.swift | UI wiring |
| 7 | SkillDetailView.swift | Install to Cursor + Promote toolbar buttons |
