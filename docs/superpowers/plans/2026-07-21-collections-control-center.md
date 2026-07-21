# Collections + 控制台 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地分组(Collections)+ 控制台卡片墙,同时连根拔除检视器(app 层 + SkillsKernel + skm CLI + adapter spec)。

**Architecture:** 磁盘是挂载状态的真相(symlink 存在与否);SwiftData `CollectionRecord` 只记分组成员与"装载意图";`ActivationService` 负责 symlink 挂载/卸载/实体迁移,纯函数 `status(intentMounted:linkedCount:memberCount:)` 供 UI 状态灯。UI 新增控制台(默认落地页)与组详情页,复用现有 SkillListView/SkillRow。

**Tech Stack:** SwiftUI + Swift 6,SwiftData,macOS 14+,SPM(swift build/test),xcodegen + xcodebuild。

**Spec:** `docs/superpowers/specs/2026-07-21-collections-control-center-design.md`

## Global Constraints

- 版本控制用 **jj**(不用 git commit):每个任务的提交步写 `jj describe -m "..." && jj new`(jj 仓库身份已配好 repo-local:yibie / yibie@outlook.com)
- 不引入新第三方依赖;Task 3 移除 Yams
- 新 UI 文案遵循现有风格(界面中英文混排,沿用现状)
- 每个任务结束必须 `swift build && swift test` 全绿再提交
- 绝不经用户操作之外的途径自动改磁盘(意图 vs 磁盘不一致只提示)

---

### Task 1: 拆除检视器 — app 层

**Files:**
- Delete: `SkillsManager/Views/InspectorView.swift`
- Delete: `SkillsManager/Services/InspectorViewModel.swift`
- Delete: `SkillsManager/Models/InspectorPresentation.swift`
- Delete: `Tests/SkillsManagerTests/InspectorViewModelTests.swift`
- Delete: `Tests/SkillsManagerTests/InspectorSnapshotTests.swift`
- Modify: `SkillsManager/Models/SidebarFilter.swift`
- Modify: `SkillsManager/Views/SidebarView.swift:96-98`
- Modify: `SkillsManager/Views/ContentView.swift`
- Modify: `SkillsManager/Views/SkillListView.swift:46`
- Modify: `SkillsManager/Models/SkillConflict.swift:67` 附近(若有 `.inspector` 分支)

**Interfaces:**
- Consumes: 无
- Produces: `SidebarFilter` 不再含 `.inspector`;ContentView 不再含 `inspectorModel`

- [ ] **Step 1: 删除 5 个文件**

```bash
rm SkillsManager/Views/InspectorView.swift \
   SkillsManager/Services/InspectorViewModel.swift \
   SkillsManager/Models/InspectorPresentation.swift \
   Tests/SkillsManagerTests/InspectorViewModelTests.swift \
   Tests/SkillsManagerTests/InspectorSnapshotTests.swift
```

- [ ] **Step 2: SidebarFilter 删 `.inspector`**

`SkillsManager/Models/SidebarFilter.swift` 中:
- 枚举删 `case inspector`
- `title` switch 删 `case .inspector: "检视器"`
- `icon` switch 删 `case .inspector: "eye"`

- [ ] **Step 3: SidebarView 删 Tools 区**

删 `SkillsManager/Views/SidebarView.swift:96-98`:

```swift
            Section("Tools") {
                SidebarRow(filter: .inspector, count: 0, selectedFilter: selectedFilter)
            }
```

- [ ] **Step 4: ContentView 删检视器路由**

删:
- `@State private var inspectorModel = InspectorViewModel()`(第 14 行)
- content 分支 `} else if selectedFilter == .inspector { InspectorView(model: inspectorModel) }`
- detail 分支 `} else if selectedFilter == .inspector { InspectorDetailView(model: inspectorModel) }`
- `currentSelectedSkill` switch 中 `.inspector` 所在 case 组改为 `case .discover, .agentDocs, .conflicts:`

AgentHomeView 调用处(Task 2 才拆卡片,本步先把编译补上):调用改为不传 `specEntry`/`onOpenInspector` —— 即删掉调用中的 `specEntry: AgentHomeSupport.specEntry(...)` 参数与 `onOpenInspector: { ... }` 闭包。**注意:AgentHomeView 本体的对应参数在 Task 2 删除,本步同时临时保留 AgentHomeView 签名不变会编译错误,所以本步直接把 Task 2 Step 1 的 AgentHomeView 签名修改一并做掉(删 `specEntry` 属性与 `inspectorCard` 引用),卡片视图代码留到 Task 2 删。** 为减少任务间耦合,直接按 Task 2 的完整 AgentHomeView 终态改(见 Task 2 Step 1 完整代码),本步即应用终态。

- [ ] **Step 5: SkillListView / SkillConflict 删 `.inspector` 分支**

`SkillsManager/Views/SkillListView.swift:46` `filteredSkills` switch:
- `case .discover, .project, .agentDocs, .inspector, .conflicts:` → `case .discover, .project, .agentDocs, .conflicts:`

`SkillsManager/Models/SkillConflict.swift` 与 `SkillsManager/Models/SidebarFilter.swift` 的其他 switch(如 `title`/`icon` 已处理)全局搜一遍:

```bash
grep -rn "\.inspector" SkillsManager/ Tests/SkillsManagerTests/ || echo "no .inspector left"
```

- [ ] **Step 6: 构建+测试全绿**

```bash
swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run with|error"
```
Expected: Build complete;全部 suite passed(InspectorViewModelTests/InspectorSnapshotTests 已不存在)

- [ ] **Step 7: Commit**

```bash
jj describe -m "Remove inspector app layer (view, view model, presentation, tests)" && jj new
```

---

### Task 2: Agent 主页拆"实际加载"卡

**Files:**
- Modify: `SkillsManager/Views/AgentHomeView.swift`
- Modify: `Tests/SkillsManagerTests/AgentHomeTests.swift`
- Modify: `Tests/SkillsManagerTests/AgentHomeSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 1 的 ContentView 终态
- Produces: `AgentHomeView(agentName:skills:conflicts:selectedSkill:onInstall:onUninstall:onToggleStar:onShowConflicts:)`;`AgentHomeSupport.conflicts(involving:from:)`(保留)

- [ ] **Step 1: AgentHomeView 终态**

完整文件替换 `SkillsManager/Views/AgentHomeView.swift`:

```swift
import SwiftUI
import AppKit

// MARK: - Agent 主页(IA 重组 v1)
// 侧边栏 Agents 从过滤器升级为目的地:每个 agent 一个主页——看懂它(检测状态、
// skills 目录),打理它(skills 列表 + 冲突)。Skills 区完整复用 SkillListView
// (搜索/星标/右键/批量)。

/// AgentHomeView 的纯逻辑,抽出来便于单元测试。
enum AgentHomeSupport {
    /// 涉及某 agent 的冲突(该 agent 的目录里有分叉副本)。
    static func conflicts(involving agentName: String, from conflicts: [SkillConflict]) -> [SkillConflict] {
        conflicts.filter { conflict in
            conflict.instances.contains { $0.agents.contains(agentName) }
        }
    }
}

struct AgentHomeView: View {
    let agentName: String
    let skills: [Skill]
    let conflicts: [SkillConflict]
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onToggleStar: (Skill) -> Void
    let onShowConflicts: () -> Void

    private var definition: AgentDefinition? {
        AgentRegistry.all.first { $0.displayName == agentName }
    }

    private var isDetected: Bool {
        AgentRegistry.installedAgents().contains { $0.displayName == agentName }
    }

