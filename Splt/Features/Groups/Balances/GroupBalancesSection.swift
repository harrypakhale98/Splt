import SpltCore
import SwiftUI

/// Who owes whom, with a switch between the fewest payments and the direct debts.
struct GroupBalancesSection: View {
    let model: GroupDetailViewModel
    let onSettle: (Debt) -> Void

    var body: some View {
        Section {
            Toggle("Simplify Debts", isOn: Binding(
                get: { model.simplifiesDebts },
                set: { model.setSimplifiesDebts($0) }
            ))
        } footer: {
            if model.simplifiesDebts {
                Text("Showing the fewest payments that settle the group.")
            } else {
                Text("Showing what each person owes each other person directly.")
            }
        }

        Section("Who Owes Whom") {
            if model.transfers.isEmpty {
                Label("Everyone is settled up", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.transfers, id: \.self) { debt in
                    TransferRow(
                        debt: debt,
                        debtorName: model.name(of: debt.debtor),
                        creditorName: model.name(of: debt.creditor),
                        currentPerson: model.me?.id,
                        onTap: { onSettle(debt) }
                    )
                }
            }
        }

        if model.netRows.contains(where: { !$0.isSettled }) {
            Section("Net Balances") {
                ForEach(model.netRows) { row in
                    NetBalanceRowView(row: row, isMe: row.person.id == model.me?.id)
                }
            }
        }
    }
}

private struct TransferRow: View {
    let debt: Debt
    let debtorName: String
    let creditorName: String
    let currentPerson: PersonID?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(name: debtorName, size: 36)
                Text(sentence)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                MoneyLabel(money: displayAmount, style: style)
                    .font(.body.weight(.semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens settle up")
    }

    private var sentence: String {
        if debt.debtor == currentPerson { return String(localized: "You owe \(creditorName)") }
        if debt.creditor == currentPerson { return String(localized: "\(debtorName) owes you") }
        return String(localized: "\(debtorName) owes \(creditorName)")
    }

    private var style: MoneyLabel.Style {
        debt.debtor == currentPerson || debt.creditor == currentPerson ? .balance : .plain
    }

    private var displayAmount: Money {
        debt.debtor == currentPerson
            ? Money(minorUnits: -debt.amount.minorUnits, currencyCode: debt.amount.currencyCode)
            : debt.amount
    }
}

private struct NetBalanceRowView: View {
    let row: NetBalanceRow
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: row.person.name, size: 32)
            Text(isMe ? String(localized: "You") : row.person.name)
            Spacer(minLength: 8)
            if row.isSettled {
                Text("Settled up")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing) {
                    ForEach(row.amounts, id: \.currencyCode) { amount in
                        Text(caption(for: amount))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(for amount: Money) -> String {
        let value = MoneyFormatting.magnitudeString(amount)
        switch (amount.minorUnits > 0, isMe) {
        case (true, true): return String(localized: "are owed \(value)")
        case (true, false): return String(localized: "is owed \(value)")
        case (false, true): return String(localized: "owe \(value)")
        case (false, false): return String(localized: "owes \(value)")
        }
    }
}

#if DEBUG
#Preview {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    NavigationStack {
        if let trip {
            List {
                GroupBalancesSection(model: GroupDetailViewModel(groupID: trip.id, services: services), onSettle: { _ in })
            }
        }
    }
}
#endif
