import SpltCore
import SwiftUI

/// A circle with a person's initials on their person color.
///
/// A person has the same color on every screen. `members` is kept for older callers and does not
/// change the color. Without an id the color comes from the name.
struct AvatarView: View {
    let name: String
    private let personID: PersonID?
    private let fixedHue: Int?
    private let showsInitials: Bool
    @ScaledMetric private var scaledDiameter: CGFloat
    private let baseDiameter: CGFloat

    init(name: String, size: CGFloat = 40, showsInitials: Bool = true) {
        self.name = name
        self.showsInitials = showsInitials
        personID = nil
        fixedHue = nil
        baseDiameter = size
        _scaledDiameter = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    init(name: String, id: PersonID, members: [PersonID] = [], size: CGFloat = 40, showsInitials: Bool = true) {
        self.name = name
        self.showsInitials = showsInitials
        personID = id
        fixedHue = nil
        baseDiameter = size
        _scaledDiameter = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// An avatar in a given hue, for you before your person exists.
    init(name: String, hue: Int, size: CGFloat = 40, showsInitials: Bool = true) {
        self.name = name
        self.showsInitials = showsInitials
        personID = nil
        fixedHue = hue
        baseDiameter = size
        _scaledDiameter = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    init(person: Person, members: [PersonID] = [], size: CGFloat = 40, showsInitials: Bool = true) {
        self.init(name: person.name, id: person.id, members: members, size: size, showsInitials: showsInitials)
    }

    /// Grows with text, but never so far that it crowds its neighbors.
    static func diameter(scaled: CGFloat, base: CGFloat) -> CGFloat { min(scaled, base * 1.5) }

    private var diameter: CGFloat { Self.diameter(scaled: scaledDiameter, base: baseDiameter) }

    private var hue: Int {
        _ = PersonColorRevision.shared.value
        if let fixedHue { return fixedHue }
        if let personID { return PersonPalette.index(for: personID) }
        return PersonPalette.preferredIndex(forName: name)
    }

    var body: some View {
        Circle()
            .fill(PersonPalette.color(at: hue))
            .frame(width: diameter, height: diameter)
            .overlay {
                if showsInitials {
                    Text(AvatarStyle.initials(for: name))
                        .font(.system(size: diameter * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(PersonPalette.onColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isImage)
    }
}

enum AvatarStyle {
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    static func color(for name: String) -> Color {
        PersonPalette.color(forName: name)
    }

    /// Stable across launches, unlike `hashValue`.
    static func paletteIndex(for name: String) -> Int {
        PersonPalette.preferredIndex(forName: name)
    }
}

#Preview {
    HStack {
        ForEach(["Sam Rivera", "Priya", "Alex Chen", "Jo", "Maria Gonzalez"], id: \.self) {
            AvatarView(name: $0)
        }
    }
    .padding()
}

#Preview("Large text") {
    AvatarView(name: "Sam Rivera", size: 56)
        .dynamicTypeSize(.accessibility3)
}
