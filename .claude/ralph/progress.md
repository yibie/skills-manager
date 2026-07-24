# Ralph Loop — 产品评估与自动改进

- 启动:2026-07-26,/loop 动态模式(自调度)
- 任务:组织团队评估 Skills Manager 产品,形成改进清单(backlog.md),后续迭代逐项自动实施
- Git 注意:启动时处于 detached HEAD @ 243ee0c;自动改进只改工作区、**不自动 commit**(用户未要求提交;如需提交建议先建分支)

## 约定

- `backlog.md`:排序后的改进清单(P0/P1/P2),每项含验收标准;实施后在本文件记录
- 每轮迭代:领取 backlog 顶部一个可自动完成的条目 → 实施 → 验证(构建/测试)→ 记录
- 循环结束条件:backlog 中可自动实施的条目做完,或用户叫停

## 迭代日志

### 迭代 1 — 2026-07-26(完成)

- product-eval-team workflow:7 agents / 约 93 万 tokens / 311 次工具调用,6 维度全部返回
- **重大发现**:记忆中的 Effective-Agent Inspector 方向已于 2026-07-21 书面废止(docs/goals/effective-agent-inspector.md 头部 CANCELLED),现行方向 = collections + 挂载的 lifecycle control plane;用户 memory 已修正
- 产出:`backlog.md`(401 行,P0/P1/P2)+ 3 个自动实施首选项
- 总体结论:工程底子扎实(symlink 原子安装、provenance 分级、意图/磁盘分离);三类系统性风险 = 方向震荡两套记录矛盾、更新/删除/挂载链路信任缺口、TUI 冻结分叉

### 迭代 2 — 2026-07-26(进行中)

- 领取 top_pick #1 = P0-4 promoteSkill 路径消毒:SkillStore.promoteSkill 把未消毒的第三方 frontmatter displayName 直接拼进 ~/.claude/skills/ 路径(全库唯一遗漏 sanitize 的写路径口子)
- 已实施:抽出 `nonisolated static promotedDirectoryName(displayName:directoryName:)` 套用 SymlinkInstaller.sanitize(SkillStore.swift);新增 Tests/SkillsManagerTests/SkillPromotionTests.swift(4 例:穿越剥离/无分隔符/空名回退/退化名);`xcodegen generate` 已重跑(xcscheme 工作区改动核实为 xcodegen 产物,无手工编辑被覆盖)
- ⚠️ 教训:第一次 xcodebuild test 的 grep 过滤只留了 XCTest 行,swift-testing(本仓库全部测试)的结果被滤掉,日志显示 "Executed 0 tests" ——绿灯是假信号。之后验证一律:完整日志落盘 + 提取 "Test run with N tests" 行
- P0-6 空分组挂载黄灯陷阱已同轮实施:ActivationService.status 对 memberCount==0 恒返 .unmounted(原:intentMounted 时 .diverged 永久黄灯);ActivationServiceTests.swift:44 断言同步翻转;ControlCenterView/CollectionDetailView 空组时"挂载到…"菜单替换为"先添加技能再挂载"提示(详情页空态本就有"添加技能"主操作,卡片整卡点击进详情,故不加新回调)
- ✅ 验证通过:107 tests / 17 suites 全绿(4.1s),SkillPromotionTests 4 例 + 翻转后的 statusMatrix 均过 → **P0-4、P0-6 完成**

### 迭代 3 — 2026-07-26(进行中)

- 领取 top_pick #3 = P0-2 Discover 同名误判/误删改 provenance 精确匹配(DiscoverView.swift:147、SkillStore.swift:602-605;防止误删用户同名本地技能)
- 已实施:新增 `Models/DiscoverLibraryMatch.swift`(纯匹配器:installed/sameNameOnly/none;provenance.skillID + 仓库 slug 归一比较,容忍 .git 后缀与大小写);三处调用点改造 —— 列表行徽章(DiscoverView:147)、详情 isInstalled(ContentView:366)、removeDiscoverSkillFromLibrary(SkillStore:602,只按 provenance 删);仅同名时显示中性 "Same name in library" 徽章且无 Remove 按钮;新增 DiscoverLibraryMatchTests 5 例
- 备注:验收标准第 1 条"无 provenance 才回退名字匹配"与该 bug 的核心场景(手写同名技能无 provenance 却被误判)自相矛盾,按安全优先解释:Installed 仅认 provenance 精确对应,同名一律中性徽章。已在此留痕
- ✅ 验证通过:112 tests / 18 suites 全绿(4.2s),DiscoverLibraryMatchTests 5 例全过 → **P0-2 完成**
- 至此 top_picks 三项(P0-4、P0-6、P0-2)全部完成

