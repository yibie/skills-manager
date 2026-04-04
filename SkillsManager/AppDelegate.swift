import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = makeAppIcon()
    }

    // MARK: - Programmatic app icon

    private func makeAppIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            // Rounded-rect background (matches macOS icon grid)
            let path = NSBezierPath(roundedRect: rect, xRadius: 112, yRadius: 112)
            path.addClip()

            // Gradient: indigo → blue
            let gradient = NSGradient(
                colors: [
                    NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.10, green: 0.60, blue: 0.90, alpha: 1),
                ],
                atLocations: [0, 1],
                colorSpace: .sRGB
            )!
            gradient.draw(in: rect, angle: -50)

            // White SF Symbol centered
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 280, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let sx = (rect.width - symbol.size.width) / 2
                let sy = (rect.height - symbol.size.height) / 2
                symbol.draw(in: NSRect(x: sx, y: sy, width: symbol.size.width, height: symbol.size.height))
            }
            return true
        }
    }
}
