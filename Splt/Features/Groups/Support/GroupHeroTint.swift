import SpltCore
import SwiftUI
import UIKit

/// The colors behind a group's header. One hue belongs to the group itself, so each group reads as
/// its own, and up to two member hues join it at low strength. The hues sit next to each other on
/// the palette wheel, so the result stays calm.
enum GroupHeroTint {
    /// Palette indexes: the group's own hue first, then at most two from its members.
    static func hues(for group: SplitGroup) -> [Int] {
        let dominant = PersonPalette.preferredIndex(for: PersonID(rawValue: group.id.rawValue))
        var result = [dominant]
        for member in group.memberIDs {
            let hue = PersonPalette.index(for: member, in: group.memberIDs)
            if !result.contains(hue), distance(hue, dominant) <= 3 || result.count == 1 {
                result.append(hue)
            }
            if result.count == 3 { break }
        }
        return result
    }

    /// How far apart two hues are on the twelve step wheel.
    static func distance(_ a: Int, _ b: Int) -> Int {
        let gap = abs(a - b) % PersonPalette.count
        return min(gap, PersonPalette.count - gap)
    }

    enum Role {
        /// The group's own hue, a little stronger.
        case dominant
        /// A member hue, washed out.
        case accent
    }

    /// The hue washed toward the background: toward white in light mode and toward a deep gray in dark.
    static func color(index: Int, role: Role) -> Color {
        Color(uiColor: UIColor { traits in
            let fill = UIColor(PersonPalette.color(at: index)).resolvedColor(with: traits)
            return blend(fill, toward: base(for: traits), amount: amount(role, dark: traits.userInterfaceStyle == .dark))
        })
    }

    static func base(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.09, alpha: 1) : .white
    }

    static func amount(_ role: Role, dark: Bool) -> CGFloat {
        switch (role, dark) {
        case (.dominant, false): 0.62
        case (.accent, false): 0.8
        case (.dominant, true): 0.68
        case (.accent, true): 0.82
        }
    }

    static func blend(_ color: UIColor, toward base: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        base.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1
        )
    }

    /// Relative luminance of a color, for contrast checks.
    static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio between two colors.
    static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

/// A quiet three by three mesh in the group's own colors. Small text may sit on it.
struct GroupHeroBackground: View {
    let hues: [Int]

    init(group: SplitGroup) {
        hues = GroupHeroTint.hues(for: group)
    }

    init(hues: [Int]) {
        self.hues = hues.isEmpty ? [0] : hues
    }

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1]
    ]

    var body: some View {
        let dominant = GroupHeroTint.color(index: hues[0], role: .dominant)
        let first = GroupHeroTint.color(index: hues.count > 1 ? hues[1] : hues[0], role: .accent)
        let second = GroupHeroTint.color(index: hues.count > 2 ? hues[2] : hues[0], role: .accent)
        MeshGradient(width: 3, height: 3, points: Self.points, colors: [
            first, dominant, dominant,
            dominant, dominant, second,
            dominant, second, first
        ])
        .accessibilityHidden(true)
    }
}
