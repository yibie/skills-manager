# Phase 3: Try Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SkillListView 的 Try 按钮上接入真实 LLM，打开沙箱窗口，让用户用同一个 prompt 对比多个 skill 的输出效果，并决定 Keep（安装）或 Discard（清空）。

**Architecture:** `LLMService` actor 封装 Claude Messages API；`SandboxSlot` @Observable class 持有每个 slot 的状态（skill、output、isLoading、error）；`SandboxView` 作为 sheet 打开，顶部是 prompt 输入 + Run 按钮，下方是横向可滚动的 SlotCard 网格；`AppSettings` 存储 API Key（@AppStorage/UserDefaults）；SkillListView 的 Try 按钮通过 ContentView 的 `@State var sandboxSkill` 打开 sheet。

**Tech Stack:** SwiftUI + Swift 6, macOS 14+, URLSession, Claude Messages API (`https://api.anthropic.com/v1/messages`), @AppStorage (UserDefaults)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `SkillsManager/Models/AppSettings.swift` | Create | API key 常量、默认模型名 |
| `SkillsManager/Views/SettingsView.swift` | Create | macOS Settings 窗口（⌘,）— API key 输入 + 模型选择 |
| `SkillsManager/SkillsManagerApp.swift` | Modify | 添加 `Settings { SettingsView() }` scene |
| `SkillsManager/Services/LLMService.swift` | Create | Claude Messages API actor |
| `SkillsManager/Models/SandboxSlot.swift` | Create | @Observable slot 状态类 |
| `SkillsManager/Views/SandboxView.swift` | Create | 沙箱 UI：prompt 输入、slot 网格、Keep/Discard |
| `SkillsManager/Views/SkillListView.swift` | Modify | 添加 `onTry: (Skill) -> Void` 回调，接通 Try 按钮 |
| `SkillsManager/Views/ContentView.swift` | Modify | `@State var sandboxSkill`，sheet 展示 SandboxView，传入 onTry |

---

## Task 1: AppSettings + SettingsView

**Files:**
- Create: `SkillsManager/Models/AppSettings.swift`
- Create: `SkillsManager/Views/SettingsView.swift`
- Modify: `SkillsManager/SkillsManagerApp.swift`

- [ ] **Step 1: 创建 AppSettings.swift**

```swift
import Foundation

enum AppSettings {
    static let claudeApiKeyKey = "claudeApiKey"
    static let sandboxModelKey = "sandboxModel"
    static let defaultModel = "claude-haiku-4-5"
}
```

