import SwiftUI

struct AdjustmentSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            RaisedRows {
                ForEach(model.participantList) { person in
                    PersonFieldRow(person: person, name: model.displayName(for: person.id), members: model.members.map(\.id)) {
                        TextField("Adjustment", text: Binding(
                            get: { model.split.adjustments[person.id, default: ""] },
                            set: { model.split.adjustments[person.id] = $0 }
                        ), prompt: Text("0"))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel("Adjustment for \(model.displayName(for: person.id))")
                    }
                }
            }
        } header: {
            SectionHeader("Adjustments")
        } footer: {
            Text("Enter an amount to add to someone's share, or a minus amount to take off. Everything else is split equally.").foregroundStyle(Ink.secondary)
        }
        .raisedSection()
    }
}