    private var agentConflicts: [SkillConflict] {
        AgentHomeSupport.conflicts(involving: agentName, from: conflicts)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                headerCard
                if !agentConflicts.isEmpty {
                    conflictsCard
                }
            }
            .padding(12)

            Divider()

            SkillListView(
                skills: skills,
                filter: .agent(agentName),
                selectedSkill: $selectedSkill,
                onInstall: onInstall,
                onUninstall: onUninstall,
                onToggleStar: onToggleStar
            )
        }
        .navigationTitle(agentName)
    }

    // MARK: 头部卡片

    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: definition?.icon ?? "cpu")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                if let dir = definition.map({ AgentRegistry.resolvedSkillsDir(for: $0) }) {
                    Text(abbreviate(dir.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            SkillMetaBadge(
                text: isDetected ? "已检测" : "未检测到安装",
                tint: isDetected ? .green : .secondary
            )
            if let dir = definition.map({ AgentRegistry.resolvedSkillsDir(for: $0) }) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show skills directory in Finder")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dir.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy skills directory path")
            }
        }
        .cardStyle()
    }

    // MARK: 冲突卡片

    private var conflictsCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(agentConflicts.count) 个技能冲突")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(agentConflicts.map(\.name).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("查看", action: onShowConflicts)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .cardStyle()
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 8))
    }
}
```

同时 `ContentView.swift` 的 AgentHomeView 调用(Task 1 已改)终态为:

```swift
            } else if case .agent(let name) = selectedFilter {
                AgentHomeView(
                    agentName: name,
                    skills: store.skills,
                    conflicts: store.conflicts,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) },
                    onShowConflicts: { selectedFilter = .conflicts }
                )
            } else {
```

- [ ] **Step 2: AgentHomeTests 只留冲突过滤**

完整文件替换 `Tests/SkillsManagerTests/AgentHomeTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManager

struct AgentHomeTests {
    private func conflict(name: String, agents: [String]) -> SkillConflict {
        SkillConflict(
            name: name,
            instances: [
                SkillConflictInstance(path: "/a/\(name)", agents: agents, contentHash: "aaaa"),
                SkillConflictInstance(path: "/b/\(name)", agents: ["Other"], contentHash: "bbbb"),
            ]
        )
    }

    @Test
    func conflictsInvolvingAgentAreFiltered() {
        let conflicts = [
            conflict(name: "commit", agents: ["Claude Code"]),
            conflict(name: "done", agents: ["Cursor"]),
        ]
        let forClaude = AgentHomeSupport.conflicts(involving: "Claude Code", from: conflicts)
        #expect(forClaude.map(\.name) == ["commit"])
        #expect(AgentHomeSupport.conflicts(involving: "Nobody", from: conflicts).isEmpty)
    }
}
```

- [ ] **Step 3: 快照测试改为两卡版**

完整文件替换 `Tests/SkillsManagerTests/AgentHomeSnapshotTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// Offscreen visual-acceptance harness for the agent home page: renders
/// AgentHomeView (header card + optional conflict card + skill list) to /tmp
/// for eyeballing:
///   swift test --filter AgentHomeSnapshot
/// The hosting view is placed in a real (parked offscreen) NSWindow and the run
/// loop is pumped before caching — AgentHomeView embeds a full SkillListView
/// and its buttons/card borders otherwise render incompletely.
struct AgentHomeSnapshotTests {
    @MainActor
    private func renderPNG<V: View>(_ view: V, size: NSSize) throws -> Data {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test @MainActor
    func agentHomeWithConflict() throws {
        let conflict = SkillConflict(
            name: "commit",
            instances: [
                SkillConflictInstance(path: "/a/commit", agents: ["Claude Code"], contentHash: "aaaa"),
                SkillConflictInstance(path: "/b/commit", agents: ["Cursor"], contentHash: "bbbb"),
            ]
        )
        let png = try renderPNG(AgentHomeView(
            agentName: "Claude Code",
            skills: Skill.mockSkills,
            conflicts: [conflict],
            selectedSkill: .constant(nil),
            onInstall: { _ in },
            onUninstall: { _ in },
            onToggleStar: { _ in },
            onShowConflicts: {}
        ), size: NSSize(width: 560, height: 800))
        try png.write(to: URL(fileURLWithPath: "/tmp/agent-home.png"))
    }
}
```

- [ ] **Step 4: 构建+测试全绿,快照目检**

```bash
swift test --filter AgentHome 2>&1 | grep -E "Test run with|error" && ls -la /tmp/agent-home.png
```
Expected: 2 suites passed(AgentHomeTests + AgentHomeSnapshotTests);PNG 已生成。用 Read 工具查看 `/tmp/agent-home.png`,确认:头部卡(含两个按钮)、冲突卡、无"实际加载"卡。

- [ ] **Step 5: Commit**

```bash
jj describe -m "Drop inspector card from agent home page" && jj new
```

---

### Task 3: 拆除检视器 — kernel + skm + 包定义

**Files:**
- Delete: `Sources/SkillsKernel/`(整目录)
- Delete: `Sources/skm/`(整目录)
- Delete: `Tests/SkillsKernelTests/`(整目录)
- Modify: `Package.swift`
- Modify: `project.yml`( SkillsManager target 的 SkillsKernel product 依赖)
- Regenerate: `SkillsManager.xcodeproj`

**Interfaces:**
- Consumes: Task 1-2(app 已不再 import SkillsKernel)
- Produces: 无 kernel/skm;Yams 依赖移除

- [ ] **Step 1: 确认 app 无残留引用**

```bash
grep -rn "import SkillsKernel" SkillsManager/ Tests/SkillsManagerTests/ || echo "clean"
grep -rn "SkillsKernel\|SpecCatalog\|AdapterSpec\|EffectiveAgent" SkillsManager/ Tests/SkillsManagerTests/ || echo "clean"
```
Expected: 两个都输出 clean。若不 clean,回到 Task 1/2 补删。

- [ ] **Step 2: 删目录**

```bash
rm -rf Sources/SkillsKernel Sources/skm Tests/SkillsKernelTests
```

- [ ] **Step 3: Package.swift 终态**

完整文件替换 `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillsManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SkillsManager", targets: ["SkillsManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/LiYanan2004/MarkdownView", from: "2.6.1"),
    ],
    targets: [
        .executableTarget(
            name: "SkillsManager",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "MarkdownView", package: "MarkdownView"),
            ],
            path: "SkillsManager",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SkillsManagerTests",
            dependencies: ["SkillsManager"],
            path: "Tests/SkillsManagerTests"
        ),
    ]
)
```

同时删掉 app target 里对 SkillsKernel 的 import(若有遗漏,Step 1 已保证没有)。

- [ ] **Step 4: project.yml 删 SkillsKernel 依赖**

`project.yml` SkillsManager target 的 dependencies 删:

```yaml
      - package: SkillsManagerPackage
        product: SkillsKernel
```

同时删文件顶部 packages 里的本地包声明:

```yaml
  # 本地根 Package:提供 SkillsKernel(Effective-Agent 检视器内核,
  # 含 platform-specs 打包资源;Bundle.module 由 SPM 自动处理)
  SkillsManagerPackage:
    path: .
```

- [ ] **Step 5: 重新生成工程并全量验证**

```bash
swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run with|error"
xcodegen && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2
```
Expected: Build complete;全部 suite passed;`** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
jj describe -m "Remove SkillsKernel, skm CLI, and adapter specs (inspector teardown)" && jj new
```

---

### Task 4: CollectionRecord 数据模型

**Files:**
- Create: `SkillsManager/Models/Collection.swift`
- Modify: `SkillsManager/SkillsManagerApp.swift:13-15`
- Test: `Tests/SkillsManagerTests/CollectionTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `CollectionRecord`(id: UUID, name: String, sortOrder: Int, memberSkillIDs: [String], mountedAgentIDs: [String], projectPaths: [String])——Task 6-8 全部依赖

