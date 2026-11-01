import SwiftUI

/// A circle with a person's initials on a system color that depends only on the name.
struct AvatarView: View {
    let name: String
    @ScaledMetric private var diameter: CGFloat

    init(name: String, size: CGFloat = 40) {
        self.name = name
        _diameter = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Circle()
            .fill(AvatarStyle.color(for: name))
            .frame(width: diameter, height: diameter)
            .overlay {
                Text(AvatarStyle.initials(for: name))
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isImage)
    }
}

enum AvatarStyle {
    private static let palette: [Color] = [.red, .blue, .indigo, .purple, .pink, .brown, .teal, .green]

    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    static func color(for name: String) -> Color {
        palette[paletteIndex(for: name)]
    }

    /// Stable across launches, unlike `hashValue`.
    static func paletteIndex(for name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(palette.count))
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
