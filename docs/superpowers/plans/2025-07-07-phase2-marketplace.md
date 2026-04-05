# Phase 2: Marketplace + 安装/卸载 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 接入真实 ClaudeCodeAdapter 数据，实现 GitHub marketplace 索引同步、skill 安装/卸载、以及搜索筛选功能。

**Architecture:** App 启动时通过 ClaudeCodeAdapter 扫描本地 skills 并显示；用户可从已注册的 marketplace（`~/.claude/plugins/known_marketplaces.json`）读取插件列表，通过 GitHub Contents API 拉取 `marketplace.json`，解析可用 plugins 并显示在 Discover 列表中；安装 = 下载插件 zip 到 `~/.claude/plugins/cache/` 并写入 `installed_plugins.json`；卸载 = 移除缓存目录并更新 `installed_plugins.json`。

**Tech Stack:** SwiftUI + Swift 6, SwiftData, URLSession (GitHub API), Foundation FileManager, Process (git CLI)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `SkillsManager/Services/MarketplaceService.swift` | Create | 读取 known_marketplaces.json，拉取 marketplace.json，构建可发现 plugin 列表 |
| `SkillsManager/Services/InstallService.swift` | Create | 下载 plugin zip，解压到 cache，更新 installed_plugins.json，安装/卸载 |
| `SkillsManager/Models/MarketplacePlugin.swift` | Create | `MarketplacePlugin` struct（可发现的 plugin）和 `InstalledPlugin` struct |
| `SkillsManager/Services/SkillStore.swift` | Modify | 注入 MarketplaceService；暴露 `discoverablePlugins`；连接安装状态 |
| `SkillsManager/Views/ContentView.swift` | Modify | 注入真实 ClaudeCodeAdapter + SkillStore，移除 mock 数据 |
| `SkillsManager/Views/SkillListView.swift` | Modify | 连接真实 Install/Uninstall 操作 |
| `SkillsManager/Views/DiscoverView.swift` | Create | 显示可发现的 marketplace plugins，搜索、筛选、安装入口 |
| `SkillsManager/Views/SidebarView.swift` | Modify | 添加 "Discover" 入口，连接真实数据 counts |
| `SkillsManager/Models/SidebarFilter.swift` | Modify | 添加 `.discover` case |
| `SkillsManagerApp.swift` | Modify | 启动时触发 `SkillStore.reload()` |

---

## Task 1: 数据模型 — MarketplacePlugin

**Files:**
- Create: `SkillsManager/Models/MarketplacePlugin.swift`

- [ ] **Step 1: 创建 MarketplacePlugin.swift**

```swift
import Foundation

/// 从 marketplace.json 解析的可安装 plugin
struct MarketplacePlugin: Identifiable, Sendable {
    let id: String               // "{marketplace}:{name}"
    var name: String
    var description: String
    var marketplace: String      // marketplace 名称，如 "claude-plugins-official"
    var category: String?
    var homepage: URL?
    var sourceType: PluginSourceType
    var skills: [String]         // 安装后包含的 skill 名称（从 plugin 目录扫描）
    var isInstalled: Bool = false
    var installedVersion: String?
}

enum PluginSourceType: Sendable {
    case localPath(String)       // source = "./" 相对路径
    case gitURL(url: String, sha: String?)
    case gitSubdir(url: String, path: String, ref: String, sha: String?)
    case remoteURL(url: String, sha: String?)
}

/// installed_plugins.json 中的一条安装记录
struct InstalledPluginRecord: Codable, Sendable {
    var scope: String
    var installPath: String
    var version: String
    var installedAt: String
    var lastUpdated: String
    var gitCommitSha: String?
}

/// installed_plugins.json 整体结构
struct InstalledPluginsFile: Codable, Sendable {
    var version: Int
    var plugins: [String: [InstalledPluginRecord]]
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Models/MarketplacePlugin.swift
git commit -m "feat: add MarketplacePlugin data model"
```

---

## Task 2: MarketplaceService — 读取本地 marketplace 索引

