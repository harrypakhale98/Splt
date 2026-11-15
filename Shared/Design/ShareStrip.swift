import SwiftUI

/// A thin bar of people's colors, the app's recurring mark. Widths follow `weights` when given.
struct ShareStrip: View {
    let colors: [Color]
    var weights: [Double]?
    var height: CGFloat = 3
    /// Sets the bar into the page as a thin groove, for use under the one big number.
    var isGrooved = false
    /// Read as the strip draws, in place of `colors`, so the strip follows any change of hues.
    /// `ShareStrip(people:members:)` sets it.
    var liveColors: (@MainActor () -> [Color])?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var showsGroove: Bool { isGrooved && contrast != .increased }

    var body: some View {
        let shown = liveColors?() ?? colors
        let total = weights?.reduce(0, +) ?? Double(shown.count)
        GeometryReader { proxy in
            let gaps = CGFloat(max(shown.count - 1, 0)) * 2
            let room = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(shown.indices, id: \.self) { index in
                    Rectangle()
                        .fill(
                            shown[index].shadow(
                                .inner(color: .black.opacity(showsGroove ? 0.4 : 0), radius: 0.5, y: 1)
                            )
                        )
                        .frame(width: total > 0 ? room * CGFloat(weight(at: index) / total) : 0)
                }
            }
        }
        .frame(height: showsGroove ? height + 1 : height)
        .shadow(
            color: showsGroove ? (colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.95)) : .clear,
            radius: 0,
            y: 1
        )
        .accessibilityHidden(true)
    }

    private func weight(at index: Int) -> Double {
        guard let weights, weights.indices.contains(index) else { return 1 }
        return weights[index]
    }
}