- [ ] **Step 1: 写失败测试**

创建 `Tests/SkillsManagerTests/CollectionTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import SkillsManager

struct CollectionTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test @MainActor
    func recordPersistsMembersAndIntent() throws {
        let context = try makeContext()
        let record = CollectionRecord(
            name: "iOS 开发",
            sortOrder: 0,
            memberSkillIDs: ["local:commit", "plugin:cache:swiftui-expert"],
            mountedAgentIDs: ["claude-code"]
        )
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CollectionRecord>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "iOS 开发")
        #expect(fetched[0].memberSkillIDs == ["local:commit", "plugin:cache:swiftui-expert"])
        #expect(fetched[0].mountedAgentIDs == ["claude-code"])
        #expect(fetched[0].projectPaths.isEmpty)
    }

    @Test @MainActor
    func memberMutationRoundTrips() throws {
        let context = try makeContext()
        let record = CollectionRecord(name: "写作")
        context.insert(record)
        try context.save()

        record.memberSkillIDs.append("local:renwei-writing")
        record.mountedAgentIDs.append("codex")
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CollectionRecord>())
        #expect(fetched[0].memberSkillIDs == ["local:renwei-writing"])
        #expect(fetched[0].mountedAgentIDs == ["codex"])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
swift test --filter CollectionTests 2>&1 | tail -3
```
Expected: 编译错误 "cannot find 'CollectionRecord' in scope"

- [ ] **Step 3: 实现模型**

创建 `SkillsManager/Models/Collection.swift`:

```swift
import Foundation
import SwiftData

// 分组:用户自定义的技能集合 + 装载意图(希望挂载到哪些 agent)。
// 磁盘是挂载状态的真相;mountedAgentIDs 只记意图,供 reconcile 对比。
@Model
final class CollectionRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var memberSkillIDs: [String]      // skill.id("{source}:{name}")
    var mountedAgentIDs: [String]     // AgentRegistry id(装载意图)
    /// 预留:Phase 2 工作区绑定。
    var projectPaths: [String]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        memberSkillIDs: [String] = [],
        mountedAgentIDs: [String] = [],
        projectPaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.memberSkillIDs = memberSkillIDs
        self.mountedAgentIDs = mountedAgentIDs
        self.projectPaths = projectPaths
    }
}
```

`SkillsManager/SkillsManagerApp.swift` schema 注册(13-15 行):

```swift
        let schema = Schema([
            SkillRecord.self,
            CollectionRecord.self,
        ])
```

- [ ] **Step 4: 跑测试确认通过**

```bash
swift test --filter CollectionTests 2>&1 | grep -E "Test run with|error"
```
Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
jj describe -m "Add CollectionRecord model for skill groups" && jj new
```

---

### Task 5: ActivationService(挂载/卸载/迁移/状态灯)

**Files:**
- Create: `SkillsManager/Services/ActivationService.swift`
- Test: `Tests/SkillsManagerTests/ActivationServiceTests.swift`

**Interfaces:**
- Consumes: `Skill`(`id`/`name`/`source`/`directoryPath`/`canonicalPath`)、`AgentRegistry.canonicalGlobalSkillsDir`、`SymlinkInstaller.sanitize(_:)`、`SymlinkInstaller.managedMarkerName`
- Produces:
  - `enum MountStatus: String, Sendable { case unmounted, mounted, diverged }`
  - `struct MountReport: Equatable, Sendable { struct Skipped: Equatable, Sendable { let skillID: String; let reason: String }; var changed: [String]; var skipped: [Skipped] }`
  - `ActivationService.status(intentMounted: Bool, linkedCount: Int, memberCount: Int) -> MountStatus`
  - `ActivationService.mount(skills: [Skill], agentSkillsDir: URL, canonicalDir: URL) throws -> MountReport`
  - `ActivationService.unmount(skills: [Skill], agentSkillsDir: URL, canonicalDir: URL) -> MountReport`
  - `ActivationService.probeLinkedCount(memberSkills: [Skill], agentSkillsDir: URL, canonicalDir: URL) -> Int`
  —— Task 6-8 的 UI 全部经由这些签名接线

- [ ] **Step 1: 写失败测试**

创建 `Tests/SkillsManagerTests/ActivationServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManager

struct ActivationServiceTests {
    private func makeSandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("activation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 在 originDir 下造一个实体技能目录(source: .local)。
    private func makeLocalSkill(name: String, originDir: URL) throws -> Skill {
        let dir = originDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# \(name)".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return Skill(
            id: "local:\(name)",
            name: name,
            displayName: name,
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: dir.appendingPathComponent("SKILL.md"),
            directoryPath: dir,
            compatibleAgents: [],
            tags: [],
            markdownContent: "# \(name)",
            frontmatter: [:]
        )
    }

    // MARK: status 纯函数

    @Test
    func statusMatrix() {
        #expect(ActivationService.status(intentMounted: true, linkedCount: 3, memberCount: 3) == .mounted)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 0, memberCount: 3) == .unmounted)
        #expect(ActivationService.status(intentMounted: true, linkedCount: 1, memberCount: 3) == .diverged)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 2, memberCount: 3) == .diverged)
        #expect(ActivationService.status(intentMounted: true, linkedCount: 0, memberCount: 0) == .diverged)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 0, memberCount: 0) == .unmounted)
    }

    // MARK: 挂载:实体技能迁移 canonical + 原处留 link + 目标 agent 挂 link

    @Test
    func mountMigratesEntitySkillAndLinksBothSides() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skill = try makeLocalSkill(name: "commit", originDir: origin)

        let report = try ActivationService.mount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:commit"])
        #expect(report.skipped.isEmpty)

