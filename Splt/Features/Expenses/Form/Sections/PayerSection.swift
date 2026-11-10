import SpltCore
import SwiftUI

struct PayerSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
                if !model.payer.isMultiple {
                    Picker("Paid by", selection: Binding(
                        get: { model.payer.single ?? model.me?.id },
                        set: { if let id = $0 { model.selectPayer(id) } }
                    )) {
                        ForEach(model.members) { person in
                            Text(model.displayName(for: person.id)).tag(Optional(person.id))
                        }
                    }
                }

                Toggle("Several people paid", isOn: Binding(
                    get: { model.payer.isMultiple },
                    set: { model.setMultiplePayers($0) }
                ))

                if model.payer.isMultiple {
                    PeopleChips(
                        people: model.members, selected: model.payer.selected,
                        currentPerson: model.me?.id, toggle: model.togglePayer
                    )
                    ForEach(model.members.filter { model.payer.selected.contains($0.id) }) { person in
                        PersonFieldRow(person: person, name: model.displayName(for: person.id), members: model.members.map(\.id)) {
                            TextField("Amount", text: Binding(
                                get: { model.payer.amounts[person.id, default: ""] },
                                set: { model.payer.amounts[person.id] = $0 }
                            ), prompt: Text("0"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .accessibilityLabel("Amount paid by \(model.displayName(for: person.id))")
                        }
                    }
                    if let remaining = model.payerRemaining {
                        RemainingRow(remaining: remaining, title: "Still to assign")
                    }
                    if model.payer.selected.count > 1 {
                        Button("Split Evenly Between Payers", action: model.splitPaymentsEvenly)
                    }
                }
            }
        } header: {
            SectionHeader("Paid by")
        }
        .raisedSection()
    }
}

/// Shows how much is left to assign. The icon carries the color, the text stays readable.
struct RemainingRow: View {
    let remaining: Money
    var title: LocalizedStringKey = "Left to assign"

    var body: some View {
        LabeledContent(title) {
            if remaining.isZero {
                Label {
                    Text("All assigned")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            } else {
                Label {
                    MoneyLabel(money: remaining)
                } icon: {
                    Image(systemName: remaining.isNegative ? "minus.circle.fill" : "exclamationmark.circle.fill")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let amount = MoneyFormatting.magnitudeString(remaining)
        if remaining.isZero { return String(localized: "All assigned") }
        return remaining.isNegative ? String(localized: "\(amount) over") : String(localized: "\(amount) left to assign")
    }
}
