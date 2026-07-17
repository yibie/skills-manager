import AppKit
import SwiftUI
import Testing
@testable import SkillsManager

/// Offscreen visual-acceptance harness: renders real views to PNG without a GUI
/// session (no mouse, no window focus). Doubles as a smoke test that the
/// inspector scan completes against this repo. PNGs land in /tmp for eyeballing:
///   swift test --filter InspectorSnapshot
/// Note: List rows stay blank offscreen (lazy rows need a real window); use this
/// for chrome/summary/detail states, not for row-level pixel checks.
struct InspectorSnapshotTests {
    @MainActor
    private func renderPNG<V: View>(_ view: V, size: NSSize) throws -> Data {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test @MainActor
    func inspectorLoadedState() async throws {
        let defaults = try #require(UserDefaults(suiteName: "inspector-snapshot-\(UUID().uuidString)"))
        let model = InspectorViewModel(defaults: defaults)
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkillsManagerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        model.selectProject(projectRoot)

        for _ in 0..<100 where model.presentation == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try #require(model.presentation != nil, "inspector scan did not finish in time")

        let content = try renderPNG(InspectorView(model: model), size: NSSize(width: 520, height: 800))
        try content.write(to: URL(fileURLWithPath: "/tmp/inspector-content.png"))

        let detail = try renderPNG(InspectorDetailView(model: model), size: NSSize(width: 420, height: 800))
        try detail.write(to: URL(fileURLWithPath: "/tmp/inspector-detail.png"))
    }
}
