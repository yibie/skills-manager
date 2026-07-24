# Skills Manager 改进 Backlog(六方评估综合)

仓库根:`/Users/chenyibin/Documents/prj/skills-manager`(下文路径均相对此根)

## 0. 核实记录与综合裁决

### 0.1 论断核实

综合前抽查了约 20 条关键论断(直接读取文件与行号),**全部属实,无需丢弃任何评估员结论**。逐项核实包括:`docs/goals/effective-agent-inspector.md:1` 的 CANCELLED 标注、`ActivationService.swift:35` 空组 diverged、`ControlCenterView.swift:143` 无确认删除、`ContentView.swift:429-442` 挂载报告进 errorMessage、`DiscoverView.swift:147/612-613`、`SkillStore.swift:602-605/818-820`、`SymlinkInstaller.swift:146`、TUI off-by-one(`app-blessed.ts:520-536/1318-1379`)、TUI `rmSync` 无确认卸载、agent 注册表 46 vs 20 且 ID 系统性不一致、manifest 无 hash/commit 字段、全仓库无本地化基础设施、trial 死状态、侧栏无 Collections 区等。

两点补充细化(非错误,但影响实施):

1. **`Tests/SkillsManagerTests/ActivationServiceTests.swift:44` 目前显式断言空组挂载返回 `.diverged`**——修复 P0-6 时必须同步修改该断言,否则测试红灯。
2. **任务背景中"检视器先行为现行方向"与仓库记录冲突**:`docs/goals/effective-agent-inspector.md:1` 已于 2026-07-21 标注 CANCELLED 并移除实现。本 backlog 的加权按"**透明性优先仍然有效**(已制度化于 `docs/ui-domain-knowledge.md:27-31`,且被现主线继承)、**检视器先行待裁决**(P0-1)"处理:服务透明性的条目(遮蔽可见、冲突收敛、provenance、漂移检测)获得提级,检视器整体重启只作 P2 条件项。

### 0.2 冲突建议的取舍决定

| 冲突 | 决定 | 理由 |
|---|---|---|
| Trial 状态:删除死状态 vs 接通试用安装 | **删除**(P1-14) | 两位评估员均倾向删;半成品状态机(永远空的过滤器、不可达菜单分支)比没有更误导,接通需先有真实需求论证 |
| TUI:按 CLAUDE.md 规范化 blessed 用法 vs 冻结迁移 Swift CLI | **冻结 + 只修信任级 bug**(P0-8/P0-9/P1-13),长期走 Swift 内核+CLI(P2-1) | 3 个月 19:87 的提交比、注册表/生命周期/Discover 全面分叉证明双写已失败;blessed 约十年未维护。故 TUI 评估员的"全面落实 list 约定"大改(其改进 7)**不排期**,与冻结决定冲突;仅保留已发布版本的安全与正确性修复 |
| 检视器重启形态 | 不进主线;P2-9 条件项(嵌入式面板),先做两方向下都成立的 P1-5 遮蔽卡 | 复盘留下的透明性特性(冲突、状态灯、provenance)全被保留且加码,说明被否定的是"独立树视图"形态而非透明性本身 |
| 更新安全:小步(hash+Trash)vs 中步(diff 确认 sheet) | 合并为 P0-3 分两阶段,第一阶段必须做 | 消灭"唯一会静默毁数据的路径"优先,diff 展示可随 P1-2 的 hash 地基跟进 |
| canonical 库 git 化(两位评估员重复提出) | 合并为 P2-2 一项 | 依赖 P0-3/P1-2 先落地 |
| Discover 同名误判(三位评估员重复提出) | 合并为 P0-2 一项 | 证据与方案一致 |

---

## P0 —— 信任与数据安全缺陷(改动小、必须立即修)

### P0-1 裁决产品方向,统一事实来源(工作量:小)

**为什么**:两个"事实源"直接冲突——用户 memory 仍以 2026-07-12 检视器方向为现行,而 `docs/goals/effective-agent-inspector.md:1` 已标 CANCELLED(2026-07-21)且实现已删(commits 18e801f/f6a8b1f/1cb9ac8);`docs/goals/effective-agent-schema.md:1-5` 无 CANCELLED 标注,仍宣称生产者为 `skm inspect` / `SkillsKernel.EffectiveAgentInspector`(两者已不存在,已核实);`.claude/worktrees/agent-a40681d9285a5696d/`(994M,untracked)完整保留已删的 InspectorView.swift 等,后续 agent 检索易把已删代码误当现行实现。方向取消依据仅两条匿名讨论、无自有用户验证,九天立项-交付-推翻的震荡若再回摆,~3000 行重建成本会重复发生。任何规划(包括本次评估的前提)都需要一个唯一基准。

**涉及文件**:`docs/goals/effective-agent-schema.md`、`docs/goals/effective-agent-schema.json`、`docs/goals/effective-agent-inspector.md`、用户 memory(`~/.claude/projects/-Users-chenyibin-Documents-prj-skills-manager/memory/`)、`AGENTS.md`、`.claude/worktrees/`

**验收标准**:
- 做出书面裁决:废止(补一份含用户证据的"为何取消"决策记录)或恢复(撤销 CANCELLED 并写"为何回摆");
- `effective-agent-schema.md/.json` 头部与 goal doc 同款 CANCELLED 横幅;memory 索引行更新为"已于 2026-07-21 取消,现行方向见 collections 设计 spec"(或反向);
- 994M worktree 删除,或在 AGENTS.md 注明存档性质并 gitignore。

### P0-2 Discover 按名匹配可误标 Installed、误删用户同名本地技能 → 改 provenance 精确匹配(工作量:小)

