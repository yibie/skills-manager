# Phase 5: Universal Agent Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support 40+ coding agents (Cursor, Windsurf, Gemini CLI, GitHub Copilot, Codex, etc.) using the same canonical `.agents/skills/` + symlink architecture as vercel-labs/skills.

**Architecture:** Replace the current two-adapter approach (ClaudeCodeAdapter + CursorAdapter) with a data-driven `AgentRegistry` of 40+ agent definitions. A new `UniversalAdapter` scans the canonical `~/.agents/skills/` directory and each installed agent's own skills dir, deduplicates by skill name, and tracks which agents have each skill. Install writes to canonical location then creates symlinks to all target agent dirs. The existing ClaudeCodeAdapter (which also scans `~/.claude/plugins/cache/`) is kept; the old CursorAdapter (.mdc format) is replaced by a standard SKILL.md entry in the registry. SkillDetailView gets an "Install to Agent" multi-select action replacing the hardcoded "Install to Cursor" button.

**Tech Stack:** Swift 6, SwiftUI macOS 14+, Foundation (FileManager, symlinks)

---

## Files

**Create:**
- `SkillsManager/Adapters/AgentRegistry.swift` — 40+ agent definitions (name, id, skillsDir, globalSkillsDir, detectInstalled)
- `SkillsManager/Adapters/UniversalAdapter.swift` — scans canonical + all installed agent dirs, deduplicates, returns skills with `compatibleAgents` list
- `SkillsManager/Services/SymlinkInstaller.swift` — writes SKILL.md to canonical dir, creates symlinks to each target agent dir

**Modify:**
- `SkillsManager/Models/Skill.swift` — add `canonicalPath: URL?` field for symlink management
- `SkillsManager/Services/SkillStore.swift` — replace two hardcoded adapters with UniversalAdapter + ClaudeCodeAdapter (for plugin cache); add `installSkillToAgents(_:agents:)` action
- `SkillsManager/Views/SkillDetailView.swift` — replace hardcoded "Install to Cursor" toolbar button with "Install to Agent…" sheet listing detected agents
- `SkillsManager/Views/InstallToAgentView.swift` (new) — multi-select sheet for picking target agents

**Remove after Task 5:**
- `SkillsManager/Adapters/CursorAdapter.swift` — superseded by registry entry + UniversalAdapter

---

### Task 1: AgentRegistry — 40+ agent definitions

Pure data file. No filesystem access. No dependencies on other new files.

**Context:** Vercel's `agents.ts` defines each agent with `skillsDir` (project-relative) and `globalSkillsDir` (absolute). We only need the global paths (macOS app, no per-project scope). Detection = check if the agent's config dir exists in `~`.

**Files:**
- Create: `SkillsManager/Adapters/AgentRegistry.swift`

- [ ] **Step 1: Create `AgentRegistry.swift`**

