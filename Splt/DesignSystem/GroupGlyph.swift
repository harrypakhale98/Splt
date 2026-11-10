import SwiftUI

/// A group's symbol, plain on the page, for list rows and headers.
struct GroupGlyph: View {
    let symbol: String
    @ScaledMetric private var scaledSide: CGFloat
    private let baseSide: CGFloat

    init(symbol: String, size: CGFloat = 32) {
        self.symbol = symbol
        baseSide = size
        _scaledSide = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var side: CGFloat { min(scaledSide, baseSide * 1.5) }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .regular))
            .foregroundStyle(Ink.secondary)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
