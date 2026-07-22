import AppKit
import SwiftUI

// MARK: - 控制台视觉基调(纸感白)
// 白/浅灰底,白卡 + 可见 1px 描边,单一深青强调色,诚实状态色(青/灰/琥珀)。
// 深色模式自动切换到「暗纸」变体:同一套语言,深色表面。
enum ConsoleTheme {
    /// 页面底色:light #FAFAFA / dark #17171A
    static let pageBackground = adaptive(light: 0xFAFAFA, dark: 0x17171A)
    /// 卡片表面:light #FFFFFF / dark #232327
    static let cardBackground = adaptive(light: 0xFFFFFF, dark: 0x232327)
    /// 卡片 1px 描边:light #E5E5E5 / dark 白 7%
    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.07) : NSColor(hex: 0xE5E5E5)
    })
    /// 唯一强调色(每视图一个):light #0F766E / dark #2DD4BF
    static let accent = adaptive(light: 0x0F766E, dark: 0x2DD4BF)
    /// 状态:正常 = 强调色
    static let statusOk = accent
    /// 状态:未挂载/关闭:light #D1D1D6 / dark #4A4A52
    static let statusOff = adaptive(light: 0xD1D1D6, dark: 0x4A4A52)
    /// 状态:与磁盘不一致:light #D97706 / dark #F59E0B
    static let statusWarn = adaptive(light: 0xD97706, dark: 0xF59E0B)

    // textPrimary / textSecondary 直接用系统色(.primary / .secondary),不硬编码。

    // MARK: 度量
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 10
    static let mountRowHeight: CGFloat = 24
    static let gridSpacing: CGFloat = 16

    /// 自适应颜色:浅色/深色各一个 hex。
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.isDark ? dark : light)
        })
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 纸感卡片

extension View {
    /// 纸感卡片:内边距 → 通宽 → 卡片底色 → 圆角裁切 → 1px 描边。
    func paperCard() -> some View {
        self
            .padding(ConsoleTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConsoleTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ConsoleTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ConsoleTheme.cardRadius)
                    .stroke(ConsoleTheme.cardBorder, lineWidth: 1)
            )
    }
}