**为什么**:三位评估员独立发现。`SkillsManager/Views/DiscoverView.swift:147` 用 `$0.name == entry.skillId || $0.name == entry.name` 判定 Installed;`SkillsManager/Services/SkillStore.swift:602-605` 的 `removeDiscoverSkillFromLibrary` 同样按名取第一个匹配走 provider 删除(均已核实)。用户手写的本地技能若与 skills.sh 热门技能同名,会被标为 Installed,在 Discover 点 "Remove from Library" 删掉的是用户自己的技能;两个不同仓库发布同名 skill 时互相误判误删。`docs/ui-domain-knowledge.md:47` 明文"同名不是充分证据",而 `ManagedSkillManifest` 里 sourceURL/skillID 数据齐全却没被用上。

**涉及文件**:`SkillsManager/Views/DiscoverView.swift`、`SkillsManager/Views/ContentView.swift`、`SkillsManager/Services/SkillStore.swift`

**验收标准**:
- isInstalled 优先比对 `skill.provenance.skillID == entry.skillId && sourceURL` 对应 entry 来源,无 provenance 才回退名字匹配;
- 仅名字相同但 provenance 不符时显示中性徽章(如 "Same name in library")且不提供 Remove;
- `removeDiscoverSkillFromLibrary` 只按 provenance 匹配;
- 新增单测:同名不同源技能不被误判、不被误删。

### P0-3 更新静默销毁本地修改:加漂移检测,备份改进废纸篓(工作量:小)

**为什么**:全应用无任何更新检查(grep updateAvailable/checkForUpdate 零命中),`SkillLifecycleService.update`(`InstallService.swift:154-214`)直接重新下载整仓 HEAD 覆盖;`SymlinkInstaller.swift:146` 在替换成功后 `try? fm.removeItem(at: backup)` 删除备份(已核实)——用户对托管技能 SKILL.md 的本地修改在点击 Update 后无提示永久丢失。`SkillDetailView.swift:226-233` 的 Update 按钮无确认、无进度。这是当前**唯一会静默毁数据的路径**,与 "trustworthy lifecycle control plane" 直接矛盾。

**涉及文件**:`SkillsManager/Services/SymlinkInstaller.swift`、`SkillsManager/Services/InstallService.swift`、`SkillsManager/Views/SkillDetailView.swift`

**验收标准**:
- 安装/更新时把内容 hash(复用 SkillConflictDetection 的 SHA-256)写入 manifest;Update 前重算 canonical hash,不符时弹确认"本地副本已被修改,更新将覆盖(旧版移入废纸篓)";
- `SymlinkInstaller.swift:146` 的 removeItem(backup) 改为 trashItem(或移入 `~/.skills-manager/history/<name>/<timestamp>/`);
- 失败回滚路径(147-152 行)行为不变,现有 SymlinkInstallerTests 全绿;新增"本地漂移时更新需确认"的测试。

### P0-4 promoteSkill 用未消毒的 frontmatter name 拼路径,可逃出 skills 目录(工作量:极小)

**为什么**:`SkillsManager/Services/SkillStore.swift:818-820`(已核实)`destDirName = skill.displayName...` 后直接 `appendingPathComponent(".claude/skills/\(destDirName)")` 并 createDirectory;displayName 来自第三方 SKILL.md 的 `name:` 字段,含 `/` 或 `../` 时会在 skills 目录外创建/写入。全库其他写路径均经 `SymlinkInstaller.sanitize`(`SymlinkInstaller.swift:283-288`),唯此处遗漏且无测试覆盖。

**涉及文件**:`SkillsManager/Services/SkillStore.swift`、`Tests/SkillsManagerTests/`

**验收标准**:
- destDirName 经 `SymlinkInstaller.sanitize` 处理;
- 新增回归测试:frontmatter name 含 `../evil`、`a/b`、空串时,落点始终在 `~/.claude/skills` 内(可注入临时 home 或抽出纯函数测试)。

### P0-5 删除分组无确认且不清理已挂载 symlink,留下 UI 中不可见的无主链接(工作量:小)

**为什么**:`ControlCenterView.swift:143` `Button("删除分组", role: .destructive, action: onDelete)` 直接执行;`ContentView.swift:254-257` 的 onDelete 仅 `modelContext.delete + refreshMountStatuses`(均已核实)。已挂载 agent 目录里的 link 原样留在磁盘,而状态重建只遍历现存 collections(`SkillStore.swift:1395-1413`),删除后 agent 仍在加载这些技能但控制面已无任何呈现——违反 `docs/ui-interaction-review.md:57` 阻断规则与 lifecycle control plane 定位。

**涉及文件**:`SkillsManager/Views/ControlCenterView.swift`、`SkillsManager/Views/ContentView.swift`

**验收标准**:
- 删除改为 confirmationDialog:列出当前挂载的 agent 名单,提供"卸载链接并删除分组"(对每个 mountedAgentID 先调 ActivationService.unmount)与"仅删除分组(保留链接)"+ 取消;
- 确认文案按 domain doc 写明"技能保留在 Library";
- 走默认路径删除后,磁盘上无该组遗留 link。

### P0-6 空分组可挂载并落入永远无法变绿的黄灯陷阱(工作量:小)

**为什么**:`ControlCenterView.swift:181-191` 与 `CollectionDetailView.swift:61-71` 的"挂载到…"菜单不检查成员是否为空;`ActivationService.swift:35` 对 `memberCount==0 && intentMounted` 返回 `.diverged`(均已核实)——空组挂载后立即琥珀点"与磁盘不一致","重新应用"挂载 0 个技能后依旧 diverged,永久警告。`docs/ui-domain-knowledge.md:36-37` 明文"空 Collection 的主操作是添加技能,不是挂载;依赖成员的操作应隐藏或禁用"。注意:`ActivationServiceTests.swift:44` 目前断言该行为,需同步修改。