```swift
import Foundation

struct AgentDefinition: Sendable {
    let id: String           // e.g. "cursor", "gemini-cli"
    let displayName: String  // e.g. "Cursor", "Gemini CLI"
    let icon: String         // SF Symbol name
    /// Absolute path to the agent's global skills directory.
    let globalSkillsDir: URL
    /// Path that must exist in HOME for us to consider this agent installed.
    let detectPath: String   // relative to homeDir, e.g. ".cursor"
}

enum AgentRegistry {

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let xdgConfig: URL = {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdg)
        }
        return home.appendingPathComponent(".config")
    }()

    /// The canonical "universal" directory all agents share.
    static var canonicalGlobalSkillsDir: URL {
        xdgConfig.appendingPathComponent("agents/skills")
    }

    static let all: [AgentDefinition] = [
        // Universal agents — use canonical dir as their global skills dir too
        .init(id: "amp",            displayName: "Amp",             icon: "bolt",             globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".config/amp"),
        .init(id: "cline",          displayName: "Cline",           icon: "terminal",         globalSkillsDir: home.appendingPathComponent(".agents/skills"),               detectPath: ".cline"),
        .init(id: "codex",          displayName: "Codex",           icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: home.appendingPathComponent(".codex/skills"),  detectPath: ".codex"),
        .init(id: "cursor",         displayName: "Cursor",          icon: "cursorarrow",      globalSkillsDir: home.appendingPathComponent(".cursor/skills"),               detectPath: ".cursor"),
        .init(id: "deepagents",     displayName: "Deep Agents",     icon: "brain",            globalSkillsDir: home.appendingPathComponent(".deepagents/agent/skills"),     detectPath: ".deepagents"),
        .init(id: "firebender",     displayName: "Firebender",      icon: "flame",            globalSkillsDir: home.appendingPathComponent(".firebender/skills"),           detectPath: ".firebender"),
        .init(id: "gemini-cli",     displayName: "Gemini CLI",      icon: "g.circle",         globalSkillsDir: home.appendingPathComponent(".gemini/skills"),               detectPath: ".gemini"),
        .init(id: "github-copilot", displayName: "GitHub Copilot",  icon: "copilot",          globalSkillsDir: home.appendingPathComponent(".copilot/skills"),              detectPath: ".copilot"),
        .init(id: "kimi-cli",       displayName: "Kimi Code CLI",   icon: "k.circle",         globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".kimi"),
        .init(id: "replit",         displayName: "Replit",          icon: "r.circle",         globalSkillsDir: xdgConfig.appendingPathComponent("agents/skills"),          detectPath: ".replit"),
        .init(id: "warp",           displayName: "Warp",            icon: "terminal.fill",    globalSkillsDir: home.appendingPathComponent(".agents/skills"),               detectPath: ".warp"),
        // Agent-specific dirs
        .init(id: "antigravity",    displayName: "Antigravity",     icon: "arrow.up.circle",  globalSkillsDir: home.appendingPathComponent(".gemini/antigravity/skills"),   detectPath: ".gemini/antigravity"),
        .init(id: "augment",        displayName: "Augment",         icon: "plus.circle",      globalSkillsDir: home.appendingPathComponent(".augment/skills"),              detectPath: ".augment"),
        .init(id: "bob",            displayName: "IBM Bob",         icon: "person.circle",    globalSkillsDir: home.appendingPathComponent(".bob/skills"),                  detectPath: ".bob"),
        .init(id: "codebuddy",      displayName: "CodeBuddy",       icon: "person.2",         globalSkillsDir: home.appendingPathComponent(".codebuddy/skills"),            detectPath: ".codebuddy"),
        .init(id: "command-code",   displayName: "Command Code",    icon: "command",          globalSkillsDir: home.appendingPathComponent(".commandcode/skills"),          detectPath: ".commandcode"),
        .init(id: "continue",       displayName: "Continue",        icon: "arrow.right.circle", globalSkillsDir: home.appendingPathComponent(".continue/skills"),          detectPath: ".continue"),
        .init(id: "cortex",         displayName: "Cortex Code",     icon: "cpu",              globalSkillsDir: home.appendingPathComponent(".snowflake/cortex/skills"),     detectPath: ".snowflake/cortex"),
        .init(id: "crush",          displayName: "Crush",           icon: "hammer",           globalSkillsDir: home.appendingPathComponent(".config/crush/skills"),         detectPath: ".config/crush"),
        .init(id: "droid",          displayName: "Droid",           icon: "desktopcomputer",  globalSkillsDir: home.appendingPathComponent(".factory/skills"),              detectPath: ".factory"),
        .init(id: "goose",          displayName: "Goose",           icon: "bird",             globalSkillsDir: xdgConfig.appendingPathComponent("goose/skills"),            detectPath: ".config/goose"),
        .init(id: "iflow-cli",      displayName: "iFlow CLI",       icon: "flowchart",        globalSkillsDir: home.appendingPathComponent(".iflow/skills"),                detectPath: ".iflow"),
        .init(id: "junie",          displayName: "Junie",           icon: "j.circle",         globalSkillsDir: home.appendingPathComponent(".junie/skills"),                detectPath: ".junie"),
        .init(id: "kilo",           displayName: "Kilo Code",       icon: "k.circle.fill",    globalSkillsDir: home.appendingPathComponent(".kilocode/skills"),             detectPath: ".kilocode"),
        .init(id: "kiro-cli",       displayName: "Kiro CLI",        icon: "wand.and.stars",   globalSkillsDir: home.appendingPathComponent(".kiro/skills"),                 detectPath: ".kiro"),
        .init(id: "kode",           displayName: "Kode",            icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: home.appendingPathComponent(".kode/skills"),  detectPath: ".kode"),
        .init(id: "mcpjam",         displayName: "MCPJam",          icon: "puzzlepiece",      globalSkillsDir: home.appendingPathComponent(".mcpjam/skills"),               detectPath: ".mcpjam"),
        .init(id: "mistral-vibe",   displayName: "Mistral Vibe",    icon: "waveform",         globalSkillsDir: home.appendingPathComponent(".vibe/skills"),                 detectPath: ".vibe"),
        .init(id: "mux",            displayName: "Mux",             icon: "m.circle",         globalSkillsDir: home.appendingPathComponent(".mux/skills"),                  detectPath: ".mux"),
        .init(id: "neovate",        displayName: "Neovate",         icon: "n.circle",         globalSkillsDir: home.appendingPathComponent(".neovate/skills"),              detectPath: ".neovate"),
        .init(id: "opencode",       displayName: "OpenCode",        icon: "chevron.left.forwardslash.chevron.right", globalSkillsDir: xdgConfig.appendingPathComponent("opencode/skills"), detectPath: ".config/opencode"),
        .init(id: "openhands",      displayName: "OpenHands",       icon: "hands.clap",       globalSkillsDir: home.appendingPathComponent(".openhands/skills"),            detectPath: ".openhands"),
        .init(id: "pi",             displayName: "Pi",              icon: "p.circle",         globalSkillsDir: home.appendingPathComponent(".pi/agent/skills"),             detectPath: ".pi/agent"),
        .init(id: "pochi",          displayName: "Pochi",           icon: "pawprint",         globalSkillsDir: home.appendingPathComponent(".pochi/skills"),                detectPath: ".pochi"),
        .init(id: "qoder",          displayName: "Qoder",           icon: "q.circle",         globalSkillsDir: home.appendingPathComponent(".qoder/skills"),                detectPath: ".qoder"),
        .init(id: "qwen-code",      displayName: "Qwen Code",       icon: "q.circle.fill",    globalSkillsDir: home.appendingPathComponent(".qwen/skills"),                 detectPath: ".qwen"),
        .init(id: "roo",            displayName: "Roo Code",        icon: "r.square",         globalSkillsDir: home.appendingPathComponent(".roo/skills"),                  detectPath: ".roo"),
        .init(id: "trae",           displayName: "Trae",            icon: "t.circle",         globalSkillsDir: home.appendingPathComponent(".trae/skills"),                 detectPath: ".trae"),
        .init(id: "trae-cn",        displayName: "Trae CN",         icon: "t.circle.fill",    globalSkillsDir: home.appendingPathComponent(".trae-cn/skills"),              detectPath: ".trae-cn"),
        .init(id: "windsurf",       displayName: "Windsurf",        icon: "wind",             globalSkillsDir: home.appendingPathComponent(".codeium/windsurf/skills"),     detectPath: ".codeium/windsurf"),
        .init(id: "zencoder",       displayName: "Zencoder",        icon: "z.circle",         globalSkillsDir: home.appendingPathComponent(".zencoder/skills"),             detectPath: ".zencoder"),
        .init(id: "adal",           displayName: "AdaL",            icon: "a.circle",         globalSkillsDir: home.appendingPathComponent(".adal/skills"),                 detectPath: ".adal"),
    ]

    /// Returns agents whose config directory exists on disk right now.
    static func installedAgents() -> [AgentDefinition] {
        all.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.detectPath).path) }
    }

    static func agent(id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Adapters/AgentRegistry.swift
git commit -m "feat: add AgentRegistry with 40+ agent definitions"
```

