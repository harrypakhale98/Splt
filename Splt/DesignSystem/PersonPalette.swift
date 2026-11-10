import SpltCore
import Foundation
import SwiftUI
import UIKit

/// One stable color per person, used for the avatar, split bar, charts, balance flow and group header.
///
/// Twelve muted pigments, each tuned for light and dark. A person has one hue on every screen: the app
/// assigns hues once across everyone it knows (`PersonColorBook`), you first, and until it has
/// done so a person falls back to the hue their id points to. Twelve hues cannot cover everyone, so
/// screens about one group ask for `colors(for:)`: there no two members of up to twelve share a hue.
enum PersonPalette {
    /// The hue that belongs to you.
    static let meIndex = 5

    static let count = 12

    /// Light and dark fills as hex values: fills carry white text in light and near black text in dark.
    private static let fills: [(light: UInt32, dark: UInt32)] = [
        (0xB5432F, 0xE58E7A), // oxide
        (0xA85510, 0xE3A26A), // sienna
        (0x8A660C, 0xD9BC6A), // ochre
        (0x62722A, 0xB4C676), // olive
        (0x3B7A4B, 0x8CC99A), // moss
        (0x1F7668, 0x6FC7B5), // pine
        (0x1F7488, 0x74C1D3), // lagoon
        (0x2F66A8, 0x8DB3E5), // cobalt
        (0x4B55A0, 0xA3A9E8), // indigo
        (0x6F4FA3, 0xBDA3E6), // iris
        (0x96437F, 0xDD9CCB), // plum
        (0xAF3F62, 0xE895AE)  // madder
    ]

    // MARK: Colors

    /// The color of a person within a group, from `indices(for:)`. Someone outside `members` gets
    /// their own color.
    static func color(for person: PersonID, in members: [PersonID]) -> Color {
        color(at: index(for: person, in: members))
    }

    /// Every member's color within one group: no two alike up to twelve members.
    static func colors(for members: [PersonID]) -> [PersonID: Color] {
        indices(for: members).mapValues { color(at: $0) }
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

    /// Each member's hue within one group, the same as `indices(for:)`.
    static func assignments(for members: [PersonID]) -> [PersonID: Int] {
        indices(for: members)
    }

    /// Each member's hue within one group. Everyone keeps their own hue unless a member who got it
    /// first (`PersonColorBook`, you before anyone) already holds it here; then they move to the next
    /// hue no member holds. Up to twelve members never share a hue, and the order of the list does not
    /// matter.
    static func indices(for members: [PersonID]) -> [PersonID: Int] {
        let unique = Array(Set(members))
        guard unique.count > 1 else { return Dictionary(uniqueKeysWithValues: unique.map { ($0, index(for: $0)) }) }
        let book = PersonColorBook.entries(for: unique)
        typealias Ranked = (id: PersonID, rank: Int, hue: Int)
        let ranked: [Ranked] = unique.map { id in
            let entry = book[id]
            return (id: id, rank: entry?.rank ?? Int.max, hue: entry?.hue ?? preferredIndex(for: id))
        }
        let ordered = ranked.sorted { (a: Ranked, b: Ranked) -> Bool in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.id.description < b.id.description
        }
        var result: [PersonID: Int] = [:]
        var taken = Set<Int>()
        var movers: [(id: PersonID, hue: Int)] = []
        for member in ordered {
            if taken.insert(member.hue).inserted {
                result[member.id] = member.hue
            } else {
                movers.append((member.id, member.hue))
            }
        }
        for mover in movers {
            var candidate = mover.hue
            if taken.count < count {
                while taken.contains(candidate) { candidate = (candidate + 1) % count }
            }
            taken.insert(candidate)
            result[mover.id] = candidate
        }
        return result
    }

    /// A person's hue within a group, or their own hue when they are not in `members`.
    static func index(for person: PersonID, in members: [PersonID]) -> Int {
        guard members.contains(person) else { return index(for: person) }
        return indices(for: members)[person] ?? index(for: person)
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

extension ShareStrip {
    /// A strip of these people's colors that follows any change of hues. Pass the group as `members`
    /// so no two members share a color; without it everyone has their own color.
    init(
        people: [PersonID], members: [PersonID]? = nil, weights: [Double]? = nil, height: CGFloat = 3,
        isGrooved: Bool = false
    ) {
        self.init(colors: [], weights: weights, height: height, isGrooved: isGrooved, liveColors: {
            _ = PersonColorRevision.shared.value
            guard let members else { return people.map { PersonPalette.color(for: $0) } }
            let scoped = PersonPalette.colors(for: members)
            return people.map { scoped[$0] ?? PersonPalette.color(for: $0) }
        })
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
