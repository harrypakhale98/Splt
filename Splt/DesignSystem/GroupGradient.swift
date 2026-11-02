import SpltCore
import SwiftUI

/// A soft mesh of a group's member colors. It is meant to sit behind a header or a glyph, at low
/// contrast, so keep small text off it unless you add a scrim.
struct GroupGradient: View {
    let colors: [Color]

    @Environment(\.colorScheme) private var scheme

    init(colors: [Color]) {
        self.colors = colors
    }

    /// Built from the member colors that `PersonPalette` assigns inside the group.
    init(members: [PersonID]) {
        colors = members.map { PersonPalette.color(for: $0, in: members) }
    }

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1]
    ]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: meshColors)
            .accessibilityHidden(true)
    }

    /// Washed toward the background so the gradient stays quiet: lighter in light mode, deeper in dark.
    private var meshColors: [Color] {
        let source = colors.isEmpty ? [Color.teal] : colors
        let base: Color = scheme == .dark ? Color(white: 0.11) : .white
        let amount = scheme == .dark ? 0.55 : 0.68
        return (0..<9).map { index in
            let row = index / 3, column = index % 3
            return source[(row + column) % source.count].mix(with: base, by: amount)
        }
    }
}

/// A group's symbol on its mesh gradient, for list rows and headers.
struct GroupGlyph: View {
    let symbol: String
    let members: [PersonID]
    @ScaledMetric private var scaledSide: CGFloat
    private let baseSide: CGFloat

    init(symbol: String, members: [PersonID], size: CGFloat = 44) {
        self.symbol = symbol
        self.members = members
        baseSide = size
        _scaledSide = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var side: CGFloat { min(scaledSide, baseSide * 1.5) }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: side, height: side)
            .background { GroupGradient(members: members) }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous).strokeBorder(.separator)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    let ids = (0..<4).map { _ in PersonID() }
    VStack(spacing: 20) {
        GroupGradient(members: ids)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        GroupGlyph(symbol: "airplane", members: ids, size: 56)
    }
    .padding()
}
