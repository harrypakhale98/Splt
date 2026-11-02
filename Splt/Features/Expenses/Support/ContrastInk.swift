import SwiftUI
import UIKit

/// Picks white or near black text for a colored fill, whichever reads better.
enum ContrastInk {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// WCAG relative luminance of an sRGB color.
    static func luminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// WCAG contrast ratio between two colors, from 1 to 21.
    static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static let white = RGB(red: 1, green: 1, blue: 1)
    static let black = RGB(red: 0, green: 0, blue: 0)

    /// True when dark text passes better than white on this fill.
    static func prefersDarkInk(on fill: RGB) -> Bool {
        ratio(black, fill) > ratio(white, fill)
    }

    /// The sRGB value of a dynamic color in one appearance.
    static func resolve(_ color: Color, style: UIUserInterfaceStyle) -> RGB {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGB(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// The text color for a fill that may change with the appearance.
    static func ink(on fill: Color, style: UIUserInterfaceStyle) -> Color {
        prefersDarkInk(on: resolve(fill, style: style)) ? .black : .white
    }
}
