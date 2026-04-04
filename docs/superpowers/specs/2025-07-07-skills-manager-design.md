# Skills Manager — macOS 原生 SwiftUI 应用设计

## 概述

一个 macOS 原生应用，用于统一管理各 coding agent（Claude Code、Cursor、Copilot CLI、Codex、Gemini CLI 等）的 skills。提供完善的生命周期管理：发现、测试、安装、保留、删除、星标收藏。内置 LLM 沙箱让用户对比不同 skills 的效果。

## 核心问题

当前 coding agent 的 skills 生态分散——不同 agent 有不同的格式、安装方式和存放路径，且没有统一的管理界面。用户难以发现新 skills、对比效果、追踪自己的修改历史。

## 目标用户

使用多个 coding agent 的开发者，需要频繁发现、测试、安装和定制 skills。

---

## 架构

### 技术栈

- **SwiftUI** + **Swift 6**，macOS 14+ (Sonoma)
- **SwiftData** 本地持久化
- **Process** 调用 `git` CLI 处理版本操作
- **GitHub REST API**（URLSession）拉取 marketplace 索引
- **FSEvents** 监听 skill 文件变更
- **NSWorkspace** 打开外部编辑器
- **Claude API / OpenAI API** 做 Try Sandbox 的 LLM 调用

### 方案选择：纯本地架构

SwiftUI app 直接读写各 agent 的本地配置文件，通过 Git 操作 marketplace 仓库来发现/安装 skills。无需后端，离线可用（Sandbox 功能除外）。

---

## 数据模型

### Skill

```swift
struct Skill: Identifiable {
    let id: UUID
    var name: String
    var displayName: String
    var description: String
    var source: SkillSource        // .marketplace(name) / .local / .projectLocal
    var version: String?
    var upstreamSource: URL?       // marketplace 来源，用于检查更新
    var upstreamVersion: String?
    var filePaths: [URL]
    var compatibleAgents: [String]
    var isStarred: Bool
    var installState: InstallState // .notInstalled / .installed / .trial
    var tags: [String]
}
```

### Marketplace

```swift
struct Marketplace: Identifiable {
    let id: UUID
    var name: String
    var repoURL: URL               // GitHub repo
    var plugins: [MarketplacePlugin]
    var lastSynced: Date
}
```

### AgentAdapter 协议

```swift
protocol AgentAdapter {
    var agentName: String { get }
    var skillsDirectory: URL { get }
    var configFile: URL? { get }
    
    func installedSkills() -> [Skill]
    func install(skill: Skill) throws
    func uninstall(skill: Skill) throws
    func isCompatible(skill: Skill) -> Bool
}
```

初期实现：
- `ClaudeCodeAdapter` — `~/.claude/skills/`、`~/.claude/plugins/`
- `CursorAdapter` — `.cursor/rules/`（Phase 4）

---

## UI 设计

### 主界面：三栏布局

```
┌─────────────┬──────────────────────┬──────────────────┐
│  Sidebar     │  Skill List          │  Detail Panel    │
│             │                      │                  │
│ ▸ All       │  skill-name  ★       │  SKILL.md 内容    │
│ ▸ Installed │  description...      │  (预览 / 编辑)    │
│ ▸ Starred   │  ┌────────────────┐  │                  │
│ ▸ Trial     │  │Install│Try│⋯  │  │  Compatible:     │
│             │  └────────────────┘  │   Claude Code ✓  │
│ ─ Agents ── │                      │   Cursor ✓       │
│ Claude Code │  skill-name          │                  │
│ Cursor      │  description...      │  Version: 1.2.0  │
│             │                      │  Source: Official │
│ ─ Sources ─ │                      │                  │
│ Official    │                      │ [Open in Editor]  │
│ Superpowers │                      │                  │
└─────────────┴──────────────────────┴──────────────────┘
```

- **Sidebar**：分类筛选（状态、Agent、来源）
- **Skill List**：skill 列表，hover/选中时显示内联操作条
- **Detail Panel**：skill 内容预览（Markdown 渲染）、元信息、编辑器

### 内联操作条

hover 或选中 skill 行时，在该行下方弹出操作条：
- **Install** — 安装到选定 agent
- **Try** — 进入 Sandbox 测试
- **Uninstall** — 已安装的 skill
- **⋯ More** — Open in Editor、查看版本历史等

### Sandbox 界面

```
┌─────────────────────────────────────────────────────────┐
│  Try Sandbox                                            │
│                                                         │
│  Input:                                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 用户输入的测试 prompt                               │  │
│  └───────────────────────────────────────────────────┘  │
│  [Run]                                                  │
│                                                         │
│  ┌─── Slot A ──────────┐  ┌─── Slot B ──────────┐     │
│  │ skill-name-1         │  │ skill-name-2         │     │
│  │ ──────────────────── │  │ ──────────────────── │     │
│  │ LLM output           │  │ LLM output           │     │
│  │ with this skill      │  │ with this skill      │     │
│  │                      │  │                      │     │
│  │ [Keep] [Discard]     │  │ [Keep] [Discard]     │     │
│  └──────────────────────┘  └──────────────────────┘     │
│                                                [+ Slot]  │
└─────────────────────────────────────────────────────────┘
```

