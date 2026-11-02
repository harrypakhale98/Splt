import SpltCore
import SwiftUI

/// Who owes whom: a ring of people with the money drawn between them, or a plain list. A switch
/// chooses between the fewest payments and the direct debts.
struct GroupBalancesSection: View {
    enum Mode: String, CaseIterable, Identifiable {
        case orbit
        case list

        var id: String { rawValue }
    }

    let model: GroupDetailViewModel
    let onSettle: (Debt) -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chosenMode: Mode?
    @State private var chosenCurrency: String?

    private var mode: Mode { chosenMode ?? (voiceOverOn ? .list : .orbit) }

    private var controls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Toggle("Simplify Debts", isOn: Binding(
                get: { model.simplifiesDebts },
                set: { model.setSimplifiesDebts($0) }
            ))
            Picker("Balance View", selection: Binding(get: { mode }, set: { chosenMode = $0 })) {
                Image(systemName: "circle.hexagongrid").tag(Mode.orbit).accessibilityLabel("Orbit")
                Image(systemName: "list.bullet").tag(Mode.list).accessibilityLabel("List")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 110)
        }
    }

    private var currency: String {
        if let chosenCurrency, model.balanceCurrencies.contains(chosenCurrency) { return chosenCurrency }
        return model.balanceCurrencies.first ?? "USD"
    }

    var body: some View {
        Section {
            controls
            if model.balanceCurrencies.count > 1 {
                Picker("Currency", selection: Binding(get: { currency }, set: { chosenCurrency = $0 })) {
                    ForEach(model.balanceCurrencies, id: \.self) { Text($0).tag($0) }
                }
            }
            if mode == .orbit {
                BalanceOrbitView(
                    board: model.orbitBoard(currency: currency),
                    members: model.group?.memberIDs ?? [],
                    onSettle: onSettle
                )
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 12, trailing: 8))
            }
        } footer: {
            if model.simplifiesDebts {
                Text("Showing the fewest payments that settle the group.")
            } else {
                Text("Showing what each person owes each other person directly.")
            }
        }

        if mode == .list {
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
                            members: model.group?.memberIDs ?? [],
                            onTap: { onSettle(debt) }
                        )
                    }
                }
            }

            if model.netRows.contains(where: { !$0.isSettled }) {
                Section("Net Balances") {
                    ForEach(model.netRows) { row in
                        NetBalanceRowView(row: row, isMe: row.person.id == model.me?.id, members: model.group?.memberIDs ?? [])
                    }
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
    let members: [PersonID]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(name: debtorName, id: debt.debtor, members: members, size: 36)
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
    let members: [PersonID]

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: row.person.name, id: row.person.id, members: members, size: 32)
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
#Preview("Orbit") {
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
