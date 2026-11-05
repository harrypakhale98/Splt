import SpltCore
import SwiftUI

/// Who paid, as one plain line under the title. Choose one person, or mark others who also paid.
struct PaidByMenu: View {
    let model: ExpenseFormModel
    var onChange: () -> Void = {}

    var body: some View {
        Menu {
            Section("Paid by") {
                ForEach(model.members) { person in
                    Button {
                        model.makeSolePayer(person.id)
                        onChange()
                    } label: {
                        if model.isPayer(person.id), !model.payer.isMultiple {
                            Label(model.displayName(for: person.id), systemImage: "checkmark")
                        } else {
                            Text(model.displayName(for: person.id))
                        }
                    }
                }
            }
            Section("Also paid") {
                ForEach(model.members) { person in
                    Button {
                        model.toggleAlsoPaid(person.id)
                        onChange()
                    } label: {
                        if model.payer.isMultiple, model.isPayer(person.id) {
                            Label(model.displayName(for: person.id), systemImage: "checkmark")
                        } else {
                            Text(model.displayName(for: person.id))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Ink.secondary)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel(title)
        .accessibilityHint("Choose who paid")
        .accessibilityIdentifier("expense-paid-by")
    }

    private var title: String {
        if model.payer.isMultiple {
            return String(localized: "Paid by \(model.payer.selected.count) people")
        }
        guard let single = model.payer.single else { return String(localized: "Choose who paid") }
        if single == model.me?.id { return String(localized: "Paid by you") }
        return String(localized: "Paid by \(model.displayName(for: single))")
    }
}
