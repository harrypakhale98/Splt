import SwiftUI
import UIKit

/// The app's colors. See docs/design.md: chrome is ink on paper, and color only ever means a
/// person or the direction of money.
enum Ink {
    static let paper = dynamic(light: 0xF6F4EF, dark: 0x131210)
    static let sheet = dynamic(light: 0xFCFBF8, dark: 0x1C1B18)
    static let text = dynamic(light: 0x1A1917, dark: 0xEFEDE6)
    static let secondary = dynamic(light: 0x66635B, dark: 0xA3A097)
    static let tertiary = dynamic(light: 0x9A968C, dark: 0x6E6B63)
    static let hairline = dynamic(light: 0xE2DED5, dark: 0x2E2C28)
    static let owed = dynamic(light: 0x1F6B4A, dark: 0x6FBF96)
    static let owe = dynamic(light: 0xB83A1E, dark: 0xEE7B5C)

    /// The color for a signed amount: owed when positive, owe when negative, plain ink at zero.
    static func direction(of minorUnits: Int64) -> Color {
        if minorUnits > 0 { return owed }
        if minorUnits < 0 { return owe }
        return text
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Puts a screen on paper, including lists and forms that draw their own background.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
    }
}

/// The app's type. Serif is for figures and titles, and the system sans is for everything else.
enum Typeface {
    /// The one big number of a screen.
    static func hero(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// An amount in a row, with tabular digits so columns line up.
    static let figure = Font.system(.body, design: .serif).monospacedDigit()

    /// A serif heading for a section or a card.
    static let heading = Font.system(.title3, design: .serif)

    /// Sets screen titles in the serif face. Call once at launch.
    @MainActor
    static func installNavigationTitles() {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        guard let serif = base.withDesign(.serif) else { return }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: serif, size: 0)]
    }
}

/// The screen's one main action: full width, ink fill.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Ink.paper)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                isEnabled ? Ink.text : Ink.tertiary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .pressEffect(isPressed: configuration.isPressed)
    }
}

/// A secondary action beside a primary one: a hairline outline, no fill.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Ink.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .pressEffect(isPressed: configuration.isPressed)
    }
}

private extension View {
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

    private var total: Double { weights?.reduce(0, +) ?? Double(colors.count) }

    var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(colors.count - 1, 0)) * 2
            let room = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(colors.indices, id: \.self) { index in
                    Rectangle()
                        .fill(colors[index])
                        .frame(width: total > 0 ? room * CGFloat(weight(at: index) / total) : 0)
                }
            }
        }
        .frame(height: height)
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
        Button("Settle up") {}.buttonStyle(PrimaryButtonStyle())
        Button("Add expense") {}.buttonStyle(QuietButtonStyle())
    }
    .padding()
    .background(Ink.paper)
}