---

### Task 2: Add `canonicalPath` to Skill model

Skills discovered from agent-specific dirs need a `canonicalPath` so the installer knows where the canonical copy lives (for future de-duplication and symlink management).

**Files:**
- Modify: `SkillsManager/Models/Skill.swift`

- [ ] **Step 1: Add `canonicalPath` field to `Skill`**

In `Skill.swift`, after the `directoryPath` field add:

```swift
/// Path to the canonical .agents/skills/<name>/ directory, if known.
/// Nil for skills that were not installed via the universal symlink mechanism.
var canonicalPath: URL? = nil
```

Full updated struct (lines 21-38):
```swift
struct Skill: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var displayName: String
    var description: String
    var source: SkillSource
    var version: String?
    var filePath: URL
    var directoryPath: URL
    /// Path to the canonical .agents/skills/<name>/ directory, if known.
    var canonicalPath: URL? = nil
    var compatibleAgents: [String]
    var tags: [String]
    var markdownContent: String
    var frontmatter: [String: String]

    // Merged from SkillRecord
    var isStarred: Bool = false
    var installState: InstallState = .installed
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Models/Skill.swift
git commit -m "feat: add canonicalPath field to Skill for symlink tracking"
```

---

### Task 3: UniversalAdapter — scan canonical + all agent dirs