### 迭代 4 — 2026-07-26(进行中)

- 领取 P0-3 更新静默销毁本地修改(评估认定的"唯一会静默毁数据的路径")
- 已实施:
  - SymlinkInstaller:替换成功后备份不再 removeItem,改移入 canonical 旁的 `.skills-manager-history/<name>-<时间戳>-<uuid8>`(`historyDirectory` 可测;移动失败则备份以隐藏名留在原地,绝不删除);失败回滚路径不变
  - ManagedSkillManifest 新增 `contentHash`(SHA-256 全量,`SkillContentHasher`);两处 manifest 写入点(SkillLifecycleService.install、NativeSkillPackageInstaller.install)安装后对 canonical SKILL.md 计算指纹
  - `SkillLifecycleService.hasLocalDrift(_:)`:重算 hash 与 manifest 比对;旧 manifest 无 hash 或读不到内容 → 无漂移(没有证据不阻断)
  - SkillStore.updateSkill 增加漂移门禁 → `pendingUpdateOverwrite`;ContentView 新增确认弹窗("仍要更新" destructive / 取消),文案写明旧副本保留位置
  - 新增 UpdateSafetyTests 4 例:替换保留旧副本进 history、全新安装不留 history、漂移检测红绿、legacy manifest 不阻断
- ✅ 验证通过:116 tests / 19 suites 全绿,UpdateSafetyTests 4 例全过、SymlinkInstaller 回滚测试保持绿 → **P0-3 完成**

### 迭代 5 — 2026-07-26(进行中)

- 领取 P0-5 删除分组无确认且不清理已挂载 symlink(遗留 UI 不可见的无主链接)
- 已实施:CollectionCard "删除分组…" 改弹 confirmationDialog —— 已挂载时列出 agent 名单,提供"卸载链接并删除分组"(destructive,先对每个 mountedAgentID 走 setMounted(mount:false) 即 ActivationService.unmount)与"仅删除分组(保留磁盘链接)"两个选项;未挂载时单一确认;文案写明"技能本体始终保留在 Library"(domain doc 要求);ContentView.onDelete 增加 unmountFirst 参数,迭代 mountedAgentIDs 快照避免边遍历边删
- 首跑失败(exit 65):ConsoleSnapshotTests/AlignmentSweepTests 两处旧签名闭包,补 `{ _, _ in }` 后重跑
- ✅ 验证通过:116 tests / 19 suites 全绿 → **P0-5 完成**(弹窗交互留待手工验证)

### 迭代 6 — 2026-07-26(进行中)

- 领取 P0-8(TUI Discover 列表 off-by-one)+ P0-9(TUI 文件安全),同轮实施
- P0-8 已实施:删除列表内表头两行(面板 label 已承载同样信息);移除全部 ±1 偏移与 discover 特殊分支(select 回调 -1、updateList 特殊分支+536、j/k 1326/1345、g 1362、G 1374)——高亮行 = 详情 = i/x 操作对象
- P0-9 已实施:InstallService.ts 重写 —— rmSync 全部移除:实体一律 moveToTrash(darwin ~/.Trash,失败退 ~/.skills-manager/trash,跨卷兜底);受管挂载守卫(lstat+readlink 解析,目标在 ~/.config/agents/skills 或 ~/.agents/skills 下即拒绝并提示去 App 内 Unmount);普通 symlink 只 unlink 链接本身;copyRecursive 改 lstat + 复制链接本身不跟随 + 深度上限 32;x 键(库/Discover 两路径)前置 confirmDestructive overlay(默认焦点 Cancel,y 确认,n/Esc 取消,grabKeys 隔离全局键);uninstallDiscoverSkill 委托 uninstall,守卫自动覆盖
- ✅ 验证:`npm run build`(tsc)零错误 → **P0-8、P0-9 完成**(TUI 交互留待手工验证)
- 队列:P0-7(挂载汇报 UI)+ P0-1 文档 truthing → 之后转 P1(优先 P1-12 卸载残留摘意图、P1-8 安全路径测试补齐)

### 迭代 7 — 2026-07-26(进行中)

