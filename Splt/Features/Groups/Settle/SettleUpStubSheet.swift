import SpltCore
import SwiftUI

/// A plain sheet that records the payments in a `SettleRoute` as they are suggested.
/// The full settle flow replaces it by handling the same route.
struct SettleUpStubSheet: View {
    let route: SettleRoute
    let names: [PersonID: String]
    let currentPerson: PersonID?

    @Environment(\.dataServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var recordedCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(route.debts, id: \.self) { debt in
                        HStack {
                            Text(sentence(for: debt))
                            Spacer(minLength: 8)
                            MoneyLabel(money: debt.amount)
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("This records that the payment was made outside the app.")
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record", action: record)
                }
            }
            .alert("Couldn't Record Payment", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .haptic(.success, trigger: recordedCount)
        }
        .presentationDetents([.medium, .large])
    }

    private func sentence(for debt: Debt) -> String {
        let payer = name(debt.debtor)
        let receiver = name(debt.creditor)
        return debt.debtor == currentPerson
            ? String(localized: "You pay \(receiver)")
            : String(localized: "\(payer) pays \(receiver)")
    }

    private func name(_ id: PersonID) -> String {
        id == currentPerson ? String(localized: "You") : names[id] ?? String(localized: "Someone")
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func record() {
        guard let services else { return }
        do {
            for debt in route.debts {
                try services.payments.settle(debt, in: route.groupID, date: Date())
            }
            recordedCount += 1
            dismiss()
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
    }
}