Scans `~/.agents/skills/` (canonical) and every detected agent's `globalSkillsDir`, deduplicates by skill name, and builds `compatibleAgents` list per skill.

**Files:**
- Create: `SkillsManager/Adapters/UniversalAdapter.swift`

**Key logic:**
- Canonical dir `~/.config/agents/skills/` (XDG) or `~/.agents/skills/` as fallback
- Each subdirectory that contains `SKILL.md` is one skill
- If the same skill name exists in multiple agent dirs (because symlinks point to same inode), deduplicate — use `FileManager.fileExists` + `attributesOfItem` `inode` comparison
- `compatibleAgents` = list of agent IDs whose skills dir contains this skill (by name or inode)
- Source = `.local` (global user skills, not plugin-sourced)
- ID = `"universal:<skillName>"`

- [ ] **Step 1: Create `UniversalAdapter.swift`**

```swift
import Foundation

struct UniversalAdapter: AgentAdapter {

    let agentName = "Universal"
    let agentIcon = "square.grid.2x2"

    var skillsDirectories: [URL] {
        [AgentRegistry.canonicalGlobalSkillsDir]
    }

    func scanSkills() async throws -> [Skill] {
        // Run filesystem work off MainActor
        return await Task.detached(priority: .userInitiated) {
            self.scanAllAgentSkills()
        }.value
    }

    func installSkill(_ skill: Skill) throws {
        // Installation is handled by SymlinkInstaller, not this adapter
    }

    func uninstallSkill(_ skill: Skill) throws {
        // Handled by SkillStore.uninstallSkill which deletes the canonical dir + symlinks
    }

    // MARK: - Private

    private func scanAllAgentSkills() -> [Skill] {
        let fm = FileManager.default
        let installedAgents = AgentRegistry.installedAgents()

        // Collect all (skillName → [agentIDs]) by scanning each agent's skills dir
        // Key: inode number of the skill directory (handles symlinked duplicates)
        // Value: (firstURL, [agentIDs])
        var inodeMap: [UInt64: (URL, [String])] = [:]
        // Also track by name for dirs that don't share inodes (copy installs)
        var nameMap: [String: (URL, [String])] = [:]

        // Scan canonical dir first
        scanDir(AgentRegistry.canonicalGlobalSkillsDir, agentID: nil,
                inodeMap: &inodeMap, nameMap: &nameMap, fm: fm)

        // Scan each installed agent's dir
        for agent in installedAgents {
            scanDir(agent.globalSkillsDir, agentID: agent.id,
                    inodeMap: &inodeMap, nameMap: &nameMap, fm: fm)
        }

        // Build skills from deduplicated entries
        var skills: [Skill] = []
        var seenNames = Set<String>()

        // Process inode-matched entries first (symlinked)
        for (_, (dirURL, agentIDs)) in inodeMap {
            let skillMD = dirURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path),
                  let content = try? String(contentsOf: skillMD, encoding: .utf8) else { continue }
            let skill = buildSkill(dirURL: dirURL, content: content, agentIDs: agentIDs)
            if !seenNames.contains(skill.name) {
                seenNames.insert(skill.name)
                skills.append(skill)
            }
        }

        // Process name-matched entries (copy installs, no shared inode)
        for (name, (dirURL, agentIDs)) in nameMap {
            guard !seenNames.contains(name) else { continue }
            let skillMD = dirURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path),
                  let content = try? String(contentsOf: skillMD, encoding: .utf8) else { continue }
            let skill = buildSkill(dirURL: dirURL, content: content, agentIDs: agentIDs)
            seenNames.insert(skill.name)
            skills.append(skill)
        }

        return skills.sorted { $0.displayName < $1.displayName }
    }

    private func scanDir(
        _ dir: URL,
        agentID: String?,
        inodeMap: inout [UInt64: (URL, [String])],
        nameMap: inout [String: (URL, [String])],
        fm: FileManager
    ) {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileResourceIdentifierKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let name = entry.lastPathComponent
            let attrs = try? fm.attributesOfItem(atPath: entry.resolvingSymlinksInPath().path)
            let inode = (attrs?[.systemFileNumber] as? UInt64) ?? 0

            if inode > 0 {
                if var existing = inodeMap[inode] {
                    if let id = agentID, !existing.1.contains(id) {
                        existing.1.append(id)
                    }
                    inodeMap[inode] = existing
                } else {
                    inodeMap[inode] = (entry, agentID.map { [$0] } ?? [])
                }
            } else {
                // Fallback: deduplicate by name
                if var existing = nameMap[name] {
                    if let id = agentID, !existing.1.contains(id) {
                        existing.1.append(id)
                    }
                    nameMap[name] = existing
                } else {
                    nameMap[name] = (entry, agentID.map { [$0] } ?? [])
                }
            }
        }
    }

    private func buildSkill(dirURL: URL, content: String, agentIDs: [String]) -> Skill {
        let parsed = SkillParser.parse(content: content)
        let fm = parsed.frontmatter
        let dirName = dirURL.lastPathComponent
        let displayName = fm["name"] ?? dirName
        let description = fm["description"] ?? ""
        let rawTags = fm["tags"] ?? fm["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Resolve display names for agentIDs, falling back to id if not in registry
        let agentDisplayNames = agentIDs.map { id in
            AgentRegistry.agent(id: id)?.displayName ?? id
        }

        return Skill(
            id: "universal:\(dirName)",
            name: dirName,
            displayName: displayName,
            description: description,
            source: .local,
            version: fm["version"],
            filePath: dirURL.appendingPathComponent("SKILL.md"),
            directoryPath: dirURL,
            canonicalPath: AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(dirName),
            compatibleAgents: agentDisplayNames.isEmpty ? ["Universal"] : agentDisplayNames,
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Adapters/UniversalAdapter.swift
git commit -m "feat: add UniversalAdapter scanning canonical + all installed agent skill dirs"
```

