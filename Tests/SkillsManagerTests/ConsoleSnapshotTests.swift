import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// Offscreen visual-acceptance for the control center and collection detail
/// (same parked-NSWindow harness as AgentHomeSnapshotTests). PNGs land in /tmp:
///   swift test --filter ConsoleSnapshot
struct ConsoleSnapshotTests {
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
    private func sampleCollections() -> [CollectionRecord] {
        [
            CollectionRecord(
                name: "iOS 开发",
                sortOrder: 0,
                memberSkillIDs: Skill.mockSkills.map(\.id),
                mountedAgentIDs: ["claude-code"]
            ),
            CollectionRecord(name: "写作", sortOrder: 1, memberSkillIDs: [], mountedAgentIDs: []),
        ]
    }

    @Test @MainActor
    func controlCenterWall() throws {
        let png = try renderPNG(ControlCenterView(
            collections: sampleCollections(),
            skills: Skill.mockSkills,
            detectedAgents: [],
            statusFor: { _, _ in .mounted },
            onOpen: { _ in },
            onCreate: { _ in },
            onToggleAgent: { _, _, _ in },
            onReapply: { _, _ in },
            onRename: { _, _ in },
            onDelete: { _ in }
        ), size: NSSize(width: 720, height: 640))
        try png.write(to: URL(fileURLWithPath: "/tmp/console.png"))
    }

    @Test @MainActor
    func collectionDetail() throws {
        let collection = sampleCollections()[0]
        let png = try renderPNG(CollectionDetailView(
            collection: collection,
            skills: Skill.mockSkills,
            detectedAgents: [],
            statusFor: { _ in .mounted },
            selectedSkill: .constant(nil),
            onToggleAgent: { _, _ in },
            onReapply: { _ in },
            onAddMembers: { _ in },
            onRemoveMember: { _ in },
            onInstall: { _ in },
            onUninstall: { _ in },
            onToggleStar: { _ in }
        ), size: NSSize(width: 560, height: 800))
        try png.write(to: URL(fileURLWithPath: "/tmp/collection-detail.png"))
    }
}