        let fm = FileManager.default
        // canonical 持有实体
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/SKILL.md").path))
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/\(SymlinkInstaller.managedMarkerName)").path))
        // 原处变成指向 canonical 的 link(原 agent 不受影响)
        let originDest = try fm.destinationOfSymbolicLink(atPath: origin.appendingPathComponent("commit").path)
        #expect(originDest == canonical.appendingPathComponent("commit").path)
        // 目标 agent 挂上 link
        let agentDest = try fm.destinationOfSymbolicLink(atPath: agentDir.appendingPathComponent("commit").path)
        #expect(agentDest == canonical.appendingPathComponent("commit").path)
        #expect(ActivationService.probeLinkedCount(memberSkills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical) == 1)
    }

    // MARK: 冲突:目标已有同名实体 → 跳过不阻塞

    @Test
    func mountSkipsConflictingRealDirectory() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skillA = try makeLocalSkill(name: "commit", originDir: origin)
        let skillB = try makeLocalSkill(name: "done", originDir: origin)
        // 目标 agent 已有同名实体目录(非 link)
        let conflictDir = agentDir.appendingPathComponent("commit")
        try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        try "other".write(to: conflictDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let report = try ActivationService.mount(skills: [skillA, skillB], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:done"])
        #expect(report.skipped.count == 1)
        #expect(report.skipped[0].skillID == "local:commit")
        // 冲突目录原样保留
        #expect(try String(contentsOf: conflictDir.appendingPathComponent("SKILL.md"), encoding: .utf8) == "other")
    }

    // MARK: 卸载:只删 link,canonical 保留;实体目录不动

    @Test
    func unmountRemovesLinkButKeepsCanonicalAndRealDirs() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skill = try makeLocalSkill(name: "commit", originDir: origin)
        _ = try ActivationService.mount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)

        let report = ActivationService.unmount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:commit"])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: agentDir.appendingPathComponent("commit").path))
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/SKILL.md").path))

        // 实体目录(非 link)不删,记 skipped
        let realDir = agentDir.appendingPathComponent("realone")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let realSkill = Skill(
            id: "local:realone", name: "realone", displayName: "realone",
            baseDescription: "", baseDescriptionLocale: "en", localizedDescription: nil,
            source: .local, version: nil,
            filePath: realDir.appendingPathComponent("SKILL.md"), directoryPath: realDir,
            compatibleAgents: [], tags: [], markdownContent: "", frontmatter: [:]
        )
        let report2 = ActivationService.unmount(skills: [realSkill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report2.skipped.count == 1)
        #expect(fm.fileExists(atPath: realDir.path))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
swift test --filter ActivationServiceTests 2>&1 | tail -3
```
Expected: 编译错误 "cannot find 'ActivationService' in scope"

- [ ] **Step 3: 实现 ActivationService**

创建 `SkillsManager/Services/ActivationService.swift`:

```swift
import Foundation

enum MountStatus: String, Sendable {
    case unmounted   // 意图未挂载且磁盘无 link
    case mounted     // 意图挂载且磁盘全部就位
    case diverged    // 其余:意图与磁盘不一致(或部分挂载)
}

struct MountReport: Equatable, Sendable {
    struct Skipped: Equatable, Sendable {
        let skillID: String
        let reason: String
    }
    var changed: [String] = []
    var skipped: [Skipped] = []

    var summaryText: String {
        var parts: [String] = []
        if !changed.isEmpty { parts.append("成功 \(changed.count) 个") }
        if !skipped.isEmpty {
            let reasons = skipped.map { "\($0.skillID)(\($0.reason))" }.joined(separator: "、")
            parts.append("跳过 \(skipped.count) 个:\(reasons)")
        }
        return parts.isEmpty ? "无变化" : parts.joined(separator: ",")
    }
}

/// 分组挂载服务:把技能 symlink 进 agent 目录(挂载)或移除 link(卸载)。
/// canonical(~/.config/agents/skills/)是库的本体,永远不删。
/// 实体技能(.local)挂载前先迁移进 canonical,原处留 link,原 agent 不受影响。
enum ActivationService {

    /// 状态灯纯函数:意图 + 磁盘事实 → 卡片/开关状态。
    static func status(intentMounted: Bool, linkedCount: Int, memberCount: Int) -> MountStatus {
        guard memberCount > 0 else { return intentMounted ? .diverged : .unmounted }
        if intentMounted && linkedCount == memberCount { return .mounted }
        if !intentMounted && linkedCount == 0 { return .unmounted }
        return .diverged
    }

    /// 数成员技能里有多少个在 agentSkillsDir 已有指向 canonical 的 link。
    static func probeLinkedCount(
        memberSkills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) -> Int {
        memberSkills.reduce(0) { count, skill in
            let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            guard isLink(link, pointingTo: canonicalPath(for: skill, canonicalDir: canonicalDir), fm: fm)
            else { return count }
            return count + 1
        }
    }

    /// 挂载:确保每个技能有 canonical 副本,再在 agentSkillsDir 建 link。
    /// 冲突(目标已有同名实体)跳过该技能并记录,不阻塞整组。
    static func mount(
        skills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) throws -> MountReport {
        var report = MountReport()
        try fm.createDirectory(at: agentSkillsDir, withIntermediateDirectories: true)
        for skill in skills {
            do {
                let canonical = try ensureCanonical(skill: skill, canonicalDir: canonicalDir, fm: fm)
                let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
                try createLink(from: canonical, at: link, fm: fm)
                report.changed.append(skill.id)
            } catch ActivationError.conflict(let url) {
                report.skipped.append(.init(skillID: skill.id, reason: "目标已存在 \(url.lastPathComponent)"))
            }
        }
        return report
    }

    /// 卸载:删 agentSkillsDir 里指向 canonical 的 link;实体目录不动;canonical 保留。
    static func unmount(
        skills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) -> MountReport {
        var report = MountReport()
        for skill in skills {
            let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            let canonical = canonicalPath(for: skill, canonicalDir: canonicalDir)
            if isLink(link, pointingTo: canonical, fm: fm) {
                try? fm.removeItem(at: link)
                report.changed.append(skill.id)
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                report.skipped.append(.init(skillID: skill.id, reason: "实体目录不删除"))
            }
        }
        return report
    }

    // MARK: - 内部

    enum ActivationError: LocalizedError {
        case conflict(URL)
        var errorDescription: String? {
            switch self {
            case .conflict(let url): "A file or directory already exists at \(url.path)."
            }
        }
    }

    static func canonicalPath(for skill: Skill, canonicalDir: URL) -> URL {
        skill.canonicalPath ?? canonicalDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
    }

    /// 确保技能在 canonical 有实体副本:.local 实体迁移(原处留 link);
    /// 其他来源(plugin 等只读缓存)写内容副本。已有 canonical 直接返回。
    private static func ensureCanonical(skill: Skill, canonicalDir: URL, fm: FileManager) throws -> URL {
        let dest = canonicalDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        if let existing = skill.canonicalPath,
           (try? fm.attributesOfItem(atPath: existing.path)) != nil {
            return existing
        }
        if (try? fm.attributesOfItem(atPath: dest.path)) != nil {
            guard SymlinkInstaller.isManagedCanonicalDirectory(dest, fm: fm) else {
                throw ActivationError.conflict(dest)
            }
            return dest
        }

        try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        if case .local = skill.source,
           (try? fm.attributesOfItem(atPath: skill.directoryPath.path)) != nil {
            // 迁移实体:原位置变 link,原 agent 无感知
            try fm.moveItem(at: skill.directoryPath, to: dest)
        } else {
            // 只读来源:写内容副本
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try skill.markdownContent.write(
                to: dest.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        try "1\n".write(
            to: dest.appendingPathComponent(SymlinkInstaller.managedMarkerName),
            atomically: true,
            encoding: .utf8
        )
        if case .local = skill.source {
            try fm.createSymbolicLink(atPath: skill.directoryPath.path, withDestinationPath: dest.path)
        }
        return dest
    }

    private static func createLink(from canonical: URL, at link: URL, fm: FileManager) throws {
        if (try? fm.attributesOfItem(atPath: link.path)) != nil {
            guard isLink(link, pointingTo: canonical, fm: fm) else {
                throw ActivationError.conflict(link)
            }
            return // 已挂好,幂等
        }
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: canonical.path)
    }

    private static func isLink(_ link: URL, pointingTo target: URL, fm: FileManager) -> Bool {
        guard let raw = try? fm.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let destination: URL = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : link.deletingLastPathComponent().appendingPathComponent(raw)
        return destination.resolvingSymlinksInPath().standardizedFileURL.path
            == target.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
swift test --filter ActivationServiceTests 2>&1 | grep -E "Test run with|error|failed"
```
Expected: 4 tests passed

- [ ] **Step 5: Commit**

```bash
jj describe -m "Add ActivationService for collection mount/unmount via symlinks" && jj new
```

---

### Task 6: 控制台基础设施 + 卡片墙

**Files:**
- Modify: `SkillsManager/Models/SidebarFilter.swift`
- Modify: `SkillsManager/Views/SkillListView.swift`(memberIDs 参数 + 新 case 分支)
- Modify: `SkillsManager/Services/SkillStore.swift`(mountStatuses 缓存)
- Create: `SkillsManager/Views/ControlCenterView.swift`
- Modify: `SkillsManager/Views/SidebarView.swift:49`
- Modify: `SkillsManager/Views/ContentView.swift`

**Interfaces:**
- Consumes: `CollectionRecord`(Task 4)、`MountStatus`/`MountReport`/`ActivationService`(Task 5)、`AgentRegistry.agent(id:)`、`AgentRegistry.resolvedSkillsDir(for:)`
- Produces:
  - `SidebarFilter.controlCenter`、`SidebarFilter.collection(UUID, name: String)`
  - `SkillListView(..., memberIDs: Set<String>? = nil, ...)`
  - `SkillStore.mountStatus(collectionID: UUID, agentID: String) -> MountStatus`、`SkillStore.refreshMountStatuses(collections: [CollectionRecord])`
  - `ControlCenterView(collections:skills:detectedAgents:statusFor:onOpen:onCreate:onToggleAgent:onReapply:onRename:onDelete:)`
  —— Task 7 依赖以上全部

- [ ] **Step 1: SidebarFilter 加两个 case**

`SkillsManager/Models/SidebarFilter.swift` 终态:

```swift
import Foundation

enum SidebarFilter: Hashable, Sendable {
    case controlCenter
    case discover
    case all
    case installed
    case starred
    case trial
    case conflicts
    case project
    case agentDocs
    case agent(String)
    case source(String)
    case collection(UUID, name: String)

    var title: String {
        switch self {
        case .controlCenter:        "控制台"
        case .discover:             "Discover"
        case .all:                  "All Skills"
        case .installed:            "Installed"
        case .starred:              "Starred"
        case .trial:                "Trial"
        case .conflicts:            "Conflicts"
        case .project:              "Project"
        case .agentDocs:            "Agent Docs"
        case .agent(let name):      name
        case .source(let name):     name
        case .collection(_, let name): name
        }
    }

    var icon: String {
        switch self {
        case .controlCenter: "switch.2"
        case .discover:      "safari"
        case .all:           "square.grid.2x2"
        case .installed:     "checkmark.circle"
        case .starred:       "star.fill"
        case .trial:         "flask"
        case .conflicts:     "exclamationmark.triangle"
        case .project:       "folder"
        case .agentDocs:     "doc.text"
        case .agent:         "cpu"
        case .source:        "shippingbox"
        case .collection:    "folder.fill"
        }
    }
}
```

- [ ] **Step 2: SkillListView 支持 memberIDs 与新 case**

`SkillsManager/Views/SkillListView.swift` 的属性区(19-24 行)加:

```swift
    let memberIDs: Set<String>?  // filter == .collection 时的成员白名单;nil 视为空
```

并把声明改为带默认值(在 `let onToggleStar` 之后追加两个可选参数,Task 7/8 用):

```swift
    var onAddToCollection: ((Skill) -> Void)? = nil
    var onRemoveFromCollection: ((Skill) -> Void)? = nil
```

memberIDs 声明给默认值以免改所有调用点——改为:

```swift
    var memberIDs: Set<String>? = nil
```

`filteredSkills` switch 终态:

```swift
    private var filteredSkills: [Skill] {
        switch filter {
        case .controlCenter, .discover, .project, .agentDocs, .conflicts:
            return []
        case .all:
            return selectedAllSkillsTab == .plugin ? pluginSkills : standaloneSkills
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
                case .local: name.lowercased() == "local"
                case .openClaw: name.lowercased() == "openclaw"
                case .symlinked: name.lowercased() == "symlinked"
                case .plugin(let pluginSource, _): pluginSource.lowercased() == name.lowercased()
                case .projectLocal: false
                }
            }
        case .collection:
            return skills.filter { memberIDs?.contains($0.id) ?? false }
        }
    }
```

- [ ] **Step 3: SkillStore 挂载状态缓存**

`SkillsManager/Services/SkillStore.swift` 属性区(约 206 行 `var errorMessage` 后)加:

```swift
    /// 挂载状态缓存:key 见 mountStatusKey;由 refreshMountStatuses 重建。
    var mountStatuses: [String: MountStatus] = [:]
```

文件末尾加:

```swift
    // MARK: - Collection mount status

    func mountStatus(collectionID: UUID, agentID: String) -> MountStatus {
        mountStatuses["\(collectionID.uuidString):\(agentID)"] ?? .unmounted
    }

    /// 以磁盘为准重建所有「组 × agent」的状态灯数据。skills 刷新或分组变更后调用。
    func refreshMountStatuses(collections: [CollectionRecord]) {
        var map: [String: MountStatus] = [:]
        for collection in collections {
            let members = collection.memberSkillIDs.compactMap { id in skills.first { $0.id == id } }
            for agentID in Set(collection.mountedAgentIDs) {
                guard let definition = AgentRegistry.agent(id: agentID) else { continue }
                let linked = ActivationService.probeLinkedCount(
                    memberSkills: members,
                    agentSkillsDir: AgentRegistry.resolvedSkillsDir(for: definition)
                )
                map["\(collection.id.uuidString):\(agentID)"] = ActivationService.status(
                    intentMounted: true,
                    linkedCount: linked,
                    memberCount: members.count
                )
            }
        }
        mountStatuses = map
    }
```

- [ ] **Step 4: ControlCenterView(卡片墙)**

创建 `SkillsManager/Views/ControlCenterView.swift`:

```swift
import SwiftUI

// MARK: - 控制台(默认落地页)
// 一进来只看到分组和当前挂载状态;大库退到侧栏 Library。卡片只列出
// 「装载意图」内的 agent 行(组 × agent 才可能几十个,列全量 45 个 agent
// 不现实),其余经「＋ 挂载到」菜单添加。

struct ControlCenterView: View {
    let collections: [CollectionRecord]
    let skills: [Skill]
    let detectedAgents: [AgentDefinition]
    let statusFor: (CollectionRecord, String) -> MountStatus
    let onOpen: (CollectionRecord) -> Void
    let onCreate: (String) -> Void
    let onToggleAgent: (CollectionRecord, String, Bool) -> Void
    let onReapply: (CollectionRecord, String) -> Void
    let onRename: (CollectionRecord, String) -> Void
    let onDelete: (CollectionRecord) -> Void

    @State private var isNamingPresented = false
    @State private var newName = ""

    private var summaryText: String {
        var skillMounts = 0
        var agents = Set<String>()
        for collection in collections {
            for agentID in collection.mountedAgentIDs where statusFor(collection, agentID) == .mounted {
                skillMounts += collection.memberSkillIDs.count
                agents.insert(agentID)
            }
        }
        return "\(collections.count) 个分组 · \(skillMounts) 个技能正挂载在 \(agents.count) 个 agent"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("控制台").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button("＋ 新建分组") { isNamingPresented = true }
                }
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(collections, id: \.id) { collection in
                        CollectionCard(
                            collection: collection,
                            detectedAgents: detectedAgents,
                            statusFor: { statusFor(collection, $0) },
                            onOpen: { onOpen(collection) },
                            onToggleAgent: { onToggleAgent(collection, $0, $1) },
                            onReapply: { onReapply(collection, $0) },
                            onRename: { onRename(collection, $0) },
                            onDelete: { onDelete(collection) }
                        )
                    }
                    // 虚线「新建分组」卡收尾(草图 §5.2)
                    Button { isNamingPresented = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title2)
                            Text("新建分组").font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle("控制台")
        .alert("新建分组", isPresented: $isNamingPresented) {
            TextField("组名", text: $newName)
            Button("创建") {
                onCreate(newName)
                newName = ""
            }
            Button("取消", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - 分组卡片

private struct CollectionCard: View {
    let collection: CollectionRecord
    let detectedAgents: [AgentDefinition]
    let statusFor: (String) -> MountStatus
    let onOpen: () -> Void
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isRenamePresented = false
    @State private var renameText = ""

    private var unmountedAgents: [AgentDefinition] {
        detectedAgents.filter { !collection.mountedAgentIDs.contains($0.id) }
    }

    private var statusText: (text: String, isWarning: Bool) {
        guard !collection.mountedAgentIDs.isEmpty else { return ("未挂载", false) }
        let diverged = collection.mountedAgentIDs.filter { statusFor($0) == .diverged }
        if diverged.isEmpty {
            let names = collection.mountedAgentIDs.compactMap { id in
                detectedAgents.first { $0.id == id }?.displayName
            }
            return ("挂载于 \(names.joined(separator: "、")) · 状态正常", false)
        }
        let names = diverged.compactMap { id in detectedAgents.first { $0.id == id }?.displayName }
        return ("\(names.joined(separator: "、")):与磁盘不一致", true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(collection.name).font(.headline)
                Spacer()
                Menu {
                    Button("重命名…") {
                        renameText = collection.name
                        isRenamePresented = true
                    }
                    Divider()
                    Button("删除分组", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            Text("\(collection.memberSkillIDs.count) 个技能")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(collection.mountedAgentIDs, id: \.self) { agentID in
                HStack(spacing: 7) {
                    statusDot(statusFor(agentID))
                    Text(detectedAgents.first { $0.id == agentID }?.displayName ?? agentID)
                        .font(.callout)
                    Spacer()
                    if statusFor(agentID) == .diverged {
                        Button("重新应用") { onReapply(agentID) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    Toggle("", isOn: Binding(
                        get: { true },
                        set: { _ in onToggleAgent(agentID, false) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }

            if !unmountedAgents.isEmpty {
                Menu {
                    ForEach(unmountedAgents, id: \.id) { agent in
                        Button(agent.displayName) { onToggleAgent(agent.id, true) }
                    }
                } label: {
                    Label("挂载到…", systemImage: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }

            Text(statusText.text)
                .font(.caption2)
                .foregroundStyle(statusText.isWarning ? Color.orange : Color.secondary)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .alert("重命名分组", isPresented: $isRenamePresented) {
            TextField("组名", text: $renameText)
            Button("确定") { onRename(renameText) }
            Button("取消", role: .cancel) {}
        }
    }

    private func statusDot(_ status: MountStatus) -> some View {
        Circle()
            .fill(status == .mounted ? Color.green : status == .diverged ? Color.orange : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}
```

- [ ] **Step 5: SidebarView 顶部加控制台行**

`SkillsManager/Views/SidebarView.swift` body 的 `List` 内最前(第 49 行 `Section("Library")` 之前)加:

```swift
            Section {
                SidebarRow(filter: .controlCenter, count: 0, selectedFilter: selectedFilter)
            }

```

- [ ] **Step 6: ContentView 接线**

`SkillsManager/Views/ContentView.swift` 修改:

a) 属性区(第 9 行 `@Query private var skillRecords` 后)加:

```swift
    @Query(sort: \CollectionRecord.sortOrder) private var collectionRecords: [CollectionRecord]
```

b) 默认落地页:`@State private var selectedFilter: SidebarFilter = .all` → `.controlCenter`

c) content 路由最前(`if selectedFilter == .discover` 之前)加:

```swift
            if selectedFilter == .controlCenter {
                ControlCenterView(
                    collections: collectionRecords,
                    skills: store.skills,
                    detectedAgents: AgentRegistry.installedAgents(),
                    statusFor: { store.mountStatus(collectionID: $0.id, agentID: $1) },
                    onOpen: { selectedFilter = .collection($0.id, name: $0.name) },
                    onCreate: { name in createCollection(name: name) },
                    onToggleAgent: { collection, agentID, mount in
                        setMounted(collection: collection, agentID: agentID, mount: mount)
                    },
                    onReapply: { collection, agentID in
                        setMounted(collection: collection, agentID: agentID, mount: true)
                    },
                    onRename: { collection, name in
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { collection.name = trimmed }
                    },
                    onDelete: { collection in
                        modelContext.delete(collection)
                        store.refreshMountStatuses(collections: collectionRecords)
                    }
                )
            } else if selectedFilter == .discover {
```

d) detail 路由:`if selectedFilter == .discover` 之前加:

```swift
            if selectedFilter == .controlCenter {
                ContentUnavailableView(
                    "选择分组",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("在控制台打开分组查看成员,或从 Library 选择技能。")
                )
            } else if selectedFilter == .discover {
```

e) `currentSelectedSkill` switch 终态:

```swift
        switch selectedFilter {
        case .project:
            return store.projectSkills.first { $0.id == selectedSkill.id } ?? selectedSkill
        case .discover, .agentDocs, .conflicts, .controlCenter:
            return selectedSkill
        case .all, .installed, .starred, .trial, .agent, .source, .collection:
            return store.skills.first { $0.id == selectedSkill.id } ?? selectedSkill
        }
```

f) 文件底部(`toggleStar` 前)加辅助方法:

```swift
    // MARK: - Collections

    private func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = CollectionRecord(name: trimmed, sortOrder: collectionRecords.count)
        modelContext.insert(record)
        store.refreshMountStatuses(collections: collectionRecords)
    }

    /// 挂载/卸载 组→agent:先执行磁盘操作,再更新装载意图,最后刷新扫描与状态灯。
    private func setMounted(collection: CollectionRecord, agentID: String, mount: Bool) {
        guard let definition = AgentRegistry.agent(id: agentID) else { return }
        let members = collection.memberSkillIDs.compactMap { id in store.skills.first { $0.id == id } }
        let dir = AgentRegistry.resolvedSkillsDir(for: definition)
        if mount {
            do {
                let report = try ActivationService.mount(skills: members, agentSkillsDir: dir)
                if !collection.mountedAgentIDs.contains(agentID) {
                    collection.mountedAgentIDs.append(agentID)
                }
                if !report.skipped.isEmpty { store.errorMessage = report.summaryText }
            } catch {
                store.errorMessage = error.localizedDescription
                return
            }
        } else {
            let report = ActivationService.unmount(skills: members, agentSkillsDir: dir)
            collection.mountedAgentIDs.removeAll { $0 == agentID }
            if !report.skipped.isEmpty { store.errorMessage = report.summaryText }
        }
        Task { await store.reloadSkills() }
        store.refreshMountStatuses(collections: collectionRecords)
    }
```

g) 状态灯刷新挂钩:`.task { ... }` 里 `_ = await (skills, discover)` 之后加一行:

```swift
            store.refreshMountStatuses(collections: collectionRecords)
```

并新增:

```swift
        .onChange(of: collectionRecords) {
            store.refreshMountStatuses(collections: collectionRecords)
        }
```

- [ ] **Step 7: 构建+测试全绿**

```bash
swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run with|error"
```
Expected: Build complete;全部 suite passed(既有测试不受影响)

- [ ] **Step 8: Commit**

```bash
jj describe -m "Add control center with collection card wall as default landing" && jj new
```

---

### Task 7: 组详情页 + 成员管理 + 快照

**Files:**
- Create: `SkillsManager/Views/CollectionDetailView.swift`(含 MemberPicker)
- Modify: `SkillsManager/Views/SkillListView.swift`(SkillRow 右键接 onRemoveFromCollection)
- Modify: `SkillsManager/Views/ContentView.swift`(`.collection` 路由)
- Test: `Tests/SkillsManagerTests/ConsoleSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 6 全部产物
- Produces: `CollectionDetailView(collection:skills:detectedAgents:statusFor:selectedSkill:onToggleAgent:onReapply:onAddMembers:onRemoveMember:onInstall:onUninstall:onToggleStar:)`

- [ ] **Step 1: CollectionDetailView**

创建 `SkillsManager/Views/CollectionDetailView.swift`:

```swift
import SwiftUI

// MARK: - 组详情
// 头部:组名 + 成员数 + 各已检测 agent 的挂载开关(开 = symlink 进 agent,
// 关 = 仅移除链接,技能留库)。成员列表复用 SkillListView。

struct CollectionDetailView: View {
    let collection: CollectionRecord
    let skills: [Skill]
    let detectedAgents: [AgentDefinition]
    let statusFor: (String) -> MountStatus
    @Binding var selectedSkill: Skill?
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onAddMembers: ([String]) -> Void
    let onRemoveMember: (Skill) -> Void
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onToggleStar: (Skill) -> Void

    @State private var isPickerPresented = false

    private var memberIDs: Set<String> { Set(collection.memberSkillIDs) }

    private var missingCount: Int {
        let known = Set(skills.map(\.id))
        return collection.memberSkillIDs.filter { !known.contains($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(collection.name).font(.headline)
                    Text("\(collection.memberSkillIDs.count) 个技能" + (missingCount > 0 ? " · \(missingCount) 个缺失" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("＋ 添加技能") { isPickerPresented = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(detectedAgents, id: \.id) { agent in
                            agentCapsule(agent)
                        }
                    }
                }
                Text("打开开关 = 组内技能 symlink 进该 agent;关闭 = 仅移除链接,技能保留在库中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            SkillListView(
                skills: skills,
                filter: .collection(collection.id, name: collection.name),
                memberIDs: memberIDs,
                selectedSkill: $selectedSkill,
                onInstall: onInstall,
                onUninstall: onUninstall,
                onToggleStar: onToggleStar,
                onRemoveFromCollection: onRemoveMember
            )
        }
        .navigationTitle(collection.name)
        .sheet(isPresented: $isPickerPresented) {
            MemberPicker(
                candidates: skills.filter { !memberIDs.contains($0.id) },
                onAdd: { ids in
                    onAddMembers(ids)
                    isPickerPresented = false
                }
            )
        }
    }

    private func agentCapsule(_ agent: AgentDefinition) -> some View {
        let mounted = collection.mountedAgentIDs.contains(agent.id)
        let status = statusFor(agent.id)
        return HStack(spacing: 7) {
            Circle()
                .fill(status == .mounted ? Color.green : status == .diverged ? Color.orange : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(agent.displayName).font(.callout)
            if status == .diverged {
                Button("重新应用") { onReapply(agent.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            Toggle("", isOn: Binding(
                get: { mounted },
                set: { onToggleAgent(agent.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - 成员 picker

private struct MemberPicker: View {
    let candidates: [Skill]
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selected: Set<Skill> = []

    private var filtered: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id, selection: $selected) { skill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.displayName)
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(skill)
            }
            .searchable(text: $searchText, prompt: "搜索技能")
            .navigationTitle("添加技能")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加 \(selected.count) 个") {
                        onAdd(selected.map(\.id))
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .frame(width: 440, height: 500)
    }
}
```

- [ ] **Step 2: SkillListView 右键接 onRemoveFromCollection**

`SkillsManager/Views/SkillListView.swift` 的 `SkillRow`(private struct,220 行起)属性加:

```swift
    var onAddToCollection: (() -> Void)? = nil
    var onRemoveFromCollection: (() -> Void)? = nil
```

`SkillRow` 的 `contextMenu` 在 star 按钮后加:

```swift
            if let onAddToCollection {
                Button("Add to Collection…", action: onAddToCollection)
            }
            if let onRemoveFromCollection {
                Button("Remove from Collection", role: .destructive, action: onRemoveFromCollection)
            }
```

`SkillListView` body 中 `SkillRow(...)` 调用处(约 114 行)改为:

```swift
                            SkillRow(
                                skill: skill,
                                onInstall: { Task { await onInstall(skill) } },
                                onUninstall: { Task { await onUninstall(skill) } },
                                onToggleStar: { onToggleStar(skill) },
                                onAddToCollection: onAddToCollection.map { cb in { cb(skill) } },
                                onRemoveFromCollection: onRemoveFromCollection.map { cb in { cb(skill) } }
                            )
```

- [ ] **Step 3: ContentView 加 `.collection` 路由**

content 路由,在 `.agent` 分支之前加:

```swift
            } else if case .collection(let id, _) = selectedFilter,
                      let collection = collectionRecords.first(where: { $0.id == id }) {
                CollectionDetailView(
                    collection: collection,
                    skills: store.skills,
                    detectedAgents: AgentRegistry.installedAgents(),
                    statusFor: { store.mountStatus(collectionID: id, agentID: $0) },
                    selectedSkill: $selectedSkill,
                    onToggleAgent: { agentID, mount in
                        setMounted(collection: collection, agentID: agentID, mount: mount)
                    },
                    onReapply: { agentID in
                        setMounted(collection: collection, agentID: agentID, mount: true)
                    },
                    onAddMembers: { ids in
                        collection.memberSkillIDs.append(contentsOf: ids.filter { !collection.memberSkillIDs.contains($0) })
                        store.refreshMountStatuses(collections: collectionRecords)
                    },
                    onRemoveMember: { skill in
                        collection.memberSkillIDs.removeAll { $0 == skill.id }
                        store.refreshMountStatuses(collections: collectionRecords)
                    },
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) }
                )
            } else if case .agent(let name) = selectedFilter {
```

- [ ] **Step 4: 快照测试**

创建 `Tests/SkillsManagerTests/ConsoleSnapshotTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// Offscreen visual-acceptance for the control center and collection detail
/// (same parked-NSWindow harness as AgentHomeSnapshotTests). PNGs land in /tmp:
///   swift test --filter ConsoleSnapshot
struct ConsoleSnapshotTests {
    @MainActor
    private func renderPNG<V: View>(_ view: V, size: NSSize) throws -> Data {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @MainActor
    private func sampleCollections() -> [CollectionRecord] {
        [
            CollectionRecord(
                name: "iOS 开发",
                sortOrder: 0,
                memberSkillIDs: Skill.mockSkills.map(\.id),
                mountedAgentIDs: ["claude-code"]
            ),
            CollectionRecord(name: "写作", sortOrder: 1, memberSkillIDs: [], mountedAgentIDs: []),
        ]
    }

    @Test @MainActor
    func controlCenterWall() throws {
        let png = try renderPNG(ControlCenterView(
            collections: sampleCollections(),
            skills: Skill.mockSkills,
            detectedAgents: [],
            statusFor: { _, _ in .mounted },
            onOpen: { _ in },
            onCreate: { _ in },
            onToggleAgent: { _, _, _ in },
            onReapply: { _, _ in },
            onRename: { _, _ in },
            onDelete: { _ in }
        ), size: NSSize(width: 720, height: 640))
        try png.write(to: URL(fileURLWithPath: "/tmp/console.png"))
    }

    @Test @MainActor
    func collectionDetail() throws {
        let collection = sampleCollections()[0]
        let png = try renderPNG(CollectionDetailView(
            collection: collection,
            skills: Skill.mockSkills,
            detectedAgents: [],
            statusFor: { _ in .mounted },
            selectedSkill: .constant(nil),
            onToggleAgent: { _, _ in },
            onReapply: { _ in },
            onAddMembers: { _ in },
            onRemoveMember: { _ in },
            onInstall: { _ in },
            onUninstall: { _ in },
            onToggleStar: { _ in }
        ), size: NSSize(width: 560, height: 800))
        try png.write(to: URL(fileURLWithPath: "/tmp/collection-detail.png"))
    }
}
```

- [ ] **Step 5: 构建+测试全绿,快照目检**

```bash
swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run with|error|failed" && ls -la /tmp/console.png /tmp/collection-detail.png
```
Expected: 全部 suite passed;两张 PNG 生成。用 Read 工具查看:控制台(卡片墙、状态灯、"＋ 挂载到"菜单、摘要行)、组详情(agent 开关胶囊、成员列表、"＋ 添加技能")。

- [ ] **Step 6: Commit**

```bash
jj describe -m "Add collection detail page with member picker and agent toggles" && jj new
```

---

### Task 8: 库页右键 "Add to Collection"

**Files:**
- Create: `SkillsManager/Views/CollectionPickerSheet.swift`
- Modify: `SkillsManager/Views/ContentView.swift`(pendingCollectionSkill + sheet + 各 SkillListView 传 onAddToCollection)

**Interfaces:**
- Consumes: Task 7 的 `SkillListView.onAddToCollection`
- Produces: `CollectionPickerSheet(collections:onPick:onCreate:)`

- [ ] **Step 1: CollectionPickerSheet**

创建 `SkillsManager/Views/CollectionPickerSheet.swift`:

```swift
import SwiftUI

/// 把某个技能加入分组的选择器;也可当场新建分组。
struct CollectionPickerSheet: View {
    let collections: [CollectionRecord]
    let onPick: (CollectionRecord) -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isNamingPresented = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections, id: \.id) { collection in
                    Button {
                        onPick(collection)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.memberSkillIDs.count) 个技能")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isNamingPresented = true
                } label: {
                    Label("新建分组…", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .frame(width: 360, height: 420)
        .alert("新建分组", isPresented: $isNamingPresented) {
            TextField("组名", text: $newName)
            Button("创建") {
                onCreate(newName)
                newName = ""
                dismiss()
            }
            Button("取消", role: .cancel) { newName = "" }
        }
    }
}
```

- [ ] **Step 2: ContentView 接线**

a) 属性区加:

```swift
    @State private var pendingCollectionSkill: Skill? = nil
```

b) content 路由的 `else` 分支(库页 SkillListView;组详情与 agent 主页内部的调用保持现状)终态:

```swift
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) },
                    onAddToCollection: { skill in pendingCollectionSkill = skill }
                )
            }
```

c) sheet 注册(其他 `.sheet` 附近)加:

```swift
        .sheet(item: $pendingCollectionSkill) { skill in
            CollectionPickerSheet(
                collections: collectionRecords,
                onPick: { collection in
                    if !collection.memberSkillIDs.contains(skill.id) {
                        collection.memberSkillIDs.append(skill.id)
                        store.refreshMountStatuses(collections: collectionRecords)
                    }
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let record = CollectionRecord(
                        name: trimmed,
                        sortOrder: collectionRecords.count,
                        memberSkillIDs: [skill.id]
                    )
                    modelContext.insert(record)
                    store.refreshMountStatuses(collections: collectionRecords)
                }
            )
        }
```

- [ ] **Step 3: 构建+测试全绿**

```bash
swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Test run with|error"
```
Expected: Build complete;全部 suite passed

- [ ] **Step 4: Commit**

```bash
jj describe -m "Add right-click 'Add to Collection' with picker sheet" && jj new
```

---

### Task 9: 文档与全量验证

**Files:**
- Modify: `README.md`
- Modify: `docs/goals/effective-agent-inspector.md`(标记取消)
- Check: `SkillsManager/Resources/description-translations.json`(仅确认无检视器 UI 串,不改内容型翻译)

**Interfaces:**
- Consumes: Task 1-8 全部
- Produces: 无新代码接口

- [ ] **Step 1: README 更新**

- 删 "What it does" 中的 Inspect 条目(以 `- **Inspect**` 开头的整行)
- agent 主页条目改为(删检视器深链描述):

```markdown
- **Agent home pages** — clicking an agent in the sidebar opens its home: detection status and skills directory (Show in Finder / Copy Path), conflicts involving that agent, and its full skill list
```

- 在 Manage 条目后新增:

```markdown
- **Group skills into collections** and mount a collection into an agent only when needed — symlinks in, links out, the library stays put (sidebar → 控制台)
```

- [ ] **Step 2: goal 文档标记取消**

`docs/goals/effective-agent-inspector.md` 文件最前加:

```markdown
> **STATUS: CANCELLED (2026-07-21)** — 检视器方向经复盘判定为伪需求,M4(45 平台 spec 覆盖)取消,实现已移除。本文档仅作历史存档。见 docs/superpowers/specs/2026-07-21-collections-control-center-design.md。
```

- [ ] **Step 3: translations 检查**

```bash
grep -o '"[^"]*inspector[^"]*"' SkillsManager/Resources/description-translations.json | head
grep -c "检视器" SkillsManager/Resources/description-translations.json || true
```
Expected: 该文件是技能**描述**翻译目录,若命中的是描述内容(而非检视器 UI 串),不做改动,在提交信息中注明。仅当存在明确的检视器 UI key 时才删除对应条目,删后 `python3 -m json.tool` 验证 JSON 合法。

- [ ] **Step 4: 全量验证**

```bash
swift build 2>&1 | tail -2
swift test 2>&1 | grep -E "Test run with|error|failed"
xcodegen
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -2
```
Expected: Build complete;全部 suite passed;`** BUILD SUCCEEDED **`

再全仓搜一遍残留:

```bash
grep -rni "inspector\|SkillsKernel\|platform-specs\|skm " SkillsManager/ Sources/ Tests/ Package.swift project.yml README.md 2>/dev/null | grep -v "description-translations.json" || echo "clean"
```
Expected: clean(或仅剩 docs/ 历史文档)

- [ ] **Step 5: 手动验证**

编译启动 app:

```bash
open ~/Library/Developer/Xcode/DerivedData/SkillsManager-*/Build/Products/Debug/"Skills Manager.app"
```

手动检查:
1. 默认落地 = 控制台;新建分组;从库页右键 Add to Collection 加几个技能
2. 卡片上「＋ 挂载到」选 Claude Code → 状态灯变绿;`ls ~/.claude/skills` 看到 link
3. 关掉开关 → link 消失,技能仍在库中
4. 手动 `rm` 一个 link → 刷新后黄灯「与磁盘不一致」,点「重新应用」恢复
5. 侧栏无 TOOLS/检视器;agent 主页无「实际加载」卡

- [ ] **Step 6: Commit**

```bash
jj describe -m "Update README and cancel inspector goal doc for collections pivot" && jj new
```

---

## 完成定义(Definition of Done)

- [ ] 检视器(app 层 + SkillsKernel + skm + platform-specs + Yams)无残留,全仓 grep clean
- [ ] 分组 CRUD、成员管理、挂载/卸载/迁移/冲突跳过/黄灯纠正全部可用
- [ ] 默认落地页为控制台;Library/Agents/Project 行为不变
- [ ] `swift build`、`swift test`、`xcodegen + xcodebuild` 全绿;快照 PNG 已目检
- [ ] README 与 goal 文档与新方向一致