- 用户输入测试 prompt
- 每个 Slot 绑定一个 skill，作为 system prompt 注入
- 点击 Run → 并行调用 LLM API，结果并排显示
- 用户对比后 Keep（安装）或 Discard（丢弃）
- 可添加多个 Slot

---

## 功能模块

### 1. Discover（发现）

- 从已注册 marketplace（GitHub repos）同步 skill 索引
- 搜索、按 agent 筛选、按分类浏览
- 显示 skill 详情、兼容性、版本信息
- 定期或手动刷新索引

### 2. Install / Uninstall（安装 / 卸载）

- 一键安装到指定 agent（或多个 agent）
- 安装 = 将 skill 文件复制到对应 agent 的 skills 目录
- 首次安装后自动 `git init` + 首次 commit 记录原始版本
- 卸载 = 移除文件

### 3. Try Sandbox（沙箱测试）

- 内置 LLM API 调用（用户配置 API key）
- 多 slot 并行对比：同一 prompt + 不同 skill
- Keep = 正式安装，Discard = 清理
- 支持自由添加/移除 slot

### 4. Version Management（版本管理）

- 已安装 skill 的编辑自动通过 git 追踪
- 查看修改历史（git log）
- diff 查看具体变更
- rollback 到任意历史版本
- 上游有新版本时提示用户，可选择更新（merge 或覆盖）

### 5. Edit（编辑）

- Detail Panel 内嵌 Markdown/YAML 预览
- 轻量编辑能力（基础文本编辑）
- 「Open in Editor」按钮 → `NSWorkspace.open()` 调用外部编辑器
- FSEvents 监听文件变更，实时刷新 UI

### 6. Star（星标收藏）

- 一键星标
- Sidebar 快捷筛选 starred skills

### 7. Project-local Skills（项目级 skills 发现）

- 扫描当前打开项目中的 skills（如 `.cursor/rules/`、项目根目录的 skill 文件）
- 可「升格」为全局 skill：复制到全局 skills 目录

---

## 本地文件结构

```
~/.skills-manager/
  ├── config.json          # app 配置（API keys、默认 agent、marketplace 列表）
  ├── cache/               # marketplace 索引缓存
  └── data.store           # SwiftData 数据库（skill 元数据、星标、状态）
```

已安装 skills 直接存放在各 agent 的原生 skills 目录中（如 `~/.claude/skills/`），由 git 管理版本。

---

## Agent 适配

| Agent | Skills 路径 | 格式 | 安装方式 |
|-------|------------|------|---------|
| Claude Code | `~/.claude/skills/` | SKILL.md（含 YAML frontmatter） | 文件复制 |
| Cursor | `.cursor/rules/` | .mdc | 文件复制 + 格式转换 |
| Copilot CLI | TBD | TBD | TBD |
| Codex | TBD | TBD | TBD |
| Gemini CLI | TBD | TBD | TBD |

---

## 分阶段实施

### Phase 1 — MVP：本地 skill 管理 + 版本追踪

- SwiftUI 三栏布局
- ClaudeCodeAdapter：扫描 `~/.claude/skills/` 和 `~/.claude/plugins/`
- Skill 列表、详情预览、内联操作条
- 星标收藏
- 内嵌编辑 + 外部编辑器打开
- Git 自动追踪修改历史（commit、diff、rollback）
- FSEvents 文件变更监听

### Phase 2 — Marketplace + 安装

- GitHub REST API 对接 marketplace
- Marketplace 索引同步与缓存
- 搜索、筛选
- 安装 / 卸载流程
- 上游版本更新提示

### Phase 3 — Try Sandbox

- API key 配置（Claude API / OpenAI API）
- 多 slot 并行 LLM 调用
- 结果并排展示
- Keep / Discard 决策流程

### Phase 4 — 多 Agent 支持

- CursorAdapter + skill 格式转换
- 项目级 skills 发现与升格
- 其他 agent adapter 扩展

---

## 验证方式

### Phase 1 验证

1. 构建并运行 app，确认能正确扫描 `~/.claude/skills/` 中的 skills
2. 选中 skill → Detail Panel 显示正确的 Markdown 内容
3. 星标操作正常，Sidebar 筛选有效
4. 内嵌编辑修改后 → git 自动记录 → 可查看 diff 和 rollback
5. 「Open in Editor」成功打开外部编辑器
6. 文件外部修改后 → app UI 自动刷新
