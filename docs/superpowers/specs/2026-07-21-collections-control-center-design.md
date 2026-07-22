# 控制台 + 分组(Collections)— 设计 spec

日期:2026-07-21
状态:待评审

## 1. 背景:方向修正

此前最大的投入是检视器/adapter spec 体系(M2 内核、YAML spec、M4 规划覆盖 45 个平台)。复盘结论:**它回答的是一个用户不怎么问的问题("agent 实际加载了什么"),看懂了也不解决实际痛点——伪需求**。

真实的用户抱怨(来自公开讨论):

- "全局的 SKILLS 真的不适合多装……SKILLS 适合分发,但是不适合安装"——装得越多,agent 上下文里的清单越长,精准度越差
- "参考 fanbox 做了改进……可以跨工作区加载 skill,这样 skill 清单不会很长,agent 能更精准使用 skill"

由此确立两个真实需求:

1. **更方便地管理 skills,支持用户自定义分组**
2. **多 agent 之间的按需分发:库可以大,但 agent 里只挂当下需要的**

产品的主语从"安装器"变为"**库 → 分组 → 挂载**"。UI 随之从"三栏列表管理器"重构为"控制中心"。

## 2. 目标与非目标

**目标(本期)**

- 用户可创建自定义分组(Collection),把库中技能归入组内
- 组可一键挂载到任一 agent(symlink);一键卸载,技能保留在库中
- 默认落地页改为控制台(分组卡片墙),一进来只看到"我的组织方式 + 当前生效状态"
- 检视器连根拔除(UI 层 + 内核 + CLI + adapter spec),取消 M4

**非目标(明确不做)**

- 嵌套分组、标签体系、分组导入导出、TUI 同步、云同步
- M4(45 平台 spec 覆盖)——取消
- 工作区/项目绑定自动挂载——仅预留接口,属 Phase 2
- Library 各列表页、Agent 主页(除拆检视器卡)、Project 区、冲突检测——保持现状

## 3. 数据模型

SwiftData 新增 `CollectionRecord`(与 `SkillRecord` 并列,不碰 skills 磁盘格式):

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID | |
| name | String | 组名 |
| sortOrder | Int | 控制台排序 |
| memberSkillIDs | [String] | 成员,引用 skill.id(`{source}:{name}`) |
| mountedAgentIDs | [String] | **装载意图**:用户希望挂载到哪些 agent(AgentRegistry id) |
| projectPaths | [String] | 预留,Phase 2 工作区绑定 |

- 成员引用而非拷贝;技能从库中消失时组里保留 ID 并标"缺失"(它可能又被装回来)
- **磁盘是挂载状态的真相**:`mountedAgentIDs` 只记意图。刷新时对比意图 vs 磁盘(symlink 是否存在),不一致显示黄灯 + "按意图重新应用";绝不未经操作自动改磁盘

## 4. 挂载语义(ActivationService)

复用 `SymlinkInstaller` 的 canonical + symlink 模式(canonical = `~/.config/agents/skills/`):

- **挂载 组→agent**:组内每个技能 symlink 进该 agent 的 skills 目录。技能若还是某 agent 目录里的实体副本(`.local` source),先**迁移**进 canonical,并在原 agent 目录留 link——原 agent 不受影响
- **卸载**:删目标 agent 里的 link;canonical 永远保留,库不丢东西
- **冲突**:目标目录已有同名实体(非指向 canonical 的 link)→ 跳过该技能并汇报,不阻塞整组
- 纯函数 `reconcile(intent: [String], disk: [String])` 计算意图与磁盘差异,供 UI 状态灯使用
- **已知限制**:组成员可重叠——卸载组 A 会删掉与已挂载组 B 共享的 link;B 通过黄灯 + "按意图重新应用"自愈。成员 id 在挂载后重扫时按名字重对(迁移会把 path-keyed id 变成 name-keyed id)

## 5. 信息架构与 UI

草图:控制台 + 组详情两帧(低保真已评审,TOOLS 区已移除)。

### 5.1 侧边栏

- 顶部新增 **控制台**(默认落地页,取代 All Skills)
- Library(All/Installed/Starred/Trial/Sources)原样保留,降级为"浏览/搜索大库"的次要入口
- **TOOLS 区(检视器)删除**;Agents 主页、Project 区不变

### 5.2 控制台(卡片墙)