**涉及文件**:`SkillsManager/Services/ActivationService.swift`、`SkillsManager/Views/ControlCenterView.swift`、`SkillsManager/Views/CollectionDetailView.swift`、`Tests/SkillsManagerTests/ActivationServiceTests.swift`

**验收标准**:
- 空组的"挂载到…"替换为禁用态并说明"先添加技能再挂载";空组卡片主操作变为"添加技能"(打开 MemberPicker);
- `ActivationService.status` 对 memberCount==0 返回 `.unmounted`(或新增 `.empty`),`ActivationServiceTests.swift:44` 断言同步更新;
- 手工验证:空组不再出现"重新应用"死循环黄灯。

### P0-7 挂载"部分成功/跳过"用全局 "Error" 弹窗汇报,违背自家 spec(工作量:中)

**为什么**:`ContentView.swift:434/442` 把 `report.summaryText`(中文"成功 N 个,跳过 N 个:…")塞进 `store.errorMessage`,由 166-173 行唯一的全局 alert(英文标题 "Error")弹出(已核实)。部分成功被标成错误、模态打断、远离操作对象、无下一步。而 `docs/superpowers/specs/2026-07-21-collections-control-center-design.md:87-89` 明文"挂载/卸载结果以行内摘要汇报…不引入 toast",`docs/ui-domain-knowledge.md:31` 要求"在相关对象附近报告并提供下一步"——规范写了,实现没做。

**涉及文件**:`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Views/ContentView.swift`、`SkillsManager/Views/ControlCenterView.swift`、`SkillsManager/Views/CollectionDetailView.swift`

**验收标准**:
- SkillStore 新增 `mountReports: [String: MountReport]`(key 同 mountStatuses),setMounted 写 report 而非 errorMessage;
- CollectionCard 底部状态行与 agent 胶囊就近显示"成功 N · 跳过 M",跳过项可展开原因;
- `errorMessage` 仅保留给 agent 目录创建失败等真错误;部分成功不再触发 "Error" alert。

### P0-8 TUI Discover 列表高亮与操作对象错位一行(off-by-one)(工作量:小)

**为什么**:`tui/src/app-blessed.ts:520-526` 的 discover items 含 2 行表头(标题+分隔线),条目从下标 2 开始,但所有选择代码用 +1 偏移(536 行 `list.select(selectedIndex + 1)`、1326/1345/1374,g 键 `select(1)` 选中的是分隔线),'select' 回调用 -1 还原(74-76)(均已核实)。结果:高亮永远停在实际操作对象的上一行,i/x/o/O/d 作用于高亮行的下一条——"发现→安装"主流程的信任级 bug,git 考证已存在 3 个月(69e81e0 加分隔线未改偏移)。

**涉及文件**:`tui/src/app-blessed.ts`

**验收标准**:
- 删除列表内的标题与分隔线两行(面板 label 已由 updatePanelChrome 渲染同样信息,297-301 行),同步移除全部 ±1 偏移与特殊分支(74-76/536/1326/1345/1362/1374);
- `npm run build`(tsc)通过;手工验证:高亮行 = 详情面板 = i/x 操作对象,g/G 选中首/末条目。

### P0-9 TUI 文件系统安全:x 键无确认永久删除、可静默破坏 mac 端受管挂载、复制无 symlink 防护(工作量:小)

**为什么**:x 键直接 `fs.rmSync(target, {recursive:true, force:true})` 且无任何确认(`tui/src/services/InstallService.ts:78-94`、`app-blessed.ts:682-733`,已核实),违反 `docs/ui-domain-knowledge.md:41-53`("外部内容只能进 Trash")与 `ui-interaction-review.md:57` 阻断规则;install 先 rmSync 再复制(`InstallService.ts:65-69`),若目标是 mac 端指向 canonical 库的受管 symlink(`SymlinkInstaller.swift:17-21`),会把受管挂载静默替换成失管副本,制造 Conflicts 页要检测的分歧;`copyRecursive`(`InstallService.ts:27-40`)用 statSync 跟随 symlink 递归复制且无环检测,循环链接即无限递归。

**涉及文件**:`tui/src/services/InstallService.ts`、`tui/src/app-blessed.ts`

**验收标准**:
- x 前弹 y/n 确认 overlay;真实目录不再 rmSync,改移入 `~/.Trash`(darwin rename)或 `~/.skills-manager/trash/<时间戳>-<名>`;
- lstat 发现目标是指向 `~/.config/agents/skills` 或 `~/.agents/skills` 的 symlink 时拒绝并提示"由 Skills Manager App 管理,请在 App 内 Unmount";
- copyRecursive 改 lstatSync,symlink 显式处理(复制链接本身或跳过)+ 深度上限;tsc 构建通过。

---

## P1 —— 高价值近期项(信任地基与体验断层)

### P1-1 标识符体系统一:agent ID 单一事实源 + compatibleAgents 存 ID(工作量:小→中)

