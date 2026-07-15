# Adapter Spec 撰写指南

Adapter Spec 是描述某个 Agent Platform **加载语义**的声明式数据文件:该平台启动时
会从哪些路径吸入哪些 Agent Resource、彼此之间的优先级/遮蔽关系是什么。spec 用
YAML 撰写,结构由同目录的 [`schema.json`](./schema.json) 约束(JSON Schema
draft 2020-12 的一个子集,见文末"校验器支持的关键字")。

spec 是**先验**:它声明"平台应该会加载什么"。真实文件系统是**后验**:
`skm check <spec> --project <path>` 逐条对照,报告 `present` / `missing`,
并在 spec 声明的目录邻域内报告 `[unmodeled]`(本机存在但 spec 未建模的可疑文件)。
诚实的不确定性本身就是透明——不确定的规则宁可标 `confidence: low`,不要省略或臆造。

## 顶层结构

```yaml
schema_version: 1        # 当前固定为 1
platform:                # 平台标识
  id: claude-code        # 小写短横线,唯一
  name: Claude Code
  version_range: ">=2.0" # 自由文本,spec 适用的平台版本范围
  docs_url: https://...
metadata:
  generated_by: human+ai # ai | human | human+ai
  last_verified: 2026-07-14   # 最后一次对照真实文件系统校验的日期
  verified_on: "macOS 15, Claude Code 2.x"   # 可选,校验环境
resources: [...]         # 加载路径规则,见下
shadowing: [...]         # 优先级/遮蔽规则,可选
unmodeled: {...}         # unmodeled 扫描配置,可选但强烈建议
```

## resources — 加载路径规则

每条 resource 描述一个加载路径。字段:

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 规则唯一标识(小写短横线),供 shadowing 引用 |
| `type` | 是 | `identity` / `guidance` / `skill` / `runtime-config`,见下 |
| `scope` | 是 | `global` / `project` / `directory`,决定路径如何解析 |
| `path` | 是 | 加载路径,支持 `~` 展开与 glob(`*`、`**`) |
| `path_kind` | 是 | `file` / `directory` / `glob` |
| `required` | 否 | 平台是否强制要求存在,默认 false(缺失只标 `[missing]`) |
| `description` | 否 | 人话说明 |
| `source` | 是 | 规则依据:官方文档 URL,或 `本机观察(...)` 等说明 |
| `confidence` | 是 | `high` / `medium` / `low` |
| `count` | 否 | 仅 `runtime-config`:浅计数方式 |

### 资源类型(type)

- **identity**:定义 Agent(或子 Agent)身份/系统提示的材料,如 subagent 定义、
  output style。
- **guidance**:注入上下文的指导性文本,如 CLAUDE.md、rules。
- **skill**:按需加载的技能/命令,如 SKILL.md 目录、slash command。
- **runtime-config**:运行时配置(MCP、hooks、权限、模型)。v1 只做浅覆盖:
  存在性 + 计数 + 文件指针,**不解析语义**。

### 路径解析(scope × path)

- `scope: global` — `path` 以 `~` 开头(展开为用户主目录)或为绝对路径,
  与项目无关。
- `scope: project` — `path` 是相对项目根的路径。
- `scope: directory` — `path` 是相对项目根的 glob,匹配项目内任意子目录中的
  资源(如 `**/CLAUDE.md` 表示"任何子目录里的 CLAUDE.md")。检查器扫描时会
  限制深度并跳过 `.git`、`node_modules` 等,避免大树扫描。

glob 语法:`*` 匹配单层内任意名字(不含 `/`);`**` 匹配任意多层目录。
`path_kind: glob` 时按 glob 解释;`file`/`directory` 时路径是字面路径。

### 计数(count,仅 runtime-config)

```yaml
count:
  method: json-keys      # json-keys | entries | files
  pointer: /mcpServers   # method=json-keys:JSON Pointer,数该对象的键数量
  unit: servers          # 展示单位
```

- `json-keys`:解析 JSON 文件,按 `pointer` 定位到对象,数键的数量
  (如 ".mcp.json 里 mcpServers 有 2 个键" → "2 servers")。
- `entries`:数目录的直接子项数量。
- `files`:按 `file_pattern`(相对该目录的 glob)数匹配文件数量
  (如 `*/SKILL.md` → 技能数)。

## shadowing — 优先级与遮蔽

```yaml
shadowing:
  - id: project-skill-shadows-global
    description: 项目级同名 skill 遮蔽全局
    strategy: override        # override | merge
    winner: project-skills    # resource id
    loser: global-skills      # resource id
    key: skill-directory-name # 同一性判定 key
    source: https://...
    confidence: high
```

- `override`:key 相同时 winner 完全遮蔽 loser。
- `merge`:两者都生效、合并,冲突处 winner 优先(如 settings 的分层覆盖)。
- `winner`/`loser` 必须引用 `resources` 中已存在的 `id`(校验器会做语义检查)。
- 链式优先级(A > B > C)拆成两两规则表达。

## unmodeled — 可疑文件扫描配置

```yaml
unmodeled:
  roots:                      # 只在这些根目录的直接子项邻域内扫描,不全盘扫
    - { path: ~/.claude, scope: global }
    - { path: .claude,    scope: project }
  ignore:                     # 已知的非 Agent Resource(会话状态、缓存等)
    - ~/.claude/projects
    - ~/.claude/shell-snapshots
    - ~/.claude/.last-*       # 末段可用 * 通配
```

检查器只看每个 root 的**直接子项**:既不被任何 resource 路径覆盖、也不在
ignore 列表内的条目,报告为 `[unmodeled]`。ignore 用于压噪音——把确认过的
会话状态/缓存显式列出,而不是靠检查器猜。新平台版本引入的新文件会自然以
`[unmodeled]` 浮出,这是 spec 过时的信号。

## 撰写与维护流程

1. 以官方文档为主要 `source`;文档没写清的行为,用本机实际布局交叉验证,
   `source` 写 `本机观察(YYYY-MM-DD, 环境)`。
2. 每次对照真实文件系统跑过 `skm check` 后,更新 `metadata.last_verified`。
3. 提交前必须通过 `skm validate <spec>`。

## 校验器支持的 JSON Schema 关键字

`skm validate` 内置一个 JSON Schema 子集校验器,支持:
`type`、`properties`、`required`、`additionalProperties`(布尔)、`items`、
`enum`、`minItems`、`pattern`、`$ref`(仅 `#/$defs/*`)。修改 `schema.json`
时不要使用子集之外的关键字(如 `oneOf`、`format`、条件关键字)。