**Files:**
- Create: `SkillsManager/Services/MarketplaceService.swift`

本服务读取 `~/.claude/plugins/known_marketplaces.json` 和已缓存的 `~/.claude/plugins/marketplaces/{name}/.claude-plugin/marketplace.json`，**不**发起网络请求（网络同步是 Task 5）。

- [ ] **Step 1: 创建 MarketplaceService.swift**

```swift
import Foundation

actor MarketplaceService {

    private let pluginsBase: URL

    init() {
        pluginsBase = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/plugins")
    }

    // MARK: - 读取已知 marketplace 列表

    /// 从 known_marketplaces.json 读取所有已注册 marketplace 名称
    func knownMarketplaceNames() throws -> [String] {
        let url = pluginsBase.appending(path: "known_marketplaces.json")
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Array(dict.keys).sorted()
    }

    // MARK: - 读取本地缓存的 marketplace 索引

    /// 解析某个 marketplace 的 marketplace.json，返回 MarketplacePlugin 列表
    func loadCachedPlugins(marketplace: String) throws -> [MarketplacePlugin] {
        let marketplaceDir = pluginsBase
            .appending(path: "marketplaces/\(marketplace)/.claude-plugin/marketplace.json")
        let data = try Data(contentsOf: marketplaceDir)
        return try parseMarketplaceJSON(data: data, marketplace: marketplace)
    }

    /// 加载所有已知 marketplace 的本地缓存
    func loadAllCachedPlugins() -> [MarketplacePlugin] {
        guard let names = try? knownMarketplaceNames() else { return [] }
        return names.flatMap { name in
            (try? loadCachedPlugins(marketplace: name)) ?? []
        }
    }

    // MARK: - 读取已安装插件状态

    func loadInstalledPlugins() throws -> InstalledPluginsFile {
        let url = pluginsBase.appending(path: "installed_plugins.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(InstalledPluginsFile.self, from: data)
    }

    // MARK: - 合并安装状态

    /// 将安装状态合并到 plugin 列表
    func mergeInstallState(
        plugins: [MarketplacePlugin],
        installed: InstalledPluginsFile
    ) -> [MarketplacePlugin] {
        let installedKeys = Set(installed.plugins.keys)
        return plugins.map { plugin in
            var p = plugin
            let key = "\(plugin.name)@\(plugin.marketplace)"
            if let records = installed.plugins[key], let record = records.first {
                p.isInstalled = true
                p.installedVersion = record.version
            } else {
                p.isInstalled = installedKeys.contains(
                    where: { $0.hasPrefix("\(plugin.name)@") }
                )
            }
            return p
        }
    }

    // MARK: - Private

    private func parseMarketplaceJSON(
        data: Data,
        marketplace: String
    ) throws -> [MarketplacePlugin] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pluginsArray = root["plugins"] as? [[String: Any]] else {
            return []
        }

        return pluginsArray.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let description = dict["description"] as? String ?? ""
            let category = dict["category"] as? String
            let homepageStr = dict["homepage"] as? String
            let homepage = homepageStr.flatMap { URL(string: $0) }
            let sourceType = parseSource(dict["source"])

            return MarketplacePlugin(
                id: "\(marketplace):\(name)",
                name: name,
                description: description,
                marketplace: marketplace,
                category: category,
                homepage: homepage,
                sourceType: sourceType,
                skills: []
            )
        }
    }

    private func parseSource(_ raw: Any?) -> PluginSourceType {
        guard let dict = raw as? [String: Any],
              let sourceType = dict["source"] as? String else {
            // No source key = local relative path
            if let str = raw as? String { return .localPath(str) }
            return .localPath("./")
        }
        switch sourceType {
        case "git-subdir":
            return .gitSubdir(
                url: dict["url"] as? String ?? "",
                path: dict["path"] as? String ?? "",
                ref: dict["ref"] as? String ?? "main",
                sha: dict["sha"] as? String
            )
        case "url":
            return .remoteURL(
                url: dict["url"] as? String ?? "",
                sha: dict["sha"] as? String
            )
        default: // "github", "git"
            return .gitURL(
                url: dict["url"] as? String ?? "",
                sha: dict["sha"] as? String
            )
        }
    }
}

// Helper to check installed keys with prefix
private extension Set where Element == String {
    func contains(where predicate: (String) -> Bool) -> Bool {
        self.first(where: predicate) != nil
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/MarketplaceService.swift
git commit -m "feat: add MarketplaceService for reading local marketplace cache"
```