**为什么**:注册表双语言各写一份且系统性漂移(已核实):Swift `AgentRegistry.swift:74-121` 约 46 个 agent,TUI `SkillStore.ts:26-47` 仅 20 个,TUI 缺 cursor/opencode/windsurf/cline 等头牌;同一 agent 两端 ID 不同(copilot vs github-copilot、kiro vs kiro-cli、qwen vs qwen-code、iflow vs iflow-cli、commandcode vs command-code、kilocode vs kilo),两边都把各自 ID 传给 `npx skills add --agent`,至多一套匹配 skills CLI。另外 Swift 侧 `compatibleAgents` 存显示名("Claude Code"/"Universal",`ClaudeCodeAdapter.swift:208`、`UniversalAdapter.swift:108-132`),`SkillStore.swift:647-649` 再按 displayName 反查 id,"Universal" 反查为 nil 被静默丢弃;TUI 却存 agentID。

**涉及文件**:`SkillsManager/Adapters/AgentRegistry.swift`、`tui/src/services/SkillStore.ts`、`tui/src/services/DiscoverInstallService.ts`、`SkillsManager/Adapters/ClaudeCodeAdapter.swift`、`SkillsManager/Adapters/UniversalAdapter.swift`、`SkillsManager/Adapters/OpenClawAdapter.swift`、`scripts/`

**验收标准**:
- 一份 checked-in 的 shared agents.json(或生成脚本,仓库已有 `scripts/build_description_translation_catalog.py` 先例):id、displayName、skillsDir、detectPath;
- Swift 测试断言 AgentRegistry.all 与 JSON 一致;脚本/测试校验 TUI 列表是其子集且 ID 完全同名;`--agent` 传值与 skills CLI 实际接受的 key 逐一核对;
- compatibleAgents 全部改存 agentID,显示层经 `AgentRegistry.agent(id:)?.displayName` 渲染,删除 displayName 反查。

### P1-2 安装固定 commit SHA + 记录内容哈希,详情页可查证(工作量:中)

**为什么**:`ManagedSkillManifest` 只有 sourceURL/skillID/sourceRef/installedAt(`InstallService.swift:463-490`,已核实),无 commit、无 hash;`repositoryRef` 在 SkillsDirectoryService 全文零赋值(已核实),zipball 永远取默认分支 HEAD(`InstallService.swift:543-561`)。用户安装前只见 skills.sh 截断 1200 字符的 excerpt,实际落盘的是 GitHub 当前 HEAD 完整目录——预览与安装之间存在完整 TOCTOU 窗口,仓库作者可在收录后随时替换内容。这是篡改检测、更新 diff、P1-3 更新检查的共同地基。

**涉及文件**:`SkillsManager/Services/InstallService.swift`、`SkillsManager/Models/Skill.swift`、`SkillsManager/Views/SkillDetailView.swift`

**验收标准**:
- zipball 顶层目录名 `{owner}-{repo}-{shortSHA}` 解析出 commit 写入 manifest 新字段 resolvedCommit;落盘目录逐文件 SHA-256 汇总写入 contentHash;
- annotate() 读回,SkillDetailView metaRow 展示 commit 短哈希与安装时间;
- 旧 manifest(字段缺失)兼容,现有测试全绿。

### P1-3 托管技能更新检查与"可更新"徽章(工作量:中,依赖 P1-2)

**为什么**:README.md:161 路线图第一条 "Auto-update detection" 未实现,当前 Update 是盲更新(见 P0-3)。有了 resolvedCommit 后,批量比对远端最新 sha 即可让"更新"从赌博变成知情决策——"可信生命周期控制面"最刺眼的缺口。

**涉及文件**:`SkillsManager/Services/InstallService.swift`、`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Views/SkillListView.swift`、`SkillsManager/Views/SkillDetailView.swift`

**验收标准**:
- `checkForUpdates(skills:)` 经 GitHub API 批量比对;SkillStore 增 updatableSkillIDs;
- 列表行尾与详情 Update 按钮显示"可更新"徽标;无更新时 Update 不再默认高亮;
- 网络失败静默降级不阻塞扫描,有测试(URLProtocol stub 先例见 EnvironmentAndNetworkingTests)。

### P1-4 冲突收敛闭环:内联 diff + "以此副本为准"(工作量:中,透明性加权提级)

**为什么**:检测已就绪但只读:详情文案明确要求用户 "Reinstall the skill to all agents to converge the copies"(`ConflictsView.swift:91`,已核实),页面却无该动作,InstanceCard 只有 Show in Finder / Open SKILL.md(131-144);hash 徽章无法帮用户判断哪份是对的,比较副本要开两个编辑器。TUI 有 diff 能力而 macOS 端没有。违反 `ui-domain-knowledge.md:31` "冲突…提供下一步"。发现→解决的闭环是透明性价值兑现的关键一半。

**涉及文件**:`SkillsManager/Views/ConflictsView.swift`、`SkillsManager/Services/ActivationService.swift`、`SkillsManager/Services/SkillStore.swift`

**验收标准**:
- 每个 InstanceCard 增 "以此副本为准…" 按钮:确认后写入 canonical(复用 ensureCanonical),其余实例走"搬走原实体→留 link→旧副本进废纸篓"流程,逐实例结果就近汇报;
- 两副本场景提供 SKILL.md 行级 diff 视图;
- 操作完成重扫后该冲突从列表消失;新增服务层测试。

### P1-5 遮蔽(shadowing)透明化最小卡(工作量:中,透明性加权提级)

**为什么**:当前只能回答"我打算挂什么/磁盘实际挂了什么"(ActivationService 三态),原方向核心问题"该平台实际加载了什么、谁遮蔽谁"无处可答:`SkillConflict.swift:28-29` 注释明确把 project-local 遮蔽 shared 副本排除出冲突("by design, not a conflict")且不在任何 UI 呈现。挂载工作流恰恰需要它——用户会遇到"挂了但被项目副本遮蔽"。现有扫描已同时拿到 project/agent/canonical 三处副本,无需恢复 spec 体系,约 200 行即可回答 skills 子集的加载真相,两个方向下都成立。

