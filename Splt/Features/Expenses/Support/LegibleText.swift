import SwiftUI

extension ShapeStyle where Self == Color {
    /// Secondary text that stays at 4.5:1 or better on light and dark backgrounds. The system
    /// secondary label is lighter than that on grouped backgrounds.
    static var legible: Color { Color.primary.opacity(0.64) }

    /// The same on a person-colored gradient, where the background varies more.
    static var legibleOnTint: Color { Color.primary.opacity(0.8) }
}
