import SwiftUI

/// The number pad built into the screen, so the system keyboard never covers the split.
/// Flat tonal keys on a system material, with large rounded digits that read clearly in both appearances.
struct NumberPad: View {
    let exponent: Int
    var onKey: (AmountKey) -> Void

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var keyHeight: CGFloat = 44

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
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
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            .font(.system(.title, design: .rounded, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: keyHeight)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(.primary)
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
