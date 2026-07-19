import AppKit
import SwiftUI
import Testing
import SkillsKernel
@testable import SkillsManager

/// Offscreen visual-acceptance harness for the agent home page: renders
/// AgentHomeView with and without a matching adapter spec to /tmp for eyeballing:
///   swift test --filter AgentHomeSnapshot
/// Unlike InspectorSnapshotTests, the hosting view is placed in a real (parked
/// offscreen) NSWindow and the run loop is pumped before caching — AgentHomeView
/// embeds a full SkillListView and its buttons/card borders otherwise render
/// incompletely (missing buttons, ghost duplicates).
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

    @MainActor
    private func agentHome(agentName: String, specEntry: SpecCatalogEntry?, conflicts: [SkillConflict]) -> AgentHomeView {
        AgentHomeView(
            agentName: agentName,
            skills: Skill.mockSkills,
            conflicts: conflicts,
            specEntry: specEntry,
            selectedSkill: .constant(nil),
            onInstall: { _ in },
            onUninstall: { _ in },
            onToggleStar: { _ in },
            onOpenInspector: {},
            onShowConflicts: {}
        )
    }

    @Test @MainActor
    func agentHomeWithSpec() throws {
        let conflict = SkillConflict(
            name: "commit",
            instances: [
                SkillConflictInstance(path: "/a/commit", agents: ["Claude Code"], contentHash: "aaaa"),
                SkillConflictInstance(path: "/b/commit", agents: ["Cursor"], contentHash: "bbbb"),
            ]
        )
        let spec = SpecCatalogEntry(
            url: URL(fileURLWithPath: "/specs/claude-code.yaml"),
            platformID: "claude-code",
            platformName: "Claude Code",
            loadError: nil
        )
        let png = try renderPNG(
            agentHome(agentName: "Claude Code", specEntry: spec, conflicts: [conflict]),
            size: NSSize(width: 560, height: 800)
        )
        try png.write(to: URL(fileURLWithPath: "/tmp/agent-home-with-spec.png"))
    }

    @Test @MainActor
    func agentHomeWithoutSpec() throws {
        let png = try renderPNG(
            agentHome(agentName: "Cursor", specEntry: nil, conflicts: []),
            size: NSSize(width: 560, height: 800)
        )
        try png.write(to: URL(fileURLWithPath: "/tmp/agent-home-without-spec.png"))
    }
}