**涉及文件**:`SkillsManager/Models/SkillConflict.swift`(或新建 ShadowingDetection)、`SkillsManager/Views/AgentHomeView.swift`、`SkillsManager/Services/SkillStore.swift`

**验收标准**:
- 与 SkillConflictDetection 平行的 ShadowingDetection 纯函数:同名 skill 跨 scope 共存时按优先级标注生效者与被遮蔽路径,有单测;
- AgentHomeView 的 headerCard 与 conflictsCard 之间新增"生效来源"卡,展示被遮蔽项及路径;
- 与 Conflicts(内容分歧)在 UI 语义上明确区分。

### P1-6 UI 语言统一 + String Catalog(工作量:中)

**为什么**:核心路径中英文混排且无任何本地化基础设施(已核实:find 全仓库无 .strings/.xcstrings/.lproj,仅第三方 checkout):默认落地页 ControlCenterView 整页中文("控制台/挂载于/重新应用/删除分组"),侧栏"控制台"与 "Discover/All Skills" 并列(`SidebarFilter.swift:19-27`),"Add to Collection" 英文标题配中文内容(`CollectionPickerSheet.swift:25-54`),全局 alert 英文 "Error" 弹中文 summaryText。产品自带 8 语描述翻译目录,UI 自身却语言分裂。

**涉及文件**:`SkillsManager/Views/ControlCenterView.swift`、`CollectionDetailView.swift`、`CollectionPickerSheet.swift`、`AgentHomeView.swift`、`SkillsManager/Models/SidebarFilter.swift`、`SkillsManager/Services/ActivationService.swift`、新增 `Localizable.xcstrings`

**验收标准**:
- 约 40 处硬编码中文串迁入 String Catalog,英文为基准 + zh-Hans 本地化,UI 语言跟随系统;
- 同一视图/同一 sheet 内不再出现两种语言混排;
- MountReport.summaryText 等服务层用户可见文案同样本地化。

### P1-7 供应链与 provenance 收口:npx 版本固定 + 迁移剥离 manifest + host 白名单(工作量:小)

**为什么**:① `npx -y skills ...` 无版本 pin(`InstallService.swift:97/161/222`,TUI `DiscoverInstallService.ts:10-22`,已核实),npm 包被接管即本机任意代码执行;② provenance 信任锚在技能目录内可写文件上:Discover 安装会剥离包内自带 manifest(`SymlinkInstaller.swift:135`,已核实),但 `ActivationService.ensureCanonical` 的实体迁移分支原样 move 不清理——伪造 `.skills-manager.json`(sourceURL 指向攻击者仓库)的目录挂载迁移后即获得 canUpdate=true,点 Update 就从攻击者仓库拉取覆盖,一次内容植入升级为持久更新通道劫持。

**涉及文件**:`SkillsManager/Services/InstallService.swift`、`SkillsManager/Services/ActivationService.swift`、`tui/src/services/DiscoverInstallService.ts`

**验收标准**:
- `static let skillsCLIVersion` 常量,两端统一 `npx -y skills@<pinned>`;
- ensureCanonical 迁移分支 move 后剥离 managedManifestName(与 SymlinkInstaller:135 对齐);
- annotate() 校验 manifest sourceURL.host == "github.com",不合规降级 .manual;各补一条测试。

### P1-8 安全关键路径测试补齐(工作量:小)

**为什么**:`validatePackageLinks`(`SymlinkInstaller.swift:220-241`,包内 symlink 逃逸防线)在 Tests/ 全目录零引用,重构即可能无声失效;sanitize 边界(`../evil`、超长名)与 takeOverSkillsCLIInstallation 失败回滚同样无断言。对主打 trustworthy 的产品,防线必须有回归保护。

**涉及文件**:`Tests/SkillsManagerTests/SymlinkInstallerTests.swift`、`Tests/SkillsManagerTests/EnvironmentAndNetworkingTests.swift`

**验收标准**:
- 含指向包外 symlink 的 fixture 必须抛 unsafePackageLink,包内相对链接放行;
- sanitize 对 `../`、`/`、超长名的输出断言;接管失败回滚断言;全部为纯文件系统单测,无网络依赖。

### P1-9 Library 列表加载态与空态动作(工作量:小)

**为什么**:`SkillStore.swift:198` 有 isLoading,但 `SkillListView.swift:4-14` 签名不接收(已核实),首次扫描/⌘R 期间显示假空态 "No Skills";该空态无任何按钮,不指向 Discover。首启空库时默认落地页(控制台)也是死胡同:建组后 MemberPicker candidates 为空,正确第一步(Discover)只藏在侧栏。违反 `ui-interaction-review.md` §3 状态矩阵与 §5 空态三问。

**涉及文件**:`SkillsManager/Views/SkillListView.swift`、`SkillsManager/Views/ContentView.swift`、`SkillsManager/Views/ControlCenterView.swift`

**验收标准**:
- SkillListView 接收 isLoading,loading 且列表空时显示 ProgressView("Scanning agent directories…");
- "No Skills" 空态加 "Browse Discover" 按钮(切 selectedFilter = .discover);
- 控制台空库摘要区加同样的 Discover 入口。

### P1-10 侧栏 Collections 区与导航选中态(工作量:小)

**为什么**:`SidebarView.swift:28-68`(已核实)无 Collections 区;进入组详情后 `selectedFilter = .collection(id,name)` 不匹配任何侧栏行,List 选中高亮消失,用户失去方位;组间切换需两跳。SidebarFilter.collection case 与选中机制现成,几乎零风险。

