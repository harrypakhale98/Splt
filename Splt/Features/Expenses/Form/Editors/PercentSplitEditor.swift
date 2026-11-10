import SwiftUI

struct PercentSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
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
                            Text("%").foregroundStyle(Ink.secondary).accessibilityHidden(true)
                        }
                    }
                }
                if let remaining = model.percentRemaining {
                    LabeledContent("Left to assign") {
                        if remaining == 0 {
                            Label {
                                Text("All assigned")
                            } icon: {
                                Image(systemName: "checkmark.circle")
                            }
                        } else {
                            Label {
                                Text((Double(remaining) / 10_000).formatted(.percent.locale(model.locale).precision(.fractionLength(0...2)))).monospacedDigit()
                            } icon: {
                                Image(systemName: remaining < 0 ? "minus.circle.fill" : "exclamationmark.circle.fill")
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button("Split Percentages Evenly") { model.fillPercentagesEvenly() }
            }
        } header: {
            SectionHeader("Percentages")
        }
        .raisedSection()
    }
}
