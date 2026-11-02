import SwiftUI

struct PercentSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.participantList) { person in
                PersonFieldRow(person: person, name: model.displayName(for: person.id), members: model.members.map(\.id), fieldWidth: 120) {
                    HStack {
                        TextField("Percent", text: Binding(
                            get: { model.split.percent[person.id, default: ""] },
                            set: { model.split.percent[person.id] = $0 }
                        ), prompt: Text("0"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel("Percent owed by \(model.displayName(for: person.id))")
                        Text("%").foregroundStyle(.legible).accessibilityHidden(true)
                    }
                }
            }
            if let remaining = model.percentRemaining {
                LabeledContent("Left to assign") {
                    if remaining == 0 {
                        Label {
                            Text("All assigned")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    } else {
                        Label {
                            Text(AmountInput.hundredthsText(remaining, locale: model.locale) + "%").monospacedDigit()
                        } icon: {
                            Image(systemName: remaining < 0 ? "minus.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(remaining < 0 ? .red : .orange)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button("Split Percentages Evenly") { model.fillPercentagesEvenly() }
        } header: {
            Text("Percentages").foregroundStyle(.legible)
        }
    }
}