---

### Task 4: SymlinkInstaller — canonical write + symlink to agent dirs

Pure service, no UI dependencies.

**Files:**
- Create: `SkillsManager/Services/SymlinkInstaller.swift`

- [ ] **Step 1: Create `SymlinkInstaller.swift`**

```swift
import Foundation

/// Writes a skill to the canonical ~/.config/agents/skills/<name>/ directory
/// and creates symlinks in each target agent's globalSkillsDir.
enum SymlinkInstaller {

    /// Install a skill (represented as SKILL.md content) to one or more agents.
    /// - Parameters:
    ///   - content: The SKILL.md content string to write.
    ///   - skillName: The directory name to use (kebab-case).
    ///   - agentIDs: IDs from AgentRegistry to install to. Pass [] to install only to canonical dir.
    static func install(content: String, skillName: String, agentIDs: [String]) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(safe)

        // Write to canonical location
        if !fm.fileExists(atPath: canonicalDir.path) {
            try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        }
        let skillMDPath = canonicalDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDPath, atomically: true, encoding: .utf8)

        // Create symlinks for each agent
        for agentID in agentIDs {
            guard let agentDef = AgentRegistry.agent(id: agentID) else { continue }
            try createSymlink(from: canonicalDir, to: agentDef.globalSkillsDir.appendingPathComponent(safe), fm: fm)
        }
    }

    /// Remove a skill: delete canonical dir (which also breaks all symlinks pointing to it).
    /// Then remove any dangling symlinks in agent dirs.
    static func uninstall(skillName: String) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(safe)

        // Remove canonical dir (all symlinks to it become dangling, then we clean them)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        // Clean up dangling symlinks in every agent dir
        for agent in AgentRegistry.all {
            let agentSkillDir = agent.globalSkillsDir.appendingPathComponent(safe)
            // lstatAttributes works on broken symlinks; fileExists does not
            if let attrs = try? fm.attributesOfItem(atPath: agentSkillDir.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                try? fm.removeItem(at: agentSkillDir)
            }
        }
    }

    // MARK: - Helpers

    private static func createSymlink(from target: URL, to linkPath: URL, fm: FileManager) throws {
        let linkDir = linkPath.deletingLastPathComponent()
        if !fm.fileExists(atPath: linkDir.path) {
            try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        }

        // Remove existing entry at linkPath (could be old copy or stale symlink)
        if fm.fileExists(atPath: linkPath.path) || (try? fm.attributesOfItem(atPath: linkPath.path)) != nil {
            try fm.removeItem(at: linkPath)
        }

        // Resolve the real target path to handle cases where parent dirs are symlinked
        let realTarget = target.resolvingSymlinksInPath()
        let realLinkDir = linkDir.resolvingSymlinksInPath()

        // Use relative path so the symlink works if home dir moves
        let relative = realTarget.path
            .replacingOccurrences(of: realLinkDir.path + "/", with: "")
        let symlinkTarget = relative.hasPrefix("/") ? realTarget.path : relative

        try fm.createSymbolicLink(atPath: linkPath.path, withDestinationPath: symlinkTarget)
    }

    /// Sanitize to kebab-case, matching vercel/skills sanitizeName logic.
    static func sanitize(_ name: String) -> String {
        let s = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"^[.\-]+|[.\-]+$"#, with: "", options: .regularExpression)
        return s.isEmpty ? "unnamed-skill" : String(s.prefix(255))
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/SymlinkInstaller.swift
git commit -m "feat: add SymlinkInstaller for canonical write + multi-agent symlink"
```

