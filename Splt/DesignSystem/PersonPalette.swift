import SpltCore
import SwiftUI
import UIKit

/// One stable color per person, used for the avatar, split bar, charts, balance flow and group header.
///
/// Twelve hues, each tuned for light and dark. A color comes from the person's id, and inside a
/// group `assignments(for:)` moves a member to the next free hue when two would look alike.
enum PersonPalette {
    static let count = 12

    /// Light and dark fills as hex values: fills carry white text in light and near black text in dark.
    private static let fills: [(light: UInt32, dark: UInt32)] = [
        (0xD63A3F, 0xFF7A7E), // coral
        (0xD2570A, 0xFF9F5A), // orange
        (0x9A6A00, 0xF5C44E), // amber
        (0x5D7F00, 0xB5E04A), // lime
        (0x2E8B3E, 0x5FD97A), // green
        (0x00806F, 0x3DDBB9), // teal
        (0x007F99, 0x4CD0EE), // cyan
        (0x1A6FD8, 0x6AAEFF), // azure
        (0x4B52C9, 0x8F96FF), // indigo
        (0x8040C8, 0xBB8CFF), // violet
        (0xB62E9B, 0xF07FD9), // magenta
        (0xCC2F67, 0xFF7FA8)  // rose
    ]

    // MARK: Colors

    /// The color of a person inside a group, avoiding the colors of the other members.
    static func color(for person: PersonID, in members: [PersonID]) -> Color {
        color(at: index(for: person, in: members))
    }

    /// The color of a person with no group around them.
    static func color(for person: PersonID) -> Color {
        color(at: preferredIndex(for: person))
    }

    /// A color for something that only has a name, such as a typed placeholder.
    static func color(forName name: String) -> Color {
        color(at: preferredIndex(forName: name))
    }

    /// The fill of hue `index`, wrapping around the twelve hues.
    static func color(at index: Int) -> Color {
        let pair = fills[((index % count) + count) % count]
        return dynamic(light: pair.light, dark: pair.dark)
    }

    /// The text color to put on a person color.
    static let onColor = dynamic(light: 0xFFFFFF, dark: 0x0E0E12)

    /// A variant of the hue for text on a plain background: darker in light mode so it stays readable.
    static func textColor(at index: Int) -> Color {
        let pair = fills[((index % count) + count) % count]
        return Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark { return UIColor(hex: pair.dark) }
            return UIColor(hex: pair.light).adjustedBrightness(0.85)
        })
    }

    // MARK: Assignment

    /// The hue each member gets. The first member keeps the hue the id points to, and a member whose
    /// hue is taken moves to the next free one. The result depends on the order of `members`.
    static func assignments(for members: [PersonID]) -> [PersonID: Int] {
        var taken = Set<Int>()
        var result: [PersonID: Int] = [:]
        for member in members where result[member] == nil {
            var candidate = preferredIndex(for: member)
            if taken.count < count {
                while taken.contains(candidate) { candidate = (candidate + 1) % count }
            }
            taken.insert(candidate)
            result[member] = candidate
        }
        return result
    }

    static func index(for person: PersonID, in members: [PersonID]) -> Int {
        assignments(for: members)[person] ?? preferredIndex(for: person)
    }

    /// The hue an id points to before any collision is resolved. Stable across launches and devices.
    static func preferredIndex(for person: PersonID) -> Int {
        let bytes = withUnsafeBytes(of: person.rawValue.uuid) { Array($0) }
        return Int(fnv(bytes) % UInt64(count))
    }

    static func preferredIndex(forName name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Int(fnv(Array(key.utf8)) % UInt64(count))
    }

    private static func fnv(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    func adjustedBrightness(_ factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation, brightness: brightness * factor, alpha: alpha)
    }
}

#Preview("Palette") {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
        ForEach(0..<PersonPalette.count, id: \.self) { index in
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PersonPalette.color(at: index))
                .frame(height: 64)
                .overlay { Text("\(index + 1)").font(.headline).foregroundStyle(PersonPalette.onColor) }
        }
    }
    .padding()
}