**涉及文件**:`SkillsManager/Views/SidebarView.swift`、`SkillsManager/Views/ContentView.swift`

**验收标准**:
- 侧栏新增 Section("Collections") 列出各组(名称 + 成员计数),ContentView 传入 collectionRecords;
- 进入组详情时侧栏对应行保持选中高亮;组间切换一跳完成。

### P1-11 呈现层修复:状态灯无障碍标签 + Discover 分类胶囊暗色对比(工作量:小)

**为什么**:① statusDot 是裸 `Circle().fill(color)`(`ControlCenterView.swift:213-217`、`CollectionDetailView.swift:124-127`,已核实),无 accessibilityLabel,全 Views 目录仅 2 处 a11y 标签;`docs/ui-domain-knowledge.md:96-104` 明文"不只依赖颜色表达挂载/偏差"且"无障碍缺陷是完成阻断项,不能延期"。② `DiscoverView.swift:612-613`(已核实)选中胶囊 `Color.primary` 底 + `Color.white` 字,暗色模式下 primary≈白,白字白底不可读,应用跟随系统外观必现。

**涉及文件**:`SkillsManager/Views/ControlCenterView.swift`、`SkillsManager/Views/CollectionDetailView.swift`、`SkillsManager/Views/DiscoverView.swift`

**验收标准**:
- statusDot 加 `.accessibilityLabel`("Mounted / Out of sync with disk / Not mounted"),agent 胶囊 `.accessibilityElement(children: .combine)`;
- CategoryChip 选中态改 `Color.accentColor` 底 + 白字(或 primary 底 + windowBackgroundColor 前景),暗色下可读;
- VoiceOver 朗读验证 + 暗色截图验证。

### P1-12 卸载残留不摘除挂载意图(工作量:极小)

**为什么**:`ContentView.swift:439-443` 卸载后无条件 `mountedAgentIDs.removeAll`,即使 report.skipped 非空(实体目录不删除,`ActivationService.swift:93-95`,已核实);intent 移除后 refreshMountStatuses 不再遍历该组×agent,遗留实体从状态灯中彻底消失,只能等内容分叉后以冲突形式再现——"冲突不能伪装成成功"在卸载路径上失守。

**涉及文件**:`SkillsManager/Views/ContentView.swift`

**验收标准**:
- 仅当 report.skipped 为空才移除 agentID;有残留时保留 intent,状态灯持续黄灯 + "重新应用",配合 P0-7 的就近报告说明原因(约 5 行 diff)。

### P1-13 TUI 已发布版本的信任级小修集(工作量:小)

**为什么**(均已核实):① `showSuccessStatus/showErrorStatus` 的 setTimeout 触发全量 render(`app-blessed.ts:266-276`),render 无条件把焦点还给三栏(654-661),overlay 打开期间(grabKeys=true)触发即除 Ctrl+C 外全键盘失灵的软死锁;② agent 选择弹窗首帧把所有行渲染成 `[✓]` 但 selectedAgents 只含 claude-code(726-729),直接回车实际只装一个,与所见相反;③ 卸载只删 claude-code 副本却提示 "Uninstalled skill: X"(`DiscoverInstallService.ts:25-28`);④ 成功消息一律 `{red-fg}` 渲染成错误红(638 行);⑤ 逐 agent 串行各起一次 npx,CLI 本支持一次多 `--agent`。

**涉及文件**:`tui/src/app-blessed.ts`、`tui/src/services/DiscoverInstallService.ts`

**验收标准**:
- overlay 打开期间(检查 screen.grabKeys 或 activeOverlay 引用)render 不切焦点;状态定时器只调 updateStatusBar;
- 弹窗首帧勾选与 selectedAgents 一致;安装单次 npx 传多 --agent;
- 卸载提示如实("Removed Claude Code copy");成功消息 green-fg;tsc 构建通过。

### P1-14 移除死 Trial 状态机(工作量:小)

**为什么**:全库仅 `Skill+Mock.swift:76` 写入 `.trial`(已核实),生产代码无任何路径产生该状态;但 `SidebarFilter.trial`、过滤菜单 Trial 选项(永远空结果)、`SkillListView.swift:396-425` 的 Keep/Discard 分支仍保留。取舍:两位评估员均倾向删除——半成品状态机比没有更误导;若未来要"试用安装",需以真实需求重新立项。

**涉及文件**:`SkillsManager/Models/Skill.swift`、`SkillsManager/Models/SidebarFilter.swift`、`SkillsManager/Views/SkillListView.swift`、`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Views/ContentView.swift`

**验收标准**:
- 删除 `.trial`(及不可达的 `.notInstalled`/`.installed`/`.source` 侧栏 case)、过滤菜单选项、SkillRow trial 分支、只改内存的 `installSkill` 死方法;
- 构建与全部测试通过,Mock 同步更新。

---

## P2 —— 结构性与长期项

### P2-1 Swift 内核 SPM 抽库 + `skm` CLI(--json),TS TUI 冻结并逐步迁移(工作量:大)

**为什么**:四位评估员从不同维度指向同一根因——双实现深度分叉且共享磁盘状态:注册表(46 vs 20 且 ID 不同)、安装模型相反(canonical+symlink vs 直拷+git)、skills.sh 抓取器逐字两份、locale/缓存 key 两份镜像却共享同一缓存文件;TUI 冻结在 3 个月前(19:87 提交比),collections/conflicts/mount 零概念。f09a4cf 还删除了 Package.swift,把逻辑锁死在 GUI target,与 2026-07-12 "Swift 内核 + CLI"目标倒退。ActivationService/SkillConflictDetection/SkillParser/AgentRegistry/SymlinkInstaller 均无 SwiftUI 依赖,是天然 kernel 素材。

