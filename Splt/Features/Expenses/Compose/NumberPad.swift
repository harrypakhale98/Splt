import SwiftUI

/// The number pad built into the screen, so the system keyboard never covers the split.
/// Flat keys in ink on paper, with no fill.
struct NumberPad: View {
    let exponent: Int
    /// Lower keys for screens where the pad would otherwise cover the split bar or the title field.
    var compact = false
    var onKey: (AmountKey) -> Void

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var scaledKeyHeight: CGFloat = 48

    private var keyHeight: CGFloat { compact ? min(scaledKeyHeight, 44) : scaledKeyHeight }

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in key(.digit(digit), title: AmountKeypad.digit(digit, locale: locale)) }
                }
            }
            GridRow {
                if exponent > 0 {
                    key(.decimal, title: AmountKeypad.decimalSeparator(locale), label: String(localized: "Decimal point"))
                } else {
                    Color.clear.frame(height: keyHeight)
                }
                key(.digit(0), title: AmountKeypad.digit(0, locale: locale))
                key(.delete, systemImage: "delete.backward", label: String(localized: "Delete"))
            }
        }
        // keypads keep 1 on the left in right-to-left languages too, like the system's
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number pad")
    }

    private func key(_ key: AmountKey, title: String? = nil, systemImage: String? = nil, label: String? = nil) -> some View {
        Button {
            Haptics.play(.tick)
            onKey(key)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? "")
                }
            }
            .font(.system(.title, design: .serif))
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            .contentShape(.rect)
        }
        .buttonStyle(KeyStyle())
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityIdentifier(identifier(for: key))
    }

    private func identifier(for key: AmountKey) -> String {
        switch key {
        case .digit(let value): "key-\(value)"
        case .decimal: "key-decimal"
        case .delete: "key-delete"
        }
    }
}

/// A key with no fill: ink that dims while it is held.
private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Ink.text)
            .opacity(configuration.isPressed ? 0.3 : 1)
            .motion(Motion.quick, value: configuration.isPressed)
    }
}