- 领取 P0-7(挂载"部分成功"误报 Error 弹窗)+ P0-1 文档 truthing 部分
- P0-1 文档部分已实施:effective-agent-schema.md 头部补 CANCELLED 横幅(与 inspector.md 同款,注明生产者已移除);schema.json 加 `$comment` + `deprecated: true`。剩余的方向裁决本体与 994M worktree 清理需用户决策
- P0-7 已实施:SkillStore 新增 `mountReports`(key 同 mountStatuses)+ mountReport/recordMountReport;setMounted 两处不再把 report.summaryText 塞 errorMessage(errorMessage 只留给目录创建失败等真错误);ControlCenterView 挂载行与 CollectionDetailView agent 胶囊就近显示"成功 N · 跳过 M"(statusWarn 色,hover 展开逐技能原因);新 props 均带默认值,快照测试调用点无需改动
- ✅ 验证通过:116 tests / 19 suites 全绿 → **P0-7、P0-1(文档部分)完成;P0 可自动化项全部收官**
- 注意:迭代 6 后 shell cwd 停在 tui/ 导致一次相对路径误判("schema 文件不存在"),已核实文件在;后续 Bash 一律绝对路径或先 cd 回仓库根
- 待用户决策:① 方向裁决本体(废止决策记录 or 回摆);② .claude/worktrees/ 994M 旧检视器工作树删留

### 迭代 8 — 2026-07-26(进行中)

- 领取 P1-12(卸载残留不摘除挂载意图,极小)+ P1-8(安全关键路径测试补齐,小)
- P1-12 已实施:setMounted 卸载分支仅当 report.skipped 为空才移除 agentID;有残留时保留意图 → 状态灯持续黄灯 + "重新应用",配合 P0-7 就近报告
- P1-8 已实施:发现包外 symlink 逃逸测试其实已存在(评估员"零引用"论断过重,已核实);补齐缺口 —— 包内相对链接放行测试 + sanitize 边界断言(../evil、a/b、空名、300 字符截断)。takeOverSkillsCLIInstallation 失败回滚测试暂缓(需先摸清 takeOver 内部注入点,避免为凑验收造脆弱 fixture),留待后续轮次
- ✅ 验证通过:118 tests / 19 suites 全绿 → **P1-12、P1-8(核心部分)完成**

### 迭代 9 — 2026-07-26(进行中)

- 领取 P1-7(供应链与 provenance 收口)+ P1-13(TUI 信任级小修集)
- P1-7 已实施:① `SkillLifecycleService.skillsCLIVersion = "1.5.20"`(npm view 查得现行版),Swift 三处 + TUI 一处 npx 统一 `skills@1.5.20`;② ensureCanonical 迁移分支 move 后剥离包内自带 manifest(与 SymlinkInstaller:135 对齐);③ annotate() 经 trustedProvenance 校验 manifest sourceURL.host == github.com,不合规降级 .manual(无更新通道);新增 3 测试:伪造 manifest 失去更新通道、github manifest 保留、迁移剥离 manifest
- P1-13 已实施:① render() 加 grabKeys 守卫 + 状态定时器只调 updateStatusBar(消灭 overlay 期间软死锁);② agent 弹窗首帧勾选与 selectedAgents 一致(只勾 claude-code);③ 卸载提示改 "Removed Claude Code copy"(如实);④ 成功消息 green-fg / 错误 red-fg;⑤ 安装单次 npx 传多 --agent(不再逐个串行)
- 首跑 1 例失败:EnvironmentAndNetworkingTests:931 断言 npx 命令原文,pin 后不匹配;断言改引用 skillsCLIVersion 常量后重跑
- ✅ 验证通过:121 tests / 19 suites 全绿 + tsc 零错误 → **P1-7、P1-13 完成**

## 循环收束 — 2026-07-26

**9 轮迭代:1 轮六维评估 + 8 轮改进,14 项完成并验证。测试 99 → 121 全绿,tsc 零错误。**

已完成:P0-2/3/4/5/6/7/8/9、P0-1(文档部分)、P1-7/8(核心)/12/13。信任与数据安全类条目 100% 清完。

停止理由:剩余 backlog 项(P1-1~6 中等重构、P1-9/10/11 UI 视觉向、P1-14 产品取舍、P2 大项)均需用户决策或手工视觉验证,超出安全自动完成边界。用户说"继续"即可重启循环(建议先 review 并提交当前改动)。

**待用户事项**:
1. 全部改动未提交(启动时即 detached HEAD @ 243ee0c)——review 后可让我建分支提交
2. 手工验证清单:删除分组确认框、更新漂移确认框、挂载"成功N·跳过M"徽标、空分组挂载提示、TUI(高亮对齐/x 确认框/绿色成功消息/弹窗勾选)
3. 方向裁决:为"废止检视器"补含用户证据的决策记录,或回摆(backlog P0-1)
4. .claude/worktrees/ 994M 旧检视器工作树删留(破坏性,未自动执行)
5. 继续改进:P1-14(移除死 Trial 状态机,已有综合裁决"删")→ P1-9/10/11(UI 小项)→ P1-1~6
- 队列第三项:top_pick #3 = P0-2 Discover 同名误判/误删改 provenance 精确匹配(DiscoverView.swift:147、SkillStore.swift:602-605)