**涉及文件**:新建 `Package.swift`、`Sources/skills-cli/`、`project.yml`、`SkillsManager/Services/*`、`SkillsManager/Adapters/*`、`tui/src/services/SkillStore.ts`、`README.md`、`tui/README.md`

**验收标准**:
- 第一步(小,可立即做):两个 README 各加 TUI 定位说明("Library 浏览与安装的键盘入口,不含 collections;已冻结,只修安全类 bug");
- 第二步:最小 SPM library target 收纳无 UI 依赖服务,Xcode 工程引用,`swift test` 可独立跑;
- 第三步:`skm scan --json` 可执行 target;TUI loadSkills 改为 spawn 消费 JSON,删除 TS 侧扫描;之后逐步迁 install/star;
- 键位表与 `tui/docs/blessed-engine.md` 作为未来交互规格保留。

### P2-2 canonical 库 git 化:安装/更新/删除自动留痕 + 历史/回滚(工作量:大,依赖 P0-3/P1-2)

**为什么**:TUI 已验证该模式(`tui/src/services/GitService.ts` 的历史/diff/回滚),macOS 应用零回滚能力;"更新"因可撤销而变得可信,与"磁盘是真相"哲学同构,也为 export/团队同步打地基(README 路线图空档)。

**涉及文件**:`SkillsManager/Services/SymlinkInstaller.swift`、`SkillsManager/Services/InstallService.swift`、`SkillsManager/Views/SkillDetailView.swift`

**验收标准**:
- install/update/removeFromLibrary 成功后在 canonical 目录 git init(如无)+ commit(消息含 skill 名、操作、provenance);
- SkillDetailView 增 History 区块:log、diff、回滚到某版;回滚后触发重扫与状态灯刷新。

### P2-3 安装流程改为"下载→清单预览→选 agent→落盘",附固定风险提示(工作量:大)

**为什么**:全链路零内容风险警示;确认 sheet 只有 agent 多选(`DiscoverInstallToAgentView.swift:11-59`),用户凭 1200 字符 excerpt 决定安装完整仓库内容(含 scripts);DiscoverTryView 把远程 readmeExcerpt 直接拼进 system prompt(`DiscoverView.swift:711-726`),恶意作者可指示模型给出"安全好用"的背书,污染"安装前试用"评估环节;已装技能的 scripts 等执行面也无查看入口。

**涉及文件**:`SkillsManager/Views/DiscoverInstallToAgentView.swift`、`SkillsManager/Services/InstallService.swift`、`SkillsManager/Services/SkillStore.swift`

**验收标准**:
- 先下载解压到临时目录,确认 sheet 列完整文件清单(.sh/.py/.js 高亮)并渲染完整 SKILL.md;
- 底部固定一行"技能是 agent 将遵照执行的指令,可能包含脚本,安装前请审查";确认后才写 canonical + 建链;
- Try 的 prompt 注明摘要来源不可信,输出中不得替技能做安全背书。

### P2-4 Skill 身份稳定化:id 与扫描来源/顺序解耦(工作量:中)

**为什么**:同一目录被不同 adapter 记为 `local:<name>` 或 `universal:<path>`,mergeScannedSkills 保留先到者;挂载迁移进 canonical 后 id 变化,而 SkillRecord 以 skillID 为唯一键,star/installState 随 id 漂移丢失(现靠 `CollectionSupport.reconcileMemberIDs` 按名重对打补丁)。

**涉及文件**:`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Adapters/UniversalAdapter.swift`、`SkillsManager/Adapters/ClaudeCodeAdapter.swift`

**验收标准**:
- id 规范化为基于 resolvedSymlinks 后 canonical 路径的确定形式,同一目录无论谁先扫、是否迁移,id 不变;
- 短期兜底:applyPersistedSkillState 在 skillID 未命中时按 (name, resolved path) 双键回退匹配;
- 测试:挂载迁移前后 star 不丢。

### P2-5 扫描与解析健壮性:reload 代际 token + SkillParser 真 YAML + 抓取器 fixture(工作量:中)

**为什么**:① reloadSkills 可重入无代际控制,FileWatcher 触发与安装后 reload 交叠时旧扫描可覆盖新结果;② `SkillParser.swift:41-53` 手写单行 YAML 不支持 `description: >-` 多行,TUI 用 gray-matter 真 YAML,同一 SKILL.md 双端解析不同,影响翻译判定与冲突展示;③ 327 行 HTML 抓取器仅 1 个测试(`SkillsDirectoryServiceTests.swift` 全文 22 行,已核实),站点改版线上静默解析为空;顺带拆分 1204 行的 EnvironmentAndNetworkingTests 大杂烩。

**涉及文件**:`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Services/SkillParser.swift`、`Tests/SkillsManagerTests/SkillsDirectoryServiceTests.swift`

**验收标准**:
- scanGeneration 递增校验,旧代结果丢弃;引入 Yams(或至少支持 folded scalar),与 gray-matter 行为对齐并有对拍样本;
- 真实首页/详情页 HTML fixture 测试,改版时红灯。

### P2-6 TUI 包卫生:Ink 僵尸代码与依赖清除、dist 出库(工作量:小)

**为什么**:README 自认 Ink 实现仅是 "historical backup",但 `tui/src/app.tsx`(383 行)、`components/` 11 个 .tsx、`index-ink.tsx`、`test-ink-render.tsx` 仍被 tsconfig include 编进 dist;ink/react/@inkjs/ui 在 dependencies,每个 npm link 用户都在为死代码安装 React;`tui/dist/*.js` 全部提交进 git(含无对应源文件的产物);列表顺序随 readdir 漂移。

