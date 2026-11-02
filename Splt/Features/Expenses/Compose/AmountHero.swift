import SpltCore
import SwiftUI

/// The amount as big rounded numerals. Tapping it opens the number pad.
struct AmountHero: View {
    let model: ExpenseFormModel
    let keypadOpen: Bool
    var onTap: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onTap) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(symbol)
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.legible)
                    Text(shown.isEmpty ? "0" : shown)
                        .font(.system(size: min(size, 96), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(shown.isEmpty ? Color.legible : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .motion(.snappy, value: model.amountText)
                    if keypadOpen {
                        Capsule()
                            .fill(.tint)
                            .frame(width: 3, height: size * 0.6)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                if keypadOpen {
                    Button(action: onTap) {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Hide number pad")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Amount in \(model.currencyCode)")
            .accessibilityValue(model.amountText.isEmpty ? String(localized: "Empty") : model.amountText)
            .accessibilityHint(keypadOpen ? String(localized: "Use the number pad to change it") : String(localized: "Opens the number pad"))
            .accessibilityIdentifier("expense-amount")

            conversion
        }
    }

    private var shown: String { AmountKeypad.display(model.amountText, locale: locale) }

    private var symbol: String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = model.currencyCode
        return formatter.currencySymbol ?? model.currencyCode
    }

    @ViewBuilder
    private var conversion: some View {
        if let converted = model.convertedTotal {
            HStack(spacing: 6) {
                Text("About")
                MoneyLabel(money: converted)
                if let rate = model.rateText { Text("(\(rate))") }
            }
            .font(.footnote)
            .foregroundStyle(.legible)
            .accessibilityElement(children: .combine)
        } else if model.isFindingRate {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Finding the exchange rate").font(.footnote).foregroundStyle(.legible)
            }
        } else if model.lacksRate {
            Text("No exchange rate for \(model.currencyCode) yet. The amount stays in \(model.currencyCode).")
                .font(.footnote)
                .foregroundStyle(.legible)
                .multilineTextAlignment(.center)
        }
    }
}
