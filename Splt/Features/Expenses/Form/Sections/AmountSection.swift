import SpltCore
import SwiftUI

struct AmountSection: View {
    @Bindable var model: ExpenseFormModel
    var focus: FocusState<ExpenseFormField?>.Binding

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(model.currencyCode)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Amount", text: $model.amountText, prompt: Text("0"))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .keyboardType(.decimalPad)
                    .focused(focus, equals: .amount)
                    .accessibilityLabel("Amount in \(model.currencyCode)")
            }

            NavigationLink {
                ExpenseCurrencyPicker(
                    selection: Binding(get: { model.currencyCode }, set: { model.changeCurrency(to: $0) }),
                    groupCurrencyCode: model.groupCurrencyCode
                )
            } label: {
                LabeledContent("Currency", value: model.currencyCode)
            }

            if let converted = model.convertedTotal {
                LabeledContent("In \(converted.currencyCode)") {
                    VStack(alignment: .trailing) {
                        MoneyLabel(money: converted)
                        if let rate = model.rateText {
                            Text(rate).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            } else if model.lacksRate {
                Label("No exchange rate is saved for \(model.currencyCode). The amount is kept in \(model.currencyCode).", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum ExpenseFormField: Hashable {
    case amount
    case title
}
