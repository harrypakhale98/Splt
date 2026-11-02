import SwiftUI

/// The number pad built into the screen, so the system keyboard never covers the split.
struct NumberPad: View {
    let exponent: Int
    var onKey: (AmountKey) -> Void

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var keyHeight: CGFloat = 42
    @State private var presses = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { digit in key(.digit(digit), title: "\(digit)") }
                    }
                }
                GridRow {
                    if exponent > 0 {
                        key(.decimal, title: AmountKeypad.decimalSeparator(locale) == "," ? "," : ".", label: String(localized: "Decimal point"))
                    } else {
                        Color.clear.frame(height: keyHeight)
                    }
                    key(.digit(0), title: "0")
                    key(.delete, systemImage: "delete.backward", label: String(localized: "Delete"))
                }
            }
        }
        .haptics(.tick, trigger: presses)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number pad")
    }

    private func key(_ key: AmountKey, title: String? = nil, systemImage: String? = nil, label: String? = nil) -> some View {
        Button {
            presses += 1
            onKey(key)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? "")
                }
            }
            .font(.system(.title2, design: .rounded, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: keyHeight)
        }
        .buttonStyle(.glass)
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
