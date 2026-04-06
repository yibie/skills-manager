# Skills Manager TUI — 设计文档

## 概述

基于 React Ink + ink-ui 的全屏交互式 TUI，作为 macOS 原生 SwiftUI app 的独立命令行平行工具。面向纯命令行工作流用户，功能定位为核心 skills 管理：发现、安装/卸载、星标收藏、版本历史。

## 目标用户

使用多个 coding agent 但不依赖 macOS GUI 的开发者，需要在终端中快速浏览、安装和管理 skills。

---

## 架构

### 技术栈

- **React Ink** + **ink-ui** — TUI 渲染框架
- **TypeScript**
- **目录**：`tui/`，独立 `package.json`，与 macOS app 共用同一 repo

### 项目结构

```
tui/
├── src/
│   ├── app.tsx                  # 根组件，全局 state + 键盘路由
│   ├── components/
│   │   ├── Sidebar.tsx          # 筛选面板（状态 / Agent）
│   │   ├── SkillList.tsx        # 技能列表
│   │   ├── DetailPanel.tsx      # 详情 + 操作快捷键
│   │   ├── SearchBar.tsx        # / 触发的搜索覆盖层
│   │   └── VersionHistory.tsx   # h 触发的版本历史覆盖层
│   └── services/
│       ├── SkillStore.ts        # 文件系统读取 skills + 状态持久化
│       ├── InstallService.ts    # 安装/卸载（文件复制）
│       ├── GitService.ts        # 版本历史（child_process → git）
│       └── MarketplaceService.ts# GitHub REST API + 本地缓存
├── package.json
└── tsconfig.json
```

### 数据流

```
FileSystem (~/.claude/skills/ 等)
      ↓ 启动时加载
  SkillStore (内存 state)
      ↓ React props
  App → Sidebar | SkillList | DetailPanel
      ↓ 用户操作
  InstallService / GitService → 写回 FileSystem → 重新加载 SkillStore
```

---

## UI 设计

### 三栏布局

```
┌─ Filter ──────┬─ Skills (23) ──────┬─ Detail ─────────────┐
│               │                    │                      │
│ ○ All    42   │ ▶ commit      ★ ●  │ commit               │
│ ○ Installed 8 │   brainstorm    ●  │ ──────────────────── │
│ ● Starred  3  │   frontend-design  │ Create well-formatted│
│               │   tdd              │ commits with conven- │
│ ── Agents ─── │   debugging        │ tional format...     │
│               │   mcp-builder      │                      │
│ ● Claude Code │   shadcn           │ Compatible:          │
│ ○ Copilot CLI │   pdf         ★ ●  │  ✓ Claude Code       │
│ ○ Codex       │                    │  ✓ Copilot CLI       │
│               │                    │                      │
│               │                    │ v2.1.0 · Official    │
│               │                    │                      │
│               │                    │ [i]nstall [s]tar     │
│               │                    │ [h]istory [o]pen     │
└───────────────┴────────────────────┴──────────────────────┘
 Tab: 切换面板   /: 搜索   q: 退出
```

图例：`●` = 已安装，`★` = 已星标，`▶` = 当前选中行，活跃面板边框高亮

### 版本历史覆盖层（`h` 触发）

```
┌─ Version History: commit ────────────────────────────────┐
│                                                          │
│  ▶ 2025-07-10  Update trigger condition           HEAD   │
│    2025-06-28  Fix commit message format                 │
│    2025-06-15  Initial install                           │
│                                                          │
│  ── Diff ──────────────────────────────────────────────  │
│  - Trigger when: user asks to commit                     │
│  + Trigger when: user asks to commit OR says /commit     │
│                                                          │
│  [r]ollback to this version   Esc: close                 │
└──────────────────────────────────────────────────────────┘
```

### 搜索覆盖层（`/` 触发）

```
┌─ Search ─────────────────────────────────────────────────┐
│  > commit_                                               │
│                                                          │
│  commit            ★ ●   Create well-formatted commits   │
│  recommit             ●   Amend and reword commits       │
│                                                          │
│  Enter: 选中并关闭   Esc: 取消                            │
└──────────────────────────────────────────────────────────┘
```

### ink-ui 组件映射

| UI 元素 | ink-ui 组件 |
|--------|-------------|
| 面板边框 | `<Box borderStyle="round">` |
| 列表选中高亮 | `<Text backgroundColor="blue">` |
| 状态图标 | `<Text color="green">` |
| 键位提示栏 | `<Box>` + `<Text dimColor>` |
| diff 展示 | `<Text color="red">` / `<Text color="green">` 行前缀 |

---

## 键盘路由

| 键 | 作用域 | 动作 |
|---|-------|------|
| `Tab` / `Shift+Tab` | 全局 | 切换活跃面板（Sidebar → SkillList → DetailPanel） |
| `↑/↓` 或 `j/k` | 当前面板 | 导航 |
| `/` | 全局 | 打开搜索覆盖层 |
| `i` | DetailPanel | 安装 / 卸载当前 skill |
| `s` | DetailPanel | 星标 / 取消星标 |
| `h` | DetailPanel | 打开版本历史覆盖层 |
| `o` | DetailPanel | 用外部编辑器打开 skill 文件 |
| `r` | 版本历史覆盖层 | 回滚到选中版本 |
| `Esc` | 覆盖层 | 关闭覆盖层 |
| `q` | 全局 | 退出 |

---

## 数据模型

```typescript
interface Skill {
  name: string
  displayName: string
  description: string
  filePath: string
  source: 'local' | 'marketplace'
  compatibleAgents: string[]
  isStarred: boolean
  isInstalled: boolean
  version?: string
}

interface Commit {
  hash: string
  date: string
  message: string
  isHead: boolean
}
```

---

## 服务层

### SkillStore

- 启动时扫描 `~/.claude/skills/` 和 `~/.claude/plugins/cache/*/skills/`
- 解析 YAML frontmatter 提取元数据
- 星标状态持久化至 `~/.skills-manager/tui-state.json`（与 macOS app 共用目录结构，独立文件）

### InstallService

- **安装**：文件复制到目标 agent 目录，首次安装后 `git init` + 初始 commit
- **卸载**：删除文件

### GitService

- 通过 `child_process.execFile` 调用本地 `git`，无额外依赖
- 提供：`getHistory`、`getDiff`、`rollback`

### MarketplaceService

- 调用 GitHub REST API 拉取 marketplace 索引
- 结果缓存至 `~/.skills-manager/cache/`
- 启动时后台静默更新，不阻塞 UI 渲染

---

## 功能范围

### 包含

- 三栏全屏交互式 TUI
- Skill 列表浏览（All / Installed / Starred + Agent 筛选）
- 安装 / 卸载
- 星标收藏
- 版本历史查看 + rollback
- 外部编辑器打开
- Marketplace 发现（后台同步）
- 搜索

### 不包含（本版本）

- Try Sandbox（LLM 对比测试）
- 项目级 skills 发现与升格
- 多 Agent 写入（仅 Claude Code，其他 Agent 为只读展示）

---

## 分阶段实施

### Phase 1 — 核心框架 + 本地 skills

- 三栏布局搭建，键盘路由
- SkillStore 读取 `~/.claude/skills/`
- Skill 列表、详情展示
- 安装 / 卸载 / 星标

### Phase 2 — 版本管理

- GitService 实现
- 版本历史覆盖层 + diff 展示 + rollback

### Phase 3 — Marketplace

- MarketplaceService + 后台同步
- 搜索覆盖层
