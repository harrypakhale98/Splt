import SpltCore
import SwiftUI

/// The amount as the big serif figure. Tapping it opens the number pad.
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
                        .font(Typeface.hero(size: size * 0.45))
                        .foregroundStyle(Ink.secondary)
                    Text(shown.isEmpty ? "0" : shown)
                        .font(Typeface.hero(size: min(size, 80)))
                        .monospacedDigit()
                        .foregroundStyle(shown.isEmpty ? Ink.secondary : Ink.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .motion(Motion.quick, value: model.amountText)
                        .letterpress()
                    if keypadOpen {
                        Rectangle()
                            .fill(Ink.text)
                            .frame(width: 2, height: size * 0.6)
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
                            .font(.body)
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
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

    /// Currency symbols already looked up, by locale and currency, so a keypress never builds a formatter.
    @MainActor private static var symbols: [String: String] = [:]

    private var symbol: String {
        let key = locale.identifier + "|" + model.currencyCode
        if let cached = Self.symbols[key] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = model.currencyCode
        let symbol = formatter.currencySymbol ?? model.currencyCode
        Self.symbols[key] = symbol
        return symbol
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
            .foregroundStyle(Ink.secondary)
            .accessibilityElement(children: .combine)
        } else if model.isFindingRate {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Finding the exchange rate").font(.footnote).foregroundStyle(Ink.secondary)
            }
        } else if model.lacksRate {
            Text("No exchange rate for \(model.currencyCode) yet. The amount stays in \(model.currencyCode).")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
