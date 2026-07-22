import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// 临时对齐扫描:渲染各关键视图的真实状态到 /tmp 供人工比对草图。
///   swift test --filter AlignmentSweep
struct AlignmentSweepTests {
    @MainActor
    private func renderPNG<V: View>(_ view: V, size: NSSize, to path: String) throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func sampleAgents() -> [AgentDefinition] {
        [
            AgentDefinition(id: "claude-code", displayName: "Claude Code", icon: "cpu",
                            globalSkillsDir: URL(fileURLWithPath: "/tmp/x"), detectPath: ".claude"),
            AgentDefinition(id: "codex", displayName: "Codex", icon: "cpu",
                            globalSkillsDir: URL(fileURLWithPath: "/tmp/y"), detectPath: ".codex"),
            AgentDefinition(id: "cursor", displayName: "Cursor", icon: "cpu",
                            globalSkillsDir: URL(fileURLWithPath: "/tmp/z"), detectPath: ".cursor"),
        ]
    }

    @MainActor
    private func collections() -> [CollectionRecord] {
        [
            CollectionRecord(name: "iOS 开发", sortOrder: 0,
                             memberSkillIDs: Skill.mockSkills.map(\.id),
                             mountedAgentIDs: ["claude-code"]),
            CollectionRecord(name: "写作", sortOrder: 1,
                             memberSkillIDs: Array(Skill.mockSkills.map(\.id).prefix(2)),
                             mountedAgentIDs: ["claude-code", "codex"]),
            CollectionRecord(name: "Git 工作流", sortOrder: 2, memberSkillIDs: [], mountedAgentIDs: []),
        ]
    }

    /// 控制台:挂载中 + 不一致 + 未挂载 三种卡片状态
    @Test @MainActor
    func consoleAllStates() throws {
        let statuses: [String: MountStatus] = ["claude-code": .mounted, "codex": .diverged]
        try renderPNG(ControlCenterView(
            collections: collections(),
            skills: Skill.mockSkills,
            detectedAgents: sampleAgents(),
            statusFor: { _, agentID in statuses[agentID] ?? .unmounted },
            onOpen: { _ in }, onCreate: { _ in }, onToggleAgent: { _, _, _ in },
            onReapply: { _, _ in }, onRename: { _, _ in }, onDelete: { _ in }
        ), size: NSSize(width: 980, height: 700), to: "/tmp/sweep-console.png")
    }

    /// 组详情:带三个 agent 胶囊
    @Test @MainActor
    func collectionDetailWithAgents() throws {
        let statuses: [String: MountStatus] = ["claude-code": .mounted]
        try renderPNG(CollectionDetailView(
            collection: collections()[0],
            skills: Skill.mockSkills,
            detectedAgents: sampleAgents(),
            statusFor: { statuses[$0] ?? .unmounted },
            selectedSkill: .constant(nil),
            onToggleAgent: { _, _ in }, onReapply: { _ in },
            onAddMembers: { _ in }, onRemoveMember: { _ in },
            onInstall: { _ in }, onUninstall: { _ in }, onToggleStar: { _ in }
        ), size: NSSize(width: 640, height: 700), to: "/tmp/sweep-detail.png")
    }

    /// 窄宽度下的组详情(已知有 overlap 报告)
    @Test @MainActor
    func collectionDetailNarrow() throws {
        let statuses: [String: MountStatus] = ["claude-code": .mounted]
        try renderPNG(CollectionDetailView(
            collection: collections()[0],
            skills: Skill.mockSkills,
            detectedAgents: sampleAgents(),
            statusFor: { statuses[$0] ?? .unmounted },
            selectedSkill: .constant(nil),
            onToggleAgent: { _, _ in }, onReapply: { _ in },
            onAddMembers: { _ in }, onRemoveMember: { _ in },
            onInstall: { _ in }, onUninstall: { _ in }, onToggleStar: { _ in }
        ), size: NSSize(width: 460, height: 700), to: "/tmp/sweep-detail-narrow.png")
    }

    /// 库页技能列表(对照信息密度)
    @Test @MainActor
    func libraryList() throws {
        try renderPNG(SkillListView(
            skills: Skill.mockSkills,
            filter: .all,
            selectedSkill: .constant(nil),
            onInstall: { _ in }, onUninstall: { _ in }, onToggleStar: { _ in }
        ), size: NSSize(width: 520, height: 700), to: "/tmp/sweep-library.png")
    }
}
