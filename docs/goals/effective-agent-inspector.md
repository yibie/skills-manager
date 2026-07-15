# Goal: Effective-Agent 检视器

> 状态:已批准(2026-07-14)。本文档是开发 agent 的执行依据,按里程碑逐个交付。

## 背景与产品决策

skills-manager 的核心痛点重新定义为**透明性**:Agent 启动时把散落在多个目录的
.md/toml/json 隐式吸进去,用户不知道最终生效的是什么——用户在黑箱里使用自己的
Agent。本 goal 交付第一个透明化工具:**Effective-Agent 检视器**。

选定平台 × 项目,渲染出"这个 Agent 实际加载了什么":

```
┌─ Effective Agent: Claude Code × ~/prj/skills-manager ─┐
│ Identity   (none — platform default)                  │
│ Guidance   CLAUDE.md            [project]             │
│            ~/.claude/CLAUDE.md  [missing]             │
│ Skills     47 shared (~/.agents/skills)               │
│            1 project (.claude/skills)                 │
│            ⚠ domain-modeling: shadowed by project 版  │
│ Runtime    mcp.json: 2 servers · hooks: 3             │
└───────────────────────────────────────────────────────┘
```

### 已敲定的决策(不要重新讨论)

1. **检视器是只读的**。v1 不做任何写入/同步/组装。
2. **深度平台五个**:Claude Code、Codex、OpenClaw、Hermes、Pi。其余 20+ 平台
   维持现有 skills 目录浅支持。
3. **平台加载规则不硬编码**,以声明式 **adapter spec** 数据文件形式存在,由 AI
   辅助提取和更新。spec 最终迁移到独立社区仓库,并驱动一个"harness 差异对照"
   静态网站(类比 caniuse.com);v1 阶段 spec 先放本仓库 `platform-specs/`。
4. **架构**:解析/扫描内核做成独立 Swift 模块 + `skm inspect` CLI(输出 JSON);
   Swift macOS 应用先行渲染,TUI 后续消费同一份 JSON。
5. **Runtime Config 层(mcp/hooks/权限/model)浅覆盖**:只做存在性 + 计数 +
   文件指针,不解析语义。
6. **真相来源分级**:spec 是先验,本地文件系统校验是后验。spec 声明的文件不存
   在 → 标 `[missing]`;本地存在但 spec 未覆盖的可疑文件 → 标 `[unmodeled]`。
   诚实的不确定性本身就是透明,不许隐藏。

### 领域术语(代码与文档统一使用)

| 术语 | 含义 |
|---|---|
| Agent Platform | 承载 Agent 的产品(Claude Code、Codex…)。现有 `AgentDefinition` 应改名为此 |
| Adapter Spec | 描述某平台加载语义的声明式数据文件 |
| Agent Resource | 被加载的原子材料:skill、guidance 文件、identity/prompt、runtime config |
| Effective Agent | 某平台 × 某项目下,实际生效的 Resource 集合及其来源/覆盖关系 |
| Deployment | 某组 Resource 在某平台+项目的实际投射(本 goal 只读取,不管理) |

## 里程碑

### M1 — Adapter Spec 格式 + Claude Code 种子 spec + 校验器

**交付物**

1. `platform-specs/SCHEMA.md` + `platform-specs/schema.json`:adapter spec 的
   JSON Schema 与撰写指南。spec 必须能表达:
   - 加载路径列表(全局/项目/目录三种 scope,支持 `~` 与项目相对路径、glob)
   - 每条路径的资源类型(identity / guidance / skill / runtime-config)
   - 优先级与遮蔽规则(如"项目级同名 skill 遮蔽全局")
   - runtime-config 条目只需:文件路径 + 计数方式(如"mcpServers 键数量")
   - 元数据:适用平台版本范围、spec 生成方式(AI/人工)、最后校验日期
2. `platform-specs/claude-code.yaml`:Claude Code 的完整 spec。提取来源:
   官方文档 + 本机 `~/.claude` 实际布局交叉验证。必须覆盖:CLAUDE.md 层级
   (全局/项目/子目录)、`.claude/skills` 与共享 skills 根、agents、
   settings.json 系列、.mcp.json、hooks、plugins、rules。
3. 校验器:新 Swift 模块 `SkillsKernel`(library target)+ 可执行 target
   `skm`,提供 `skm validate <spec>`(schema 校验)与
   `skm check <spec> --project <path>`(对照本机文件系统,报告
   missing/unmodeled)。
4. 单元测试:schema 校验用例、用 fixture 目录树测试 check 逻辑。

**验收标准**

- `skm check platform-specs/claude-code.yaml --project .` 在本机运行,输出与
  `~/.claude`、项目 `.claude/` 的真实内容一致,无误报的 `[unmodeled]` 噪音。
- spec 中每条规则都附 `source` 字段注明依据(文档 URL 或"本机观察")。
- 不修改现有 SkillsManager 应用与 TUI 的任何行为。

### M2 — `skm inspect`:输出 Effective-Agent JSON

- 定义 Effective-Agent JSON schema(`docs/goals/effective-agent-schema.json`)。
- `skm inspect --platform claude-code --project <path>` 消费 M1 spec,扫描
  文件系统,输出完整 Effective-Agent JSON:每个 Resource 的来源文件、scope、
  遮蔽关系、missing/unmodeled 标注、runtime 浅覆盖计数。
- 现有 `SkillsManager/Adapters/ClaudeCodeAdapter.swift` 的扫描逻辑不迁移、
  不删除(避免破坏现有功能),但新代码不得复制其实现——内核是独立实现。

### M3 — Swift 应用检视器 UI

- 新增 Inspector 视图:平台选择 + 项目选择 → 渲染 Effective-Agent 树。
- 数据全部来自 SkillsKernel(进程内调用,不走 CLI)。
- 遮蔽/missing/unmodeled 用视觉标注,点击资源可跳转文件。

### M4 — 其余四平台 spec + AI 再生成流程

- Codex、OpenClaw、Hermes、Pi 的 spec(方法同 M1)。
- 应用内"用 AI 更新 spec"入口:走已有 LLM gateway(`AppSettings.swift` 的
  LLMProvider),生成的 spec 必须过 `skm validate` + `skm check` 才可保存。

### M5 — 社区仓库拆分 + 对照网站

- `platform-specs/` 拆到独立公开仓库;skills-manager 启动时拉取 + 本地缓存。
- 从 spec 自动构建静态对照网站(不手工维护第二份内容)。

### M6(后续)— TUI 消费 Effective-Agent JSON

## 非目标(v1 明确不做)

- 写入/同步/部署任何文件;Profile manifest 与组装工作台;runtime 语义解析
  (hook 触发时机、工具权限判定);会话/成本等 Runtime State。

## 风险

- **spec 过时说谎**:靠 M1 的 check 后验 + 元数据里的校验日期缓解;检视器只读,
  错误不会造成破坏。
- **AI 提取不准**:M1 由人(agent)+ 本机交叉验证打样,这条路走不通会在 M1 暴露。
