import SwiftUI

struct ExactSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.participantList) { person in
                HStack {
                    AvatarView(name: person.name, size: 28)
                    Text(model.displayName(for: person.id))
                    Spacer(minLength: 8)
                    TextField("Amount", text: Binding(
                        get: { model.split.exact[person.id, default: ""] },
                        set: { model.split.exact[person.id] = $0 }
                    ), prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Amount owed by \(model.displayName(for: person.id))")
                }
            }
            if let remaining = model.splitRemaining {
                RemainingRow(remaining: remaining)
            }
        } header: {
            Text("Amounts")
        }
    }
}
