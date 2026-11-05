import SwiftUI

struct ExactSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.participantList) { person in
                PersonFieldRow(person: person, name: model.displayName(for: person.id), members: model.members.map(\.id)) {
                    TextField("Amount", text: Binding(
                        get: { model.split.exact[person.id, default: ""] },
                        set: { model.split.exact[person.id] = $0 }
                    ), prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("Amount owed by \(model.displayName(for: person.id))")
                }
            }
            if let remaining = model.splitRemaining {
                RemainingRow(remaining: remaining)
            }
        } header: {
            Text("Amounts").foregroundStyle(Ink.secondary)
        }
    }
}