**涉及文件**:`tui/src/app.tsx`、`tui/src/index-ink.tsx`、`tui/src/components/`、`tui/test-ink-render.tsx`、`tui/package.json`、`tui/.gitignore`、`tui/src/app-blessed.ts`

**验收标准**:
- 删除全部 Ink 源与 start:ink 脚本,ink/react/@inkjs/ui/@types/react 移出依赖;
- .gitignore 加 dist/ 并从索引移除,package.json files:["dist"];
- filteredSkills 按 displayName localeCompare 排序;构建与启动正常。

### P2-7 跨进程共享文件写入协议(工作量:小)

**为什么**:star 文件两进程并发 toggle 时 last-writer-wins 丢数据,TUI 侧 writeFileSync 非原子(`tui/src/services/SkillStore.ts:82-90`),Swift 读到半写 JSON 时返回空集当作无 star 应用;翻译缓存 Swift 侧首次加载后永不从磁盘刷新,persist 整文件覆盖会抹掉另一进程写入的条目(`SkillStore.swift:1720-1748`)。

**涉及文件**:`SkillsManager/Services/SharedStarredState.swift`、`tui/src/services/SkillStore.ts`、`SkillsManager/Services/SkillStore.swift`

**验收标准**:
- 两端均为"重读磁盘→合并→写临时文件→rename";翻译缓存 persist 前按 mtime 判断过期并 reload-merge;
- SharedStarredStateTests 补并发合并用例。

### P2-8 术语迁移 AgentDefinition→AgentPlatform + 领域文档收录四层术语(工作量:小,依赖 P1-1 后做)

**为什么**:2026-07-12 已敲定、两个方向下都成立的决策(collections 语境里它同样是"平台描述符"),双侧均未执行:`AgentRegistry.swift:3` 仍为 struct AgentDefinition,`tui/src/types.ts:41` 同名 interface;`docs/ui-domain-knowledge.md` §2 未收录 Library/Collection/Mount 与 Platform/Resource/Deployment 的映射,两代方向的领域语言断代。

**涉及文件**:`SkillsManager/Adapters/AgentRegistry.swift`、`tui/src/types.ts`、`docs/ui-domain-knowledge.md`

**验收标准**:机械改名 + 引用点批量更新,构建/测试全绿;领域文档补术语映射表。

### P2-9 【条件项,取决于 P0-1 裁决】以嵌入式形态重启检视器(工作量:大)

**为什么**:复盘判"伪需求"的实际教训更可能是"独立 TOOLS 树视图离用户任务太远"而非"透明性无价值"——冲突、状态灯、provenance 全被留下且继续加码(f09a4cf)。重启形态:collection detail 的 agent 胶囊点开时内嵌"该 agent 此刻实际生效的 skills + 来源 + 遮蔽"面板,数据全部来自现有扫描,零 spec 依赖;原 InspectorView 446 行渲染可从 commit f1fe114 取材。检视器从"先行的独立交付物"降级为"挂载工作流的解释层",与 collections 互补而非竞争。

**涉及文件**:`SkillsManager/Views/CollectionDetailView.swift`、`SkillsManager/Views/AgentHomeView.swift`、`SkillsManager/Views/ContentView.swift`

**验收标准**:P0-1 裁决为"回摆"或"部分恢复"后才启动;基于 P1-5 的 ShadowingDetection;不新建独立侧栏入口。

### P2-10 Discover/Try 细节打磨(工作量:小)

**为什么**:① 详情加载失败被静默吞掉(`SkillStore.swift:557-559` catch 空),"Loading detail content…" 永久停留无重试;② Try 按钮先 await 网络再弹 sheet,期间无 spinner 不禁用,慢网可连点;③ DiscoverInstallToAgentView 点 Install 后 sheet 保持打开无 ProgressView(活动面板被遮挡),且预选 claude-code 而同构的 InstallToAgentView 不预选;④ ⌘S 绑定 Star 偏离平台"保存"惯例。

**涉及文件**:`SkillsManager/Views/DiscoverView.swift`、`SkillsManager/Views/DiscoverInstallToAgentView.swift`、`SkillsManager/Views/InstallToAgentView.swift`、`SkillsManager/Services/SkillStore.swift`、`SkillsManager/Views/SkillCommands.swift`

**验收标准**:失败态区分于加载态并可重试;Try 有加载反馈;安装 sheet 点击后立即 dismiss 交给活动面板;两个安装 sheet 预选逻辑统一;Star 快捷键改非 ⌘S。

### P2-11 Settings baseURL 数据流向说明(工作量:小)

**为什么**:API key 随请求发往用户可配置的任意 baseURL(`LLMService.swift:254-278`),TextField 无校验无提示(`SettingsView.swift:144`),被诱导填入代理 URL 即泄露 key。

**涉及文件**:`SkillsManager/Views/SettingsView.swift`

**验收标准**:字段下加 caption "API key 将随每次请求发送到此地址";scheme 非 https 且 host 非 loopback 时显示橙色警告。

---

## 附:依赖关系速览

- P1-3(更新检查)依赖 P1-2(commit/hash 记录);P2-2(git 历史)依赖 P0-3/P1-2;
- P2-8(改名)排在 P1-1(ID 单源)之后,避免两次触碰同一批引用;
- P2-9(检视器重启)以 P0-1(方向裁决)为闸门,以 P1-5(遮蔽检测)为地基;
- TUI 条目(P0-8/P0-9/P1-13)是冻结前的最后维护窗口,之后新能力一律走 P2-1 的内核+CLI 路线。

