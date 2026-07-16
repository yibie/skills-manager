import Foundation
import SkillsKernel

// MARK: - 检视器展示模型(M3)
// EffectiveAgentReport(SkillsKernel 数据契约)→ 视图可直接消费的展示结构。
// 纯值转换,不依赖 AppKit/SwiftUI,便于单元测试。

/// 一个资源实例的展示行。
struct InspectorInstanceRow: Identifiable, Hashable, Sendable {
    let id: String
    /// 展示名:key 优先(skill 目录名 / agent 名 / 文件名),missing 时退回期望路径的文件名
    let name: String
    /// 来源文件绝对路径(missing 时为 spec 期望路径)
    let path: String
    /// 产生该实例的 spec 规则 id
    let ruleId: String
    let scope: ResourceScope
    let status: InstanceStatus
    /// spec 声明为必需
    let required: Bool
    /// confidence: low —— 该条规则本身可能说谎,UI 须显式标注
    let lowConfidence: Bool
    /// 仅 shadowed:遮蔽方(winner)路径
    let shadowedByPath: String?
    /// 仅 runtime-config:浅计数文案,如 "2 servers"
    let countText: String?

    init(instance: ResourceInstance) {
        self.id = instance.ruleId + "|" + instance.path + "|" + instance.status.rawValue
        self.name = instance.key
            ?? instance.path.split(separator: "/").last.map(String.init)
            ?? instance.path
        self.path = instance.path
        self.ruleId = instance.ruleId
        self.scope = instance.scope
        self.status = instance.status
        self.required = instance.required
        self.lowConfidence = instance.confidence == .low
        self.shadowedByPath = instance.shadowedBy?.winnerPath
        self.countText = instance.count.map { "\($0.value) \($0.unit)" }
    }
}

/// spec 未建模的可疑条目展示行。
struct InspectorUnmodeledRow: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let scope: ResourceScope

    init(item: UnmodeledItem) {
        self.id = item.path
        self.path = item.path
        self.scope = item.scope
    }
}

/// 按资源类型分组的一节。
struct InspectorResourceSection: Identifiable, Sendable {
    let id: String
    /// 组名沿用 goal 文档的四个资源类型称谓
    let title: String
    let rows: [InspectorInstanceRow]
}

/// 顶部 summary 统计。
struct InspectorSummary: Equatable, Sendable {
    let resources: Int
    let active: Int
    let shadowed: Int
    let missing: Int
    let unmodeled: Int
}

/// 一次扫描的完整展示模型。
struct InspectorPresentation: Sendable {
    let platformName: String
    let projectPath: String
    let generatedAt: String
    /// spec 最后校验日期(越久远越可能说谎,summary 区展示)
    let specLastVerified: String
    let summary: InspectorSummary
    /// 恒定四节(Identity / Guidance / Skills / Runtime),空节保留,呈现"这一层没有东西"本身也是信息
    let sections: [InspectorResourceSection]
    let unmodeled: [InspectorUnmodeledRow]

    init(report: EffectiveAgentReport) {
        self.platformName = report.platform.name
        self.projectPath = report.project.path
        self.generatedAt = report.generatedAt
        self.specLastVerified = report.spec.lastVerified
        self.summary = InspectorSummary(
            resources: report.summary.resources,
            active: report.summary.active,
            shadowed: report.summary.shadowed,
            missing: report.summary.missing,
            unmodeled: report.summary.unmodeled
        )
        self.sections = [
            InspectorResourceSection(
                id: "identity",
                title: "Identity",
                rows: report.resources.identity.map(InspectorInstanceRow.init)
            ),
            InspectorResourceSection(
                id: "guidance",
                title: "Guidance",
                rows: report.resources.guidance.map(InspectorInstanceRow.init)
            ),
            InspectorResourceSection(
                id: "skill",
                title: "Skills",
                rows: report.resources.skill.map(InspectorInstanceRow.init)
            ),
            InspectorResourceSection(
                id: "runtime-config",
                title: "Runtime",
                rows: report.resources.runtimeConfig.map(InspectorInstanceRow.init)
            ),
        ]
        self.unmodeled = report.unmodeled.map(InspectorUnmodeledRow.init)
    }

    /// 按行 id 查找实例(detail 栏与右键菜单用)。
    func row(withID id: InspectorInstanceRow.ID?) -> InspectorInstanceRow? {
        guard let id else { return nil }
        return sections.lazy.flatMap(\.rows).first { $0.id == id }
    }
}

// MARK: - 展示辅助(scope / status 文案)

extension ResourceScope {
    /// scope 徽标文字(保留英文术语,与 spec/schema 一致)。
    var inspectorBadgeText: String { rawValue }
}

extension InstanceStatus {
    /// 状态的中文说明(detail 栏用)。
    var inspectorDescription: String {
        switch self {
        case .active:   "生效中 — Agent 会实际加载该资源"
        case .shadowed: "被遮蔽 — 同名的更高优先级实例生效,此实例不加载"
        case .missing:  "缺失 — spec 声明了该路径,但文件系统中不存在"
        }
    }
}