---

### Task 5: Wire SkillStore + retire CursorAdapter

Replace the two hardcoded adapters with `UniversalAdapter` + `ClaudeCodeAdapter`. Add `installSkillToAgents` action. Remove `.mdc` install-to-cursor path (now covered by registry).

**Files:**
- Modify: `SkillsManager/Services/SkillStore.swift`
- Delete: `SkillsManager/Adapters/CursorAdapter.swift`

- [ ] **Step 1: Update `SkillStore.swift` — replace adapters, add installSkillToAgents**

Replace the `// MARK: - Services` section and `init()` and `reloadSkills()` and `installToCursor`:

```swift
// MARK: - Services

private let claudeAdapter: ClaudeCodeAdapter
private let universalAdapter: UniversalAdapter
private let marketplaceService: MarketplaceService
private let installService: InstallService

init() {
    let ms = MarketplaceService()
    self.claudeAdapter = ClaudeCodeAdapter()
    self.universalAdapter = UniversalAdapter()
    self.marketplaceService = ms
    self.installService = InstallService(marketplaceService: ms)
}
```

Replace `reloadSkills()`:

```swift
func reloadSkills() async {
    isLoading = true
    defer { isLoading = false }
    do {
        // ClaudeCodeAdapter: scans ~/.claude/skills/ + ~/.claude/plugins/cache/
        // UniversalAdapter:  scans ~/.config/agents/skills/ + every installed agent dir
        async let claudeSkills = claudeAdapter.scanSkills()
        async let universalSkills = universalAdapter.scanSkills()
        let (claude, universal) = try await (claudeSkills, universalSkills)
        // Deduplicate by id (a Claude skill also present in ~/.agents/skills will
        // appear in both; prefer the ClaudeCodeAdapter version for richer metadata)
        var seen = Set<String>()
        var merged: [Skill] = []
        for skill in claude + universal {
            if seen.insert(skill.id).inserted { merged.append(skill) }
        }
        skills = merged
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Replace `installToCursor(skill:)` with `installSkillToAgents(_:agentIDs:)`:

```swift
// MARK: - Install to agents via SymlinkInstaller

