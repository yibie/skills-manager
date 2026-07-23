# UI 领域知识指引

本指引定义 Skills Manager 界面判断所依据的领域知识。它回答“什么是正确的”，
具体如何验证见 [`ui-interaction-review.md`](ui-interaction-review.md)。

## 1. 判断优先级

发生冲突时，按以下顺序决定：

1. 数据安全与无障碍硬约束
2. Skills Manager 的业务语义
3. macOS 平台约定
4. 通用人机交互原则
5. 视觉参考与个人审美

低优先级规则不能推翻高优先级约束。启发式原则用于发现问题，不是机械套用的法律。

## 2. Skills Manager 业务语义

产品的核心关系是 `Library → Collection → Mount`。以现有
[`Collections Control Center` 设计规格](superpowers/specs/2026-07-21-collections-control-center-design.md)
为事实来源，不在本文件复制存储结构或实现细节。

- **Library** 是技能的持久归属。Collection 和 Agent 都不拥有技能实体。
- **Collection** 组织技能，并表达批量装载意图；空 Collection 没有可装载内容。
- **Agent** 是技能的运行目标。挂载表示把技能的 symlink 放进 Agent 的技能目录。
- **意图不等于事实**：`mountedAgentIDs` 保存用户意图，磁盘上的 symlink 才是实际状态。
- **卸载不等于删除**：卸载只移除链接，技能必须保留在 Library 中。
- **状态偏差必须显式处理**：意图与磁盘不一致时，显示差异并提供“按意图重新应用”；
  未经用户操作不得静默改磁盘。
- **冲突不能伪装成成功**：跳过、失败和来源冲突必须在相关对象附近报告，并提供下一步。

这些语义直接约束界面：

- 空 Collection 的主操作是“添加技能”，不是“挂载”。
- 没有成员时，依赖成员的操作应隐藏或禁用，并说明原因。
- Agent 控件必须区分计划挂载、实际挂载、等待应用和失败，不能只显示一个真假开关。
- “卸载”“从 Collection 移除”和“从 Library 删除”必须使用不同文案与风险等级。
- 删除确认必须准确说明会保留什么、移除什么；不能用含糊的通用警告。

### 生命周期归属与来源

Skills Manager 是技能的生命周期控制面；发现来源、安装来源和当前管理者是三个不同概念：

- `skills.sh` 只负责发现，不决定安装机制。App 内的新安装由 Skills Manager 原生写入 Library。
- **来源（source）**说明内容来自哪个仓库；**管理者（provider）**说明更新和删除应交给谁。
- 扫描到外部安装时，只有可验证的 provider 元数据才能改变管理者；同名不是充分证据。
- provider 可用时，更新和删除交还原工具；不可用时，Skills Manager 可接管，但必须保留可恢复副本，
  清理陈旧元数据，并明确反馈接管结果。
- Collection 的 Unmount 只改变 Agent 链接；Delete from Library 才删除 Library 实体。
- 外部目录默认只读。没有可信 provider 删除能力时只能使用 macOS Trash，不能永久删除。

界面必须在对象附近显示当前管理者，并让更新、Unmount、从 Library 删除使用不同动作和确认文案。

## 3. macOS 平台约定

以 Apple Human Interface Guidelines 为平台事实来源：

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)：
  支持窗口缩放、键盘操作和符合桌面习惯的命令组织。
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) 与
  [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)：定义合理最小尺寸，
  在窄、中、宽窗口中保持主任务成立，避免无价值空白占用窗口。
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)：侧栏应可隐藏，
  空间不足时优先使用紧凑形式，层级保持克制。
- [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)：第二栏选择驱动详情；
  只有对象确有进一步内容时才保留第三栏，隐藏后必须可恢复。
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)：工具栏用于标题、导航、
  搜索和高频重要动作；长统计、诊断信息和低频操作不应主导工具栏。
- [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)：核心任务应支持
  Full Keyboard Access、合理焦点顺序和平台标准快捷键。

使用系统原生组件和行为优先于自定义模拟。若偏离平台约定，评审记录必须说明用户收益。

## 4. 可用性判断方法

使用 [Nielsen 十项可用性原则](https://www.nngroup.com/articles/ten-usability-heuristics/)
检查系统状态、用户语言、控制与退出、错误预防、一致性、识别负担、效率、信息克制、
错误恢复和帮助。

对每个核心任务执行一次
[Cognitive Walkthrough](https://www.colorado.edu/ics/sites/default/files/attached-files/93-07.pdf)：

1. 用户此刻会形成正确目标吗？
2. 用户能注意到正确动作吗？
3. 用户能把这个动作与目标联系起来吗？
4. 操作后，用户能看见自己正朝目标前进吗？

任一答案为“不能”时，先修复任务、结构、文案或反馈，不用装饰性视觉效果补偿。

## 5. 无障碍与人体工学

以 [Apple Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
为 macOS 实现基线，并用 [WCAG 2.2](https://www.w3.org/TR/WCAG22/) 补充检查原则：

- 核心流程可仅用键盘完成，焦点可见且顺序符合任务。
- 图标按钮、状态和自定义控件具有可读标签与角色。
- 不只依赖颜色表达挂载、偏差、冲突或失败。
- 操作目标大小和间距足以避免误触；macOS 尺寸遵循 Apple 指南，不照搬 Web 像素值。
- 状态变化能被辅助技术感知，并在发生动作的位置给出反馈。
- 缩放、窄窗口和较长本地化文本下，信息与主操作仍可用。
- 动效不是理解状态的唯一方式，并尊重“减少动态效果”设置。

无障碍缺陷是完成阻断项，不能作为后续美化工作延期。

## 6. 每次评审如何使用

开始前只需完成四件事：

1. 写出用户任务及涉及的业务对象。
2. 标明每个可变状态是用户意图、磁盘事实，还是两者的差异。
3. 找到对应的 macOS 平台模式，并记录必要的偏离。
4. 用 Cognitive Walkthrough 和无障碍检查验证核心流程，再进入视觉判定。

不要复制整套外部规范到仓库。本文只保存稳定的项目化结论；具体细节链接到原始来源。
