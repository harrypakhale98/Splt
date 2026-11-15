import SwiftUI
import UIKit

extension View {
    /// Puts a screen on paper, including lists and forms that draw their own background.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
    }

    /// The one style for a section's label: small, secondary, in the case it was written in.
    /// Write the label in sentence case, such as "Paid by" or "Who owes whom".
    func sectionHeaderStyle() -> some View {
        font(.footnote)
            .foregroundStyle(Ink.secondary)
            .textCase(nil)
    }
}

/// A section's label in the one shared style. Use it as a List or Form section header, or above a card.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title).sectionHeaderStyle()
    }
}

extension Typeface {
    /// Sets screen titles in the serif face. Call once at launch.
    @MainActor
    static func installNavigationTitles() {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        guard let serif = base.withDesign(.serif) else { return }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: serif, size: 0)]
    }
}

/// The screen's one main action: full width, a slab of ink that sinks when pressed. A disabled
/// button lies flat on the page, so only what can be pressed looks raised.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous)
        let isRaised = isEnabled && contrast != .increased
        let isDark = colorScheme == .dark
        return configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Ink.paper)
            .multilineTextAlignment(.center)
            .buttonLabelPadding()
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                shape.fill(isEnabled ? Ink.text : Ink.tertiary)
                    .overlay {
                        if isRaised {
                            shape.strokeBorder(
                                Depth.topLight(strength: isDark ? 0.9 : (isPressed ? 0.08 : 0.16)),
                                lineWidth: 1
                            )
                        }
                    }
                    .shadow(
                        color: isRaised ? (isDark ? Color.black.opacity(0.5) : Depth.warmShadow.opacity(0.2)) : .clear,
                        radius: isPressed ? 1 : 4,
                        y: isPressed ? 1 : 3
                    )
            }
            .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
            .offset(y: isPressed && !reduceMotion ? 1 : 0)
            .opacity(isPressed && reduceMotion ? 0.7 : 1)
            .motion(Motion.quick, value: isPressed)
    }
}

/// A secondary action beside a primary one: a hairline outline, no fill.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.center)
            .buttonLabelPadding()
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay {
                RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous).strokeBorder(Ink.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous))
            .pressEffect(isPressed: configuration.isPressed)
    }
}

private extension View {
    /// Keeps a label off the button's edges wherever the button ends up: when a container shrinks
    /// it to fit, and when large text fills it.
    func buttonLabelPadding() -> some View {
        padding(.horizontal, 24)
            .padding(.vertical, 8)
    }

    func pressEffect(isPressed: Bool) -> some View {
        opacity(isPressed ? 0.7 : 1)
            .motion(Motion.quick, value: isPressed)
    }
}

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

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        Text("€1,650.07").font(Typeface.hero(size: 52))
        ShareStrip(colors: (0..<6).map { PersonPalette.color(at: $0 * 2) })
        Button("Settle Up") {}.buttonStyle(PrimaryButtonStyle())
        Button("Add Expense") {}.buttonStyle(QuietButtonStyle())
    }
    .padding()
    .background(Ink.paper)
}