/// Installs a skill's SKILL.md content to the canonical dir and symlinks to each target agent.
func installSkillToAgents(_ skill: Skill, agentIDs: [String]) async {
    do {
        try SymlinkInstaller.install(
            content: skill.markdownContent,
            skillName: skill.name,
            agentIDs: agentIDs
        )
        await reloadSkills()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Also update `uninstallSkill` to call `SymlinkInstaller.uninstall` for `.local` source skills that have a `canonicalPath` set, as they may have been installed via the universal mechanism. Replace the `.local` branch inside `uninstallSkill`:

```swift
case .local:
    let skillsBase = fm.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills").standardized
    let target = skill.directoryPath.standardized
    if target.path.hasPrefix(skillsBase.path + "/") {
        // Claude-specific local skill — delete directly
        do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
    } else if skill.canonicalPath != nil {
        // Universal skill installed via SymlinkInstaller
        do { try SymlinkInstaller.uninstall(skillName: skill.name) } catch { errorMessage = error.localizedDescription }
    }
```

- [ ] **Step 2: Delete `CursorAdapter.swift`**

```bash
rm SkillsManager/Adapters/CursorAdapter.swift
```

CursorAdapter is no longer referenced after this change. Cursor is now handled as an `AgentDefinition` in the registry and scanned by `UniversalAdapter`.

- [ ] **Step 3: Fix any remaining references to `cursorAdapter` or `installToCursor` in ContentView / SkillDetailView**

Search:
```bash
grep -r "installToCursor\|cursorAdapter\|CursorAdapter" SkillsManager/ --include="*.swift"
```

For any `onInstallToCursor` callback in `ContentView.swift` and `SkillDetailView.swift`:
- Remove the `onInstallToCursor` parameter from `SkillDetailView` (replaced by `InstallToAgentView` sheet in Task 6)
- Remove the `onInstallToCursor` call-site in `ContentView`

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SkillsManager/Services/SkillStore.swift
git rm SkillsManager/Adapters/CursorAdapter.swift
git commit -m "feat: wire UniversalAdapter+SymlinkInstaller, retire CursorAdapter"
```

---

### Task 6: InstallToAgentView + SkillDetailView integration

New sheet that shows all installed agents as a multi-select list. Replaces the hardcoded "Install to Cursor" toolbar button.

**Files:**
- Create: `SkillsManager/Views/InstallToAgentView.swift`
- Modify: `SkillsManager/Views/SkillDetailView.swift`
- Modify: `SkillsManager/Views/ContentView.swift`

- [ ] **Step 1: Create `InstallToAgentView.swift`**

```swift
import SwiftUI

struct InstallToAgentView: View {
    let skill: Skill
    let onInstall: ([String]) async -> Void  // agentIDs to install to

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isInstalling = false

    private var installedAgents: [AgentDefinition] {
        AgentRegistry.installedAgents()
    }

    // Pre-select agents this skill is already compatible with
    private var alreadyInstalledIDs: Set<String> {
        Set(skill.compatibleAgents.compactMap { name in
            AgentRegistry.all.first { $0.displayName == name }?.id
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install to Agent")
                        .font(.headline)
                    Text(skill.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if installedAgents.isEmpty {
                ContentUnavailableView(
                    "No Agents Detected",
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    description: Text("No supported coding agents were found on this Mac.")
                )
                .frame(minHeight: 200)
            } else {
                List(installedAgents, id: \.id, selection: $selected) { agent in
                    HStack {
                        Label(agent.displayName, systemImage: agent.icon)
                        Spacer()
                        if alreadyInstalledIDs.contains(agent.id) {
                            Text("Installed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(agent.id)
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack {
                Text(selected.isEmpty ? "Select agents above" : "\(selected.count) agent\(selected.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install") {
                    isInstalling = true
                    Task {
                        await onInstall(Array(selected))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 340, height: 420)
    }
}

#Preview {
    InstallToAgentView(
        skill: Skill.mockSkills[0],
        onInstall: { _ in }
    )
}
```

- [ ] **Step 2: Update `SkillDetailView.swift` — replace "Install to Cursor" with "Install to Agent…"**

Remove the `onInstallToCursor` property and its `DetailContent` usage. Add `@State private var showInstallToAgent = false`.

Replace the old `ToolbarItem` for "Install to Cursor":

```swift
// Show "Install to Agent" for installed skills
if skill.installState == .installed {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showInstallToAgent = true
        } label: {
            Label("Install to Agent…", systemImage: "square.and.arrow.down.on.square")
        }
        .help("Install this skill to another coding agent")
    }
}
```

Add the sheet modifier at the end of `DetailContent.body` (inside the `ScrollView`'s parent):

```swift
.sheet(isPresented: $showInstallToAgent) {
    InstallToAgentView(skill: skill, onInstall: onInstallToAgent)
}
```

Add `@State private var showInstallToAgent = false` and `let onInstallToAgent: ([String]) async -> Void` to `DetailContent`.

Updated `SkillDetailView` struct (full replacement of the struct and its forwarding to `DetailContent`):

```swift
struct SkillDetailView: View {
    let skill: Skill?
    var onToggleStar: () -> Void = {}
    var onInstallToAgent: (Skill, [String]) async -> Void = { _, _ in }
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
                    onInstallToAgent: { agentIDs in Task { await onInstallToAgent(skill, agentIDs) } },
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

Updated `DetailContent` properties:
```swift
private struct DetailContent: View {
    let skill: Skill
    @Binding var showVersionHistory: Bool
    @Binding var commits: [GitCommit]
    let onToggleStar: () -> Void
    let onInstallToAgent: ([String]) -> Void
    let onPromote: () -> Void

    @State private var showInstallToAgent = false
```

- [ ] **Step 3: Update `ContentView.swift` — pass new callback**

Replace the `onInstallToCursor` call-site in the `SkillDetailView(...)` block:

```swift
SkillDetailView(
    skill: selectedSkill,
    onToggleStar: { /* existing star toggle code */ },
    onInstallToAgent: { skill, agentIDs in
        await store.installSkillToAgents(skill, agentIDs: agentIDs)
    },
    onPromote: { skill in await store.promoteSkill(skill) }
)
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SkillsManager/Views/InstallToAgentView.swift \
        SkillsManager/Views/SkillDetailView.swift \
        SkillsManager/Views/ContentView.swift
git commit -m "feat: add InstallToAgentView multi-select sheet, replace Install to Cursor button"
```

---

### Task 7: Update SidebarView — show detected agent count per agent

The Agents sidebar section currently shows agents from `skill.compatibleAgents` strings. Update it to also list installed agents from `AgentRegistry` even if they have 0 skills yet.

**Files:**
- Modify: `SkillsManager/Views/SidebarView.swift`

- [ ] **Step 1: Update `agentNames` computed property in `SidebarView`**

Replace the `agentNames` computed property:

```swift
/// Union of: agents detected from registry + agents appearing in skill metadata.
private var agentNames: [String] {
    let fromSkills = Set(skills.flatMap { $0.compatibleAgents })
    let fromRegistry = Set(AgentRegistry.installedAgents().map { $0.displayName })
    return fromSkills.union(fromRegistry).sorted()
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Views/SidebarView.swift
git commit -m "feat: sidebar Agents section shows all detected agents from registry"
```

---

## Summary

| Task | Files | What it does |
|---|---|---|
| 1 | AgentRegistry.swift | 40+ agent definitions with global skill paths + detect logic |
| 2 | Skill.swift | `canonicalPath` field for symlink tracking |
| 3 | UniversalAdapter.swift | Scans canonical + all agent dirs, deduplicates via inode |
| 4 | SymlinkInstaller.swift | Writes canonical SKILL.md + symlinks to agent dirs |
| 5 | SkillStore.swift, delete CursorAdapter.swift | Wire new adapters, add installSkillToAgents, retire CursorAdapter |
| 6 | InstallToAgentView.swift, SkillDetailView.swift, ContentView.swift | Multi-select agent install sheet |
| 7 | SidebarView.swift | Agents section shows all detected agents |