- 顶部摘要行:"N 个分组 · M 个技能正挂载在 K 个 agent" + "＋ 新建分组"
- 分组卡片:组名、成员数、各 agent 挂载行(状态灯 + 开关)
  - 状态灯:绿 = 挂载中;灰 = 未挂载;黄 = 意图与磁盘不一致(附"按意图重新应用")
- 虚线"新建分组"卡收尾

### 5.3 组详情页

- 头部:组名、成员数、一排 agent 开关胶囊;一行语义说明(开 = symlink 进 agent,关 = 仅移除链接、技能留库)
- 成员列表:复用现有技能行(搜索/星标/右键/批量操作保留);底部"＋ 添加技能"搜索 picker
- 加成员的另一入口:库页技能行右键 "Add to Collection"

### 5.4 状态反馈

- 挂载/卸载结果以行内摘要汇报(成功 N 个、跳过 M 个及原因),不引入 toast
- 技能缺失(库中已无)在成员列表标灰"缺失",不参与挂载

## 6. 检视器拆除清单(连根拔)

**删除文件**

- `SkillsManager/Views/InspectorView.swift`(含 InspectorDetailView)
- `SkillsManager/Services/InspectorViewModel.swift`
- `SkillsManager/Models/InspectorPresentation.swift`
- `Sources/SkillsKernel/EffectiveAgentInspector.swift`
- `Sources/SkillsKernel/AdapterSpec.swift`
- `Sources/SkillsKernel/SpecCatalog.swift`
- `Sources/SkillsKernel/SpecChecker.swift`
- `Sources/SkillsKernel/Resources/platform-specs/`(整目录)
- `Sources/skm/`(整个 target 均为检视器 CLI,连 target 删除,Package.swift 同步)
- 测试:`InspectorViewModelTests.swift`、`InspectorSnapshotTests.swift`、`Tests/SkillsKernelTests/EffectiveAgentInspectorTests.swift`

**修改文件(删分支)**

- `ContentView.swift`:删 `inspectorModel` state、`.inspector` content/detail 路由、AgentHomeView 的 `specEntry`/`onOpenInspector` 传参
- `SidebarFilter.swift`:删 `.inspector` case;`SidebarView.swift`:删 TOOLS 区
- `AgentHomeView.swift`:删"实际加载"卡,agent 主页 = 头部卡 + 冲突卡 + skills 列表;`AgentHomeSupport.specEntry` 删除(`conflicts(involving:)` 保留)
- `SkillListView.swift`、`SkillConflict.swift` 等 switch 中 `.inspector` 分支同步删除
- `AgentHomeTests.swift`:删 spec 匹配测试(保留冲突过滤);`AgentHomeSnapshotTests.swift`:删 with-spec 场景,保留两卡版快照
- README:删 Inspect 条目与 spec 相关段落,改 agent 主页条目;`description-translations.json` 清理检视器相关串
- docs/goals 等规划文档:标记 M4 取消、检视器移除

**保留**:`AgentRegistry`(技能扫描依赖,与 spec 无关)、冲突检测、agent 主页其余部分。

## 7. 阶段划分

**Phase 1(本期交付)**

1. 检视器连根拔除(第 6 节)
2. `CollectionRecord` + ActivationService(挂载/卸载/迁移/reconcile)
3. 控制台(卡片墙)+ 组详情页 + 默认落地页切换
4. 库页右键 "Add to Collection"

**Phase 2(后续,仅预留接口)**

- `projectPaths` 生效:打开项目时把绑定的组幂等自动挂载到指定 agent
- **只自动挂载,不自动卸载**(用户可能手动调过;卸载给显式操作)

## 8. 测试

- `CollectionRecord`:持久化、成员增删、缺失标记
- ActivationService:实体技能迁移 canonical + 原 agent 留 link、挂载/卸载、冲突跳过并汇报、`reconcile` 纯函数各分支
- 快照测试(NSWindow 离屏 harness):控制台卡片墙(正常/不一致/空态)、组详情页
- 检视器拆除后:`swift build`、`swift test`、`xcodegen + xcodebuild` 全绿,无残留引用
- UI 实现过一遍 baseline-ui 清单

## 9. 风险

- **symlink 兼容性**:已被现有 `.symlinked` source 验证,风险低
- **实体迁移的侵入性**:迁移会改变技能在磁盘上的位置(原处变 link);通过"原 agent 留 link"保证行为不变,并在挂载结果中明确告知
- **意图与磁盘漂移**:用户手动删 link 后以黄灯提示 + 手动纠正,不自动改磁盘,避免惊吓
