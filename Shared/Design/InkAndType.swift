import SwiftUI
import UIKit

/// The app's colors. See docs/design.md: chrome is ink on paper, and color only ever means a
/// person or the direction of money.
enum Ink {
    static let paper = dynamic(light: 0xF3F0EA, dark: 0x131210)
    static let sheet = dynamic(light: 0xFFFEFB, dark: 0x23211D)
    static let text = dynamic(light: 0x1A1917, dark: 0xEFEDE6)
    static let secondary = dynamic(light: 0x66635B, dark: 0xA3A097)
    static let tertiary = dynamic(light: 0x9A968C, dark: 0x6E6B63)
    static let hairline = dynamic(light: 0xE2DED5, dark: 0x2E2C28)
    static let owed = dynamic(light: 0x1F6B4A, dark: 0x6FBF96)
    static let owe = dynamic(light: 0xB83A1E, dark: 0xEE7B5C)
    /// The track of a switch that is on. In dark mode plain ink is nearly white, so the white knob
    /// would vanish into it; a mid ink keeps the knob visible and on clearly apart from off.
    static let switchOn = dynamic(light: 0x1A1917, dark: 0x8A877E)
    /// The fill of a system control that draws its own white label, such as Apple's Paste button.
    /// Ink in light mode; in dark mode a deep ink, so white still reads at 6.8 to 1.
    static let whiteLabelFill = dynamic(light: 0x1A1917, dark: 0x5E5B54)

    /// The color for a signed amount: owed when positive, owe when negative, plain ink at zero.
    static func direction(of minorUnits: Int64) -> Color {
        if minorUnits > 0 { return owed }
        if minorUnits < 0 { return owe }
        return text
    }

    /// A color that follows light and dark mode, from hex values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The app's type. Serif is for figures and titles, and the system sans is for everything else.
enum Typeface {
    /// The one big number of a screen.
    static func hero(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// An amount in a row, with tabular digits so columns line up.
    static let figure = Font.system(.body, design: .serif).monospacedDigit()

    /// A serif heading for a section or a card.
    static let heading = Font.system(.title3, design: .serif)

    /// A serif title set in the content, such as a group's name above its figure.
    static let title = Font.system(.title, design: .serif)

    /// The largest serif title, for full-screen moments such as the welcome tour.
    static let display = Font.system(.largeTitle, design: .serif)
}
