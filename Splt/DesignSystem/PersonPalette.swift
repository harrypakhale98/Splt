import SpltCore
import Foundation
import SwiftUI
import UIKit

/// One stable color per person, used for the avatar, split bar, charts, balance flow and group header.
///
/// Twelve hues, each tuned for light and dark. A person has one hue on every screen: the app
/// assigns hues once across everyone it knows (`PersonColorBook`), you first, and until it has
/// done so a person falls back to the hue their id points to.
enum PersonPalette {
    /// The hue that belongs to you, the brand teal.
    static let meIndex = 5

    static let count = 12

    /// Light and dark fills as hex values: fills carry white text in light and near black text in dark.
    private static let fills: [(light: UInt32, dark: UInt32)] = [
        (0xD63A3F, 0xFF7A7E), // coral
        (0xD2570A, 0xFF9F5A), // orange
        (0x9A6A00, 0xF5C44E), // amber
        (0x5D7F00, 0xB5E04A), // lime
        (0x2B8639, 0x5FD97A), // green
        (0x00806F, 0x3DDBB9), // teal
        (0x007F99, 0x4CD0EE), // cyan
        (0x1A6FD8, 0x6AAEFF), // azure
        (0x4B52C9, 0x8F96FF), // indigo
        (0x8040C8, 0xBB8CFF), // violet
        (0xB62E9B, 0xF07FD9), // magenta
        (0xCC2F67, 0xFF7FA8)  // rose
    ]

    // MARK: Colors

    /// The color of a person. The member list is kept for older callers: the color is the same
    /// whichever list is passed.
    static func color(for person: PersonID, in members: [PersonID]) -> Color {
        color(at: index(for: person))
    }

    /// The color of a person, the same on every screen.
    static func color(for person: PersonID) -> Color {
        color(at: index(for: person))
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

    /// The text color to put on a person color when you do not know which one. Prefer `onColor(at:)`,
    /// which picks black or white for the actual fill.
    static let onColor = dynamic(light: 0xFFFFFF, dark: 0x0E0E12)

    private static let white: UInt32 = 0xFFFFFF
    private static let nearBlack: UInt32 = 0x0E0E12

    /// The text color for hue `index`: white or near black, whichever reads better on that fill in
    /// the current appearance. Every pair reaches a 4.5 to 1 contrast ratio.
    static func onColor(at index: Int) -> Color {
        let pair = fills[((index % count) + count) % count]
        return dynamic(light: foregroundHex(onFill: pair.light), dark: foregroundHex(onFill: pair.dark))
    }

    /// The text color for a person, matching `color(for:)`.
    static func onColor(for person: PersonID) -> Color {
        onColor(at: index(for: person))
    }

    /// The fill and text colors of a hue as hex values, for checking contrast.
    static func hexPair(at index: Int, dark: Bool) -> (fill: UInt32, text: UInt32) {
        let pair = fills[((index % count) + count) % count]
        let fill = dark ? pair.dark : pair.light
        return (fill, foregroundHex(onFill: fill))
    }

    static func foregroundHex(onFill fill: UInt32) -> UInt32 {
        contrastRatio(white, fill) >= contrastRatio(nearBlack, fill) ? white : nearBlack
    }

    /// The WCAG contrast ratio of two sRGB colors.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    // MARK: Assignment

    /// Hands out hues in order. The first person keeps the hue their id points to and a person whose
    /// hue is taken moves to the next free one. `reserved` hues are skipped, once all are used they repeat.
    static func resolve(_ people: [PersonID], reserved: Set<Int> = []) -> [PersonID: Int] {
        var taken = reserved
        var result: [PersonID: Int] = [:]
        for person in people where result[person] == nil {
            var candidate = preferredIndex(for: person)
            if taken.count < count {
                while taken.contains(candidate) { candidate = (candidate + 1) % count }
            }
            taken.insert(candidate)
            result[person] = candidate
        }
        return result
    }

    /// The global hue of each listed person, never depending on who else is in the list.
    static func assignments(for members: [PersonID]) -> [PersonID: Int] {
        Dictionary(members.map { ($0, index(for: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    static func index(for person: PersonID, in members: [PersonID]) -> Int {
        index(for: person)
    }

    /// The hue of a person on every screen.
    static func index(for person: PersonID) -> Int {
        PersonColorBook.index(for: person) ?? preferredIndex(for: person)
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