---

## Task 3: InstallService — 安装与卸载

**Files:**
- Create: `SkillsManager/Services/InstallService.swift`

安装策略：对于 `localPath` 类型的 plugin（已在 marketplace 本地缓存里），直接从 marketplaces 目录复制到 plugins/cache；对于其他类型，先用 `git clone` 或 `curl` 下载，再解压。Phase 2 仅实现 `localPath` 类型（覆盖绝大多数 `claude-plugins-official` 中的 plugins）。

- [ ] **Step 1: 创建 InstallService.swift**

```swift
import Foundation

actor InstallService {

    private let pluginsBase: URL
    private let marketplaceService: MarketplaceService

    init(marketplaceService: MarketplaceService) {
        self.pluginsBase = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/plugins")
        self.marketplaceService = marketplaceService
    }

    // MARK: - Install

    func install(plugin: MarketplacePlugin) async throws {
        switch plugin.sourceType {
        case .localPath(let relativePath):
            try installFromLocalCache(plugin: plugin, relativePath: relativePath)
        case .gitURL(let url, _), .remoteURL(let url, _):
            try await installFromGit(plugin: plugin, repoURL: url, subpath: nil)
        case .gitSubdir(let url, let path, let ref, _):
            try await installFromGit(plugin: plugin, repoURL: url, subpath: path, ref: ref)
        }
        try updateInstalledRecord(plugin: plugin, action: .install)
    }

    // MARK: - Uninstall

    func uninstall(plugin: MarketplacePlugin) throws {
        // Remove all version directories under cache/{marketplace}/{name}/
        let cacheDir = pluginsBase
            .appending(path: "cache/\(plugin.marketplace)/\(plugin.name)")
        if FileManager.default.fileExists(atPath: cacheDir.path()) {
            try FileManager.default.removeItem(at: cacheDir)
        }
        try updateInstalledRecord(plugin: plugin, action: .uninstall)
    }

    // MARK: - Local cache install (for localPath source type)

    private func installFromLocalCache(
        plugin: MarketplacePlugin,
        relativePath: String
    ) throws {
        // Source: ~/.claude/plugins/marketplaces/{marketplace}/{relativePath}
        let sourceBase = pluginsBase
            .appending(path: "marketplaces/\(plugin.marketplace)")
        let sourcePath = relativePath.hasPrefix("./")
            ? sourceBase.appending(path: String(relativePath.dropFirst(2)))
            : sourceBase.appending(path: relativePath)

        // Destination: ~/.claude/plugins/cache/{marketplace}/{name}/{version}/
        let version = plugin.installedVersion ?? "local"
        let destDir = pluginsBase
            .appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)")

        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Copy all contents
        let contents = try fm.contentsOfDirectory(
            at: sourcePath,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            let dest = destDir.appending(path: item.lastPathComponent)
            if fm.fileExists(atPath: dest.path()) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: item, to: dest)
        }
    }

    // MARK: - Git install

    private func installFromGit(
        plugin: MarketplacePlugin,
        repoURL: String,
        subpath: String?,
        ref: String = "main"
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "skills-manager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Clone repo
        try await runProcess(
            "/usr/bin/git",
            args: ["clone", "--depth=1", "--branch", ref, repoURL, tempDir.path()],
            at: FileManager.default.temporaryDirectory
        )

        let sourceDir: URL
        if let sub = subpath {
            sourceDir = tempDir.appending(path: sub)
        } else {
            sourceDir = tempDir
        }

        let version = plugin.installedVersion ?? ref
        let destDir = pluginsBase
            .appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)")

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceDir, includingPropertiesForKeys: nil
        )
        for item in contents {
            let dest = destDir.appending(path: item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path()) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: item, to: dest)
        }
    }

    // MARK: - installed_plugins.json update

    private enum RecordAction { case install, uninstall }

    private func updateInstalledRecord(
        plugin: MarketplacePlugin,
        action: RecordAction
    ) throws {
        let url = pluginsBase.appending(path: "installed_plugins.json")
        var file: InstalledPluginsFile
        if let data = try? Data(contentsOf: url) {
            file = (try? JSONDecoder().decode(InstalledPluginsFile.self, from: data))
                ?? InstalledPluginsFile(version: 2, plugins: [:])
        } else {
            file = InstalledPluginsFile(version: 2, plugins: [:])
        }

        let key = "\(plugin.name)@\(plugin.marketplace)"
        switch action {
        case .install:
            let version = plugin.installedVersion ?? "local"
            let installPath = pluginsBase
                .appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)")
                .path()
            let now = ISO8601DateFormatter().string(from: Date())
            let record = InstalledPluginRecord(
                scope: "user",
                installPath: installPath,
                version: version,
                installedAt: now,
                lastUpdated: now,
                gitCommitSha: nil
            )
            file.plugins[key] = [record]
        case .uninstall:
            file.plugins.removeValue(forKey: key)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url)
    }

    // MARK: - Process helper

    private func runProcess(_ exec: String, args: [String], at dir: URL) async throws {
        let process = Process()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: exec)
        process.arguments = args
        process.currentDirectoryURL = dir
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? ""
            throw InstallError.processFailed(exec, msg)
        }
    }
}

enum InstallError: LocalizedError {
    case processFailed(String, String)
    case sourceNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let cmd, let msg): "Process failed: \(cmd)\n\(msg)"
        case .sourceNotSupported(let type): "Install source not supported: \(type)"
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/InstallService.swift
git commit -m "feat: add InstallService for plugin install/uninstall"
```

