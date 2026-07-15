# Effective-Agent JSON:数据契约说明

> Schema:`docs/goals/effective-agent-schema.json`。生产者:`skm inspect` /
> `SkillsKernel.EffectiveAgentInspector`。消费者:Swift 检视器 UI(M3)、
> TUI(M6)、任何下游工具。改动此格式必须升 `schema_version`。

## 一份报告长什么样

```
skm inspect platform-specs/claude-code.yaml --project . --pretty
```

```json
{
  "schema_version": 1,
  "generated_at": "2026-07-16T10:00:00Z",
  "platform": { "id": "claude-code", "name": "Claude Code", "version_range": ">=2.0" },
  "project": { "path": "/Users/me/prj/demo" },
  "spec": { "schema_version": 1, "generated_by": "human+ai", "last_verified": "2026-07-14",
            "path": "platform-specs/claude-code.yaml" },
  "summary": { "resources": 13, "active": 10, "shadowed": 2, "missing": 1, "unmodeled": 2 },
  "resources": {
    "identity": [ … ], "guidance": [ … ], "skill": [ … ], "runtime-config": [ … ]
  },
  "unmodeled": [ { "path": "…/.claude/mystery-dir", "root": "…/.claude", "scope": "global" } ]
}
```

## 核心概念:规则 vs 实例

adapter spec 里的一条 resource 规则(如 `global-skills: ~/.claude/skills`)
在检视时被**实例化**成零或多个资源实例:

- skill 目录规则:每个含 `SKILL.md` 的子目录是一个实例(key = 目录名,
  path = SKILL.md 绝对路径);目录下的裸 `*.md`(slash command 形态)也
  各是一个实例(key = 去掉 `.md` 的文件名)。
- identity 目录规则:每个 `*.md` 是一个实例(key 去扩展名,即 agent 名)。
- guidance 文件/目录/glob 规则:每个命中的文件是一个实例(key 保留文件名)。
- runtime-config 规则:**浅覆盖**——文件本身即实例,附 `count`
  (沿用 SpecChecker 的计数机制),不解析语义。
- 规则声明的路径在文件系统不存在:产出**一个** `status: missing` 的实例
  (path 为期望路径,key 缺席)。

## 状态与遮蔽

- `active`:实际会被 Agent 加载。
- `shadowed`:仅由 spec 中 `strategy: override` 的 shadowing 规则产生——
  loser 规则下与某个 active winner 实例同 key 的实例被标记,
  `shadowed_by` 指明遮蔽方路径、遮蔽方规则 id、依据的 shadowing 规则 id。
  `strategy: merge` 的规则(如 settings 分层、CLAUDE.md 叠加)双方都生效,
  **不**产生 shadowed。
- `missing`:spec 声明(先验)但文件系统不存在(后验)。

## 不确定性的显式表达(goal 决策 6)

- `required` / `confidence` 每个实例必有,直接透传 spec,不做缺省折叠;
  `confidence: low` 意味着这条规则本身可能说谎。
- `unmodeled` 列出 spec 邻域内未建模的可疑条目——spec 可能过时,不许隐藏。
- 可选字段(`key`、`shadowed_by`、`count`、`spec.path`、`version_range`)
  用**缺席**表达"不适用/未知",不用空串或 0 冒充。

## 已知取舍

- present 但为空的容器目录(如空 skills 目录)不产生任何实例,报告里
  不可见;需要规则级 present/missing 视图时用 `skm check`。
- 遮蔽标记按 spec 中 shadowing 规则的书写顺序单趟处理,且只有当时仍为
  active 的 winner 实例才能遮蔽别人(遮蔽不传染)。
- identity/guidance 容器只做浅枚举(一层 `*.md`),不下钻子目录。
