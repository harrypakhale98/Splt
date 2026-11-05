import SpltCore
import SwiftUI

/// Everything you set before recording: how much, paid with what, when, and the payment app.
struct SettleControls: View {
    let model: SettleModel
    let onPayWith: (URL) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            if model.isBatch {
                plan
            } else {
                amountSection
            }
            methodRow
            detailsSection
            payWithButton
        }
    }

    // MARK: Amount

    private var amountSection: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 12) {
            if model.fullAmount != nil {
                HStack(spacing: 12) {
                    Picker("Amount", selection: amountModeBinding) {
                        Text("Full").tag(SettleModel.AmountMode.full)
                        Text("Partial").tag(SettleModel.AmountMode.partial)
                    }
                    .pickerStyle(.segmented)
                    .haptics(.tick, trigger: model.amountMode)
                    Button {
                        model.isReversed.toggle()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.headline)
                            .foregroundStyle(Ink.text)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Swap who pays")
                    .accessibilityAddTraits(model.isReversed ? .isSelected : [])
                    .haptics(.tick, trigger: model.isReversed)
                }
            }
            if model.amountMode == .partial {
                HStack(spacing: 12) {
                    stepButton("minus", label: "Less", steps: -1)
                    TextField("Amount", text: $model.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(Typeface.heading.monospacedDigit())
                        .accessibilityLabel("Amount to pay in \(model.fullAmount?.currencyCode ?? "")")
                    stepButton("plus", label: "More", steps: 1)
                }
                .transition(.opacity)
            }
            if let footer = amountMessage {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(.smooth, value: model.amountMode)
    }

    private var amountModeBinding: Binding<SettleModel.AmountMode> {
        Binding(
            get: { model.amountMode },
            set: { mode in
                if mode == .partial { model.setFraction(0.5) } else { model.amountMode = .full }
            }
        )
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, steps: Int) -> some View {
        Button {
            model.nudge(by: steps)
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Ink.text)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private var amountMessage: String? {
        guard let issue = model.amountIssue else {
            return model.isReversed ? String(localized: "This records a payment the other way, such as an advance.") : nil
        }
        switch issue {
        case .empty: return String(localized: "Enter how much was paid.")
        case .invalid: return String(localized: "That isn't an amount.")
        case .notPositive: return String(localized: "The amount must be more than zero.")
        case .exceedsBalance(let limit):
            let owed = MoneyFormatting.magnitudeString(limit, locale: locale)
            return String(localized: "That's more than the \(owed) owed. Swap the direction to record an advance.")
        }
    }

    /// The payments of a whole group as a plain list of who pays whom.
    private var plan: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payments")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .padding(.bottom, 4)
            ForEach(model.route.debts, id: \.self) { debt in
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    Text(model.sentence(payer: debt.debtor, receiver: debt.creditor))
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(MoneyFormatting.magnitudeString(debt.amount, locale: locale))
                        .font(Typeface.figure)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                Divider().overlay(Ink.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Method, date and note

    private var methodRow: some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            Picker("Paid with", selection: $model.method) {
                ForEach(SettleMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .tint(Ink.text)
            .frame(minHeight: 44)
            Divider().overlay(Ink.hairline)
        }
    }

    private var detailsSection: some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            DatePicker("Date", selection: $model.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                .frame(minHeight: 44)
            Divider().overlay(Ink.hairline)
            TextField("Note", text: $model.note, axis: .vertical)
                .lineLimit(1...3)
                .frame(minHeight: 44)
            Divider().overlay(Ink.hairline)
        }
    }

    @ViewBuilder
    private var payWithButton: some View {
        if let url = model.payWithURL {
            VStack(spacing: 8) {
                Button {
                    onPayWith(url)
                } label: {
                    Label("Pay with \(model.method.title)", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle())
                Text("Opens \(model.method.title) so you can send the money. Come back and tap Record Payment when it's done.")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 16)
        }
    }
}