- [ ] **Step 2: 创建 SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.claudeApiKeyKey) private var apiKey = ""
    @AppStorage(AppSettings.sandboxModelKey) private var model = AppSettings.defaultModel

    var body: some View {
        Form {
            Section("Claude API") {
                LabeledContent("API Key") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .frame(width: 280)
                }
                LabeledContent("Model") {
                    Picker("Model", selection: $model) {
                        Text("claude-haiku-4-5 (Fast)").tag("claude-haiku-4-5")
                        Text("claude-sonnet-4-5 (Balanced)").tag("claude-sonnet-4-5")
                        Text("claude-opus-4-5 (Best)").tag("claude-opus-4-5")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .padding()
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
}
```

- [ ] **Step 3: 修改 SkillsManagerApp.swift，添加 Settings scene**

读取当前文件，在 `WindowGroup { ... }.modelContainer(...)` 之后追加：

```swift
import SwiftUI
import SwiftData

@main
struct SkillsManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([SkillRecord.self])
        let config = ModelConfiguration(
            "SkillsManager",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 4: 构建验证**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add SkillsManager/Models/AppSettings.swift \
        SkillsManager/Views/SettingsView.swift \
        SkillsManager/SkillsManagerApp.swift
git commit -m "feat: add AppSettings and SettingsView with Claude API key config"
```

---

## Task 2: LLMService — Claude Messages API

**Files:**
- Create: `SkillsManager/Services/LLMService.swift`

- [ ] **Step 1: 创建 LLMService.swift**

```swift
import Foundation

actor LLMService {

    // MARK: - Encodable request

    private struct APIRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [APIMessage]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct APIMessage: Encodable {
        let role: String
        let content: String
    }

    // MARK: - Decodable response

    private struct APIResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        var text: String {
            content.compactMap(\.text).joined()
        }
    }

    // MARK: - Public API

    /// Sends a prompt + optional skill system prompt to Claude Messages API.
    /// - Parameters:
    ///   - prompt: User input text.
    ///   - systemPrompt: Skill markdown content injected as system prompt.
    ///   - apiKey: Claude API key (from AppSettings).
    ///   - model: Claude model ID (defaults to `AppSettings.defaultModel`).
    func complete(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String = AppSettings.defaultModel
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMError.noApiKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = APIRequest(
            model: model,
            maxTokens: 2048,
            system: systemPrompt,
            messages: [APIMessage(role: "user", content: prompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw LLMError.httpError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.text
    }
}

enum LLMError: LocalizedError {
    case noApiKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No Claude API key configured. Open Settings (⌘,) to add your key."
        case .invalidResponse:
            return "Invalid response received from the API."
        case .httpError(let code, let body):
            return "API request failed (\(code)): \(body.prefix(300))"
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Services/LLMService.swift
git commit -m "feat: add LLMService for Claude Messages API calls"
```

---

## Task 3: SandboxSlot model

**Files:**
- Create: `SkillsManager/Models/SandboxSlot.swift`

- [ ] **Step 1: 创建 SandboxSlot.swift**

```swift
import Foundation
import Observation

/// Observable state for a single sandbox comparison slot.
/// Each slot holds one optional skill, the LLM output, and loading/error state.
@Observable
final class SandboxSlot: Identifiable {
    let id = UUID()
    var skill: Skill?
    var output: String?
    var isLoading: Bool = false
    var error: String?

    init(skill: Skill? = nil) {
        self.skill = skill
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Models/SandboxSlot.swift
git commit -m "feat: add SandboxSlot model for Try Sandbox"
```

---

## Task 4: SandboxView

**Files:**
- Create: `SkillsManager/Views/SandboxView.swift`

SandboxView 是一个 sheet。顶部 bar 有 Done 按钮；中间是 prompt 输入 + Run 按钮（⌘↵）；下方是横向可滚动的 slot cards，末尾有 "+ Add Slot" 按钮。每个 SlotCard 有 skill 选择器、输出区域、Keep/Discard。

- [ ] **Step 1: 创建 SandboxView.swift**

```swift
import SwiftUI

struct SandboxView: View {
    let availableSkills: [Skill]
    let onKeep: (Skill) async -> Void

    @AppStorage(AppSettings.claudeApiKeyKey) private var apiKey: String = ""
    @AppStorage(AppSettings.sandboxModelKey) private var model: String = AppSettings.defaultModel

    @State private var slots: [SandboxSlot]
    @State private var prompt: String = ""

    private let llmService = LLMService()
    @Environment(\.dismiss) private var dismiss

    private var isRunning: Bool {
        slots.contains { $0.isLoading }
    }

    init(initialSkill: Skill?, availableSkills: [Skill], onKeep: @escaping (Skill) async -> Void) {
        _slots = State(initialValue: [
            SandboxSlot(skill: initialSkill),
            SandboxSlot()
        ])
        self.availableSkills = availableSkills
        self.onKeep = onKeep
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Try Sandbox")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Prompt input
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Enter a prompt to test with your skills...")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60, maxHeight: 100)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    )

                    Button {
                        runAll()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning
                    )
                    .keyboardShortcut(.return, modifiers: .command)
                }

                if apiKey.isEmpty {
                    Label(
                        "No API key — add one in Settings (⌘,)",
                        systemImage: "key.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Slot grid
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(slots) { slot in
                        SlotCard(
                            slot: slot,
                            availableSkills: availableSkills,
                            canRemove: slots.count > 1,
                            onKeep: {
                                if let skill = slot.skill {
                                    Task { await onKeep(skill) }
                                }
                            },
                            onDiscard: {
                                slot.output = nil
                                slot.error = nil
                            },
                            onRemove: {
                                slots.removeAll { $0.id == slot.id }
                            }
                        )
                        .frame(width: 300, alignment: .top)
                    }

                    // Add slot
                    Button {
                        slots.append(SandboxSlot())
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                            Text("Add Slot")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                        .padding(.vertical, 40)
                        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: - Run

    /// Fire one independent Task per slot that has a skill selected.
    /// Tasks run concurrently; each suspends at the URLSession call inside LLMService.
    private func runAll() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for slot in slots where slot.skill != nil {
            Task { await run(slot: slot, skill: slot.skill!, prompt: trimmed) }
        }
    }

    /// Calls LLMService on a single slot.
    /// SandboxView is @MainActor (implicit from View conformance), so all property
    /// accesses and slot mutations happen on the main actor; the await on llmService
    /// suspends the main actor while the HTTP call executes on LLMService's actor.
    private func run(slot: SandboxSlot, skill: Skill, prompt: String) async {
        slot.isLoading = true
        slot.output = nil
        slot.error = nil
        do {
            slot.output = try await llmService.complete(
                prompt: prompt,
                systemPrompt: skill.markdownContent,
                apiKey: apiKey,
                model: model
            )
        } catch {
            slot.error = error.localizedDescription
        }
        slot.isLoading = false
    }
}

// MARK: - SlotCard

private struct SlotCard: View {
    let slot: SandboxSlot
    let availableSkills: [Skill]
    let canRemove: Bool
    let onKeep: () -> Void
    let onDiscard: () -> Void
    let onRemove: () -> Void

    private var skillIDBinding: Binding<String> {
        Binding(
            get: { slot.skill?.id ?? "" },
            set: { id in slot.skill = availableSkills.first { $0.id == id } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: skill picker + remove button
            HStack {
                Picker("Skill", selection: skillIDBinding) {
                    Text("Select a skill...").tag("")
                    ForEach(availableSkills) { skill in
                        Text(skill.displayName).tag(skill.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove slot")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.06))

            Divider()

            // Output body
            Group {
                if slot.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                } else if let error = slot.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let output = slot.output {
                    ScrollView {
                        Text(output)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else {
                    Text("Output will appear here after running.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                }
            }
            .frame(minHeight: 200)

            // Footer: Keep / Discard — shown only when output is available
            if slot.output != nil {
                Divider()
                HStack {
                    Button("Keep", action: onKeep)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Discard", action: onDiscard)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

#Preview {
    SandboxView(
        initialSkill: Skill.mockSkills.first,
        availableSkills: Skill.mockSkills,
        onKeep: { _ in }
    )
}
```

- [ ] **Step 2: 构建验证**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add SkillsManager/Views/SandboxView.swift
git commit -m "feat: add SandboxView with multi-slot LLM skill comparison UI"
```

---

## Task 5: Wire Try button + ContentView sheet

**Files:**
- Modify: `SkillsManager/Views/SkillListView.swift`
- Modify: `SkillsManager/Views/ContentView.swift`

先读取两个文件再修改。

- [ ] **Step 1: 在 SkillListView 中添加 onTry 回调**

在 `SkillListView` struct 添加参数：
```swift
let onTry: (Skill) -> Void
```

在 `List` 内的 `SkillRow` 调用处，追加 `onTry` 参数：
```swift
SkillRow(
    skill: skill,
    onInstall: { Task { await onInstall(skill) } },
    onUninstall: { Task { await onUninstall(skill) } },
    onTry: { onTry(skill) }
)
```

在 `SkillRow` struct 添加参数：
```swift
let onTry: () -> Void
```

在 `SkillRow.body` 中，把 `SkillActionButtons` 调用更新为：
```swift
SkillActionButtons(skill: skill, onInstall: onInstall, onUninstall: onUninstall, onTry: onTry)
```

在 `SkillActionButtons` struct 添加参数：
```swift
let onTry: () -> Void
```

在 `SkillActionButtons.body` 中，把当前空的 Try 按钮：
```swift
ActionButton(icon: "flask", label: "Try") { }
```
替换为：
```swift
ActionButton(icon: "flask", label: "Try", action: onTry)
```

更新 `SkillListView` 的 `#Preview`，补上新参数：
```swift
SkillListView(
    skills: Skill.mockSkills,
    filter: .all,
    selectedSkill: $selected,
    onInstall: { _ in },
    onUninstall: { _ in },
    onTry: { _ in }
)
```

- [ ] **Step 2: 在 ContentView 中添加 sandboxSkill state 和 sheet**

在 `ContentView` 的 `@State` 属性区域添加：
```swift
@State private var sandboxSkill: Skill? = nil
```

更新 `SkillListView` 的调用，追加 `onTry`：
```swift
SkillListView(
    skills: store.skills,
    filter: selectedFilter,
    selectedSkill: $selectedSkill,
    onInstall: { skill in await store.installSkill(skill) },
    onUninstall: { skill in await store.uninstallSkill(skill) },
    onTry: { skill in sandboxSkill = skill }
)
```

在 `NavigationSplitView` 的修饰符链中，在 `.task { ... }` 之前添加：
```swift
.sheet(item: $sandboxSkill) { skill in
    SandboxView(
        initialSkill: skill,
        availableSkills: store.skills,
        onKeep: { skill in await store.installSkill(skill) }
    )
}
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

如有 error，常见原因：
- `Skill` 是否 `Identifiable`（已是，`let id: String`）— `.sheet(item:)` 需要 `Identifiable` ✓
- `@MainActor` 隔离问题：`onTry: { skill in sandboxSkill = skill }` 在 MainActor 上，✓

- [ ] **Step 4: Commit**

```bash
git add SkillsManager/Views/SkillListView.swift \
        SkillsManager/Views/ContentView.swift
git commit -m "feat: wire Try button to open SandboxView sheet"
```

---

## Task 6: 最终验证

- [ ] **Step 1: 全量构建**

```bash
cd /Users/chenyibin/Documents/prj/skills-manager && swift build 2>&1 | grep -E "error:|warning:|Build complete"
```
Expected: `Build complete!`，no error

- [ ] **Step 2: 手动验证清单**

1. 打开 App → 按 ⌘, → Settings 窗口出现，可以输入 Claude API key
2. 在 Skill List 中，点击任意 skill 的 Try（烧杯图标）→ Sandbox sheet 打开
3. Sandbox 已有 Slot A 预填该 skill，Slot B 为空选择器
4. 选择 Slot B 的 skill → 输入 prompt → ⌘↵ 或点 Run
5. 两个 slot 并发调用 LLM，各自显示 ProgressView → 输出文本
6. 点 Keep → `installSkill` 被调用，skill 状态变为 installed
7. 点 Discard → output 清空，slot 恢复空白状态
8. 点 "+ Add Slot" → 增加第三个 slot
9. 点 slot 右上角 × → slot 移除（最后一个 slot 无 × 按钮）
10. 无 API key 时，Run 可点击但 LLM 返回错误提示

- [ ] **Step 3: 最终 commit（仅 SkillsManagerApp.swift 有变动则提交）**

```bash
git add -A
git commit -m "feat: Phase 3 complete — Try Sandbox with Claude API integration"
```
