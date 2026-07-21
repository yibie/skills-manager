import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// Offscreen visual-acceptance harness for the agent home page: renders
/// AgentHomeView (header card + optional conflict card + skill list) to /tmp
/// for eyeballing:
///   swift test --filter AgentHomeSnapshot
/// The hosting view is placed in a real (parked offscreen) NSWindow and the run
/// loop is pumped before caching — AgentHomeView embeds a full SkillListView
/// and its buttons/card borders otherwise render incompletely.
struct AgentHomeSnapshotTests {
    @MainActor
    private func renderPNG<V: View>(_ view: V, size: NSSize) throws -> Data {
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
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test @MainActor
    func agentHomeWithConflict() throws {
        let conflict = SkillConflict(
            name: "commit",
            instances: [
                SkillConflictInstance(path: "/a/commit", agents: ["Claude Code"], contentHash: "aaaa"),
                SkillConflictInstance(path: "/b/commit", agents: ["Cursor"], contentHash: "bbbb"),
            ]
        )
        let png = try renderPNG(AgentHomeView(
            agentName: "Claude Code",
            skills: Skill.mockSkills,
            conflicts: [conflict],
            selectedSkill: .constant(nil),
            onInstall: { _ in },
            onUninstall: { _ in },
            onToggleStar: { _ in },
            onShowConflicts: {}
        ), size: NSSize(width: 560, height: 800))
        try png.write(to: URL(fileURLWithPath: "/tmp/agent-home.png"))
    }
}