---

## Task 4: SkillStore — 接入真实数据

**Files:**
- Modify: `SkillsManager/Services/SkillStore.swift`

- [ ] **Step 1: 更新 SkillStore，加入 discoverablePlugins 和安装操作**

完整替换文件内容：

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {

    // MARK: - State

    var skills: [Skill] = []
    var discoverablePlugins: [MarketplacePlugin] = []
    var isLoading = false
    var isLoadingPlugins = false
    var errorMessage: String?

    // MARK: - Services

    private let adapter: ClaudeCodeAdapter
    private let marketplaceService: MarketplaceService
    let installService: InstallService

    init() {
        let ms = MarketplaceService()
        self.adapter = ClaudeCodeAdapter()
        self.marketplaceService = ms
        self.installService = InstallService(marketplaceService: ms)
    }

    // MARK: - Load local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await adapter.scanSkills()
            skills = loaded
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

    // MARK: - Discover marketplace plugins

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

    // MARK: - Install / Uninstall

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
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/SkillStore.swift
git commit -m "feat: wire SkillStore with real data and marketplace plugins"
```

---

## Task 5: DiscoverView — Marketplace 浏览界面

**Files:**
- Create: `SkillsManager/Views/DiscoverView.swift`
- Modify: `SkillsManager/Models/SidebarFilter.swift` — 添加 `.discover` case
- Modify: `SkillsManager/Views/SidebarView.swift` — 添加 Discover 入口

- [ ] **Step 1: 添加 .discover 到 SidebarFilter**

在 `SkillsManager/Models/SidebarFilter.swift` 中，将 `enum SidebarFilter` 的 `title` 和 `icon` switch 添加：

```swift
// 在 enum SidebarFilter 中添加 case：
case discover

// 在 title computed property 中添加：
case .discover: "Discover"

// 在 icon computed property 中添加：
case .discover: "safari"
```

- [ ] **Step 2: 在 SidebarView 添加 Discover 行**

在 `SkillsManager/Views/SidebarView.swift` 的 Library section 中，在 `case .all` 之前添加 Discover 行：

```swift
SidebarRow(
    filter: .discover,
    count: nil,
    selectedFilter: $selectedFilter
)
```

- [ ] **Step 3: 创建 DiscoverView.swift**

```swift
import SwiftUI

struct DiscoverView: View {
    let plugins: [MarketplacePlugin]
    let isLoading: Bool
    let onInstall: (MarketplacePlugin) async -> Void
    let onUninstall: (MarketplacePlugin) async -> Void

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil

    private var filtered: [MarketplacePlugin] {
        plugins.filter { plugin in
            let matchesSearch = searchText.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(searchText)
                || plugin.description.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil
                || plugin.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var categories: [String] {
        Array(Set(plugins.compactMap { $0.category })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter chips
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(
                            label: "All",
                            isSelected: selectedCategory == nil
                        ) { selectedCategory = nil }

                        ForEach(categories, id: \.self) { cat in
                            CategoryChip(
                                label: cat.capitalized,
                                isSelected: selectedCategory == cat
                            ) { selectedCategory = cat }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            if isLoading {
                ProgressView("Loading marketplace...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Plugins" : "No Results",
                    systemImage: "safari",
                    description: Text(
                        searchText.isEmpty
                            ? "No marketplace plugins found."
                            : "No plugins match \"\(searchText)\"."
                    )
                )
            } else {
                List(filtered) { plugin in
                    PluginRow(
                        plugin: plugin,
                        onInstall: { Task { await onInstall(plugin) } },
                        onUninstall: { Task { await onUninstall(plugin) } }
                    )
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search plugins...")
        .navigationTitle("Discover")
    }
}

// MARK: - Plugin row

private struct PluginRow: View {
    let plugin: MarketplacePlugin
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(plugin.marketplace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if plugin.isInstalled {
                    Button("Uninstall", action: onUninstall)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                } else {
                    Button("Install", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            Text(plugin.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let cat = plugin.category {
                Text(cat.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiscoverView(
        plugins: [
            MarketplacePlugin(
                id: "claude-plugins-official:superpowers",
                name: "superpowers",
                description: "Core skills library: TDD, debugging, collaboration patterns",
                marketplace: "claude-plugins-official",
                category: "development",
                homepage: URL(string: "https://github.com/obra/superpowers"),
                sourceType: .localPath("./plugins/superpowers"),
                skills: [],
                isInstalled: true,
                installedVersion: "5.0.7"
            ),
            MarketplacePlugin(
                id: "claude-plugins-official:code-review",
                name: "code-review",
                description: "Automated code review with best practice checks",
                marketplace: "claude-plugins-official",
                category: "development",
                homepage: nil,
                sourceType: .localPath("./plugins/code-review"),
                skills: [],
                isInstalled: false,
                installedVersion: nil
            ),
        ],
        isLoading: false,
        onInstall: { _ in },
        onUninstall: { _ in }
    )
    .frame(width: 500, height: 600)
}
```

- [ ] **Step 4: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add SkillsManager/Views/DiscoverView.swift \
        SkillsManager/Models/SidebarFilter.swift \
        SkillsManager/Views/SidebarView.swift
git commit -m "feat: add DiscoverView for marketplace plugin browsing"
```

---

## Task 6: ContentView — 接入真实数据，移除 mock

**Files:**
- Modify: `SkillsManager/Views/ContentView.swift`
- Modify: `SkillsManager/SkillsManagerApp.swift`

- [ ] **Step 1: 更新 ContentView，注入 SkillStore，路由 Discover**

完整替换 `ContentView.swift`：

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var skillRecords: [SkillRecord]

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFilter: $selectedFilter, skills: store.skills)
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    plugins: store.discoverablePlugins,
                    isLoading: store.isLoadingPlugins,
                    onInstall: { plugin in await store.install(plugin: plugin) },
                    onUninstall: { plugin in await store.uninstall(plugin: plugin) }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) }
                )
            }
        } detail: {
            SkillDetailView(skill: selectedSkill)
        }
        .task {
            await store.reloadSkills()
            await store.reloadDiscoverablePlugins()
            store.merge(records: skillRecords)
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .alert("Error", isPresented: .constant(store.errorMessage != nil)) {
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

- [ ] **Step 2: 给 SkillStore 添加 installSkill / uninstallSkill stub**

在 `SkillStore.swift` 末尾添加（用于 SkillListView 的已安装 skill 操作）：

```swift
// 已安装 skill 的安装/卸载（操作本地文件）
func installSkill(_ skill: Skill) async {
    // Phase 2: copy skill dir to ~/.claude/skills/ if not already there
    // For now update state only
    if let index = skills.firstIndex(where: { $0.id == skill.id }) {
        skills[index].installState = .installed
    }
}

func uninstallSkill(_ skill: Skill) async {
    if let index = skills.firstIndex(where: { $0.id == skill.id }) {
        skills[index].installState = .notInstalled
    }
}
```

- [ ] **Step 3: 更新 SkillListView 接受 install/uninstall 回调**

在 `SkillListView` 中添加两个参数，并把 `SkillActionButtons` 的按钮接上：

```swift
// SkillListView 新增参数:
let onInstall: (Skill) async -> Void
let onUninstall: (Skill) async -> Void

// SkillActionButtons 新增参数:
let onInstall: () -> Void
let onUninstall: () -> Void

// SkillRow 传递给 SkillActionButtons:
SkillActionButtons(
    skill: skill,
    onInstall: { Task { await onInstall(skill) } },
    onUninstall: { Task { await onUninstall(skill) } }
)
```

同时更新 `SkillActionButtons` 中的按钮 action：

```swift
case .notInstalled:
    ActionButton(icon: "arrow.down.circle", label: "Install", action: onInstall)
case .installed:
    ActionButton(icon: "trash", label: "Uninstall", action: onUninstall)
case .trial:
    ActionButton(icon: "arrow.down.circle", label: "Keep", action: onInstall)
    ActionButton(icon: "xmark.circle", label: "Discard", action: onUninstall)
```

更新 Preview 中的 `SkillListView` 调用：

```swift
SkillListView(
    skills: Skill.mockSkills,
    filter: .all,
    selectedSkill: $selected,
    onInstall: { _ in },
    onUninstall: { _ in }
)
```

- [ ] **Step 4: 构建验证**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add SkillsManager/Views/ContentView.swift \
        SkillsManager/Services/SkillStore.swift \
        SkillsManager/Views/SkillListView.swift
git commit -m "feat: wire ContentView to real data, add install/uninstall actions"
```

---

## Task 7: 启动时加载 + 最终验证

**Files:**
- Modify: `SkillsManager/SkillsManagerApp.swift`

- [ ] **Step 1: 确认 SkillsManagerApp 包含 modelContainer**

当前 `SkillsManagerApp.swift` 已经配置了 `ModelContainer`，确认 `SkillRecord.self` 在 schema 中：

```swift
// 当前已有，确认无误：
let schema = Schema([SkillRecord.self])
```

不需要修改，跳过。

- [ ] **Step 2: 全量构建验证**

```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```
Expected: `Build complete!` 无 error

- [ ] **Step 3: 手动验证清单**

1. 运行 app（`swift run` 或 Xcode）
2. Sidebar 显示真实 skills 数量（来自 `~/.claude/skills/`）
3. 选中 skill → Detail Panel 显示真实 SKILL.md 内容
4. 切换到 Discover → 显示 marketplace plugins 列表，分 category 筛选正常
5. 点击 Install → plugin 出现在 `~/.claude/plugins/cache/`，按钮变为 Uninstall
6. 点击 Uninstall → cache 目录被移除，按钮恢复 Install
7. 搜索框过滤 Discover 列表正常

- [ ] **Step 4: 最终 commit**

```bash
git add -A
git commit -m "feat: Phase 2 complete — marketplace discovery and install/uninstall"
```
