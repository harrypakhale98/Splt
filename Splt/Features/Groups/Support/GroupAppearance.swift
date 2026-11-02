import SpltCore
import SwiftUI

enum GroupAppearance {
    /// Stable per group, so a group keeps its color on every device.
    static func color(for id: GroupID) -> Color {
        AvatarStyle.color(for: id.description)
    }
}

/// A group symbol on a colored rounded square.
struct GroupIconView: View {
    let symbol: String
    let color: Color
    @ScaledMetric private var scaledSide: CGFloat
    private let baseSide: CGFloat

    init(symbol: String, color: Color, size: CGFloat = 44) {
        self.symbol = symbol
        self.color = color
        baseSide = size
        _scaledSide = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// Grows with text, but never so far that it crowds the name out of the row.
    private var side: CGFloat { min(scaledSide, baseSide * 1.5) }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: side * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        GroupIconView(symbol: "airplane", color: .blue)
        GroupIconView(symbol: "house.fill", color: .green)
        GroupIconView(symbol: "heart.fill", color: .pink, size: 64)
    }
    .padding()
}
