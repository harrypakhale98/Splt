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
        @State private var chosenMode: Mode?
    @State private var chosenCurrency: String?

    private var mode: Mode { chosenMode ?? (voiceOverOn ? .list : .orbit) }

    private var simplifyToggle: some View {
        Toggle("Simplify Debts", isOn: Binding(
            get: { model.simplifiesDebts },
            set: { model.setSimplifiesDebts($0) }
        ))
    }

    private var modePicker: some View {
        Picker("Balance View", selection: Binding(get: { mode }, set: { chosenMode = $0 })) {
            Text("Orbit").tag(Mode.orbit)
            Text("List").tag(Mode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Balance View")
    }

    private var currency: String {
        if let chosenCurrency, model.balanceCurrencies.contains(chosenCurrency) { return chosenCurrency }
        return model.balanceCurrencies.first ?? "USD"
    }

    var body: some View {
        Section {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    modePicker
                    if model.balanceCurrencies.count > 1 {
                        Picker("Currency", selection: Binding(get: { currency }, set: { chosenCurrency = $0 })) {
                            ForEach(model.balanceCurrencies, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                if mode == .orbit {
                    Divider().overlay(Ink.hairline)
                    BalanceOrbitView(
                        board: model.orbitBoard(currency: currency),
                        members: model.group?.memberIDs ?? [],
                        onSettle: onSettle
                    )
                    .padding(.vertical, 4)
                }
            }
            .raisedRow(padding: EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
        }
        .raisedSection()

        Section {
            simplifyToggle
                .raisedRow(padding: EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        } footer: {
            Group {
                if model.simplifiesDebts {
                    Text("Showing the fewest payments that settle the group.")
                } else {
                    Text("Showing what each person owes each other person directly.")
                }
            }
            .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()

        if mode == .list {
            Section {
                RaisedRows {
                    if model.transfers.isEmpty {
                        Text("Everyone is settled up")
                            .foregroundStyle(Ink.secondary)
                    } else {
                        ForEach(model.transfers, id: \.self) { debt in
                            TransferRow(
                                debt: debt,
                                debtorName: model.name(of: debt.debtor),
                                avatarName: model.peopleByID[debt.debtor]?.name ?? model.name(of: debt.debtor),
                                creditorName: model.name(of: debt.creditor),
                                currentPerson: model.me?.id,
                                members: model.group?.memberIDs ?? [],
                                onTap: { onSettle(debt) }
                            )
                        }
                    }
                }
            } header: {
                SectionHeader("Who owes whom")
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()

            if model.netRows.contains(where: { !$0.isSettled }) {
                Section {
                    RaisedRows {
                        ForEach(model.netRows) { row in
                            NetBalanceRowView(row: row, isMe: row.person.id == model.me?.id, members: model.group?.memberIDs ?? [])
                        }
                    }
                } header: {
                    SectionHeader("Net balances")
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
                .raisedSection()
            }
        }
    }
}

private struct TransferRow: View {
    let debt: Debt
    let debtorName: String
    /// The stored name, so the avatar shows real initials even when the sentence says "You".
    let avatarName: String
    let creditorName: String
    let currentPerson: PersonID?
    let members: [PersonID]
    let onTap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(name: avatarName, id: debt.debtor, members: members, size: 28)
                Text(sentence)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 8)
                Text(MoneyFormatting.string(displayAmount, locale: locale, showsSign: involvesMe))
                    .font(Typeface.figure)
                    .foregroundStyle(involvesMe ? Ink.direction(of: displayAmount.minorUnits) : Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private var involvesMe: Bool {
        debt.debtor == currentPerson || debt.creditor == currentPerson
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
            AvatarView(name: row.person.name, id: row.person.id, members: members, size: 28)
            Text(isMe ? String(localized: "You") : row.person.name)
            Spacer(minLength: 8)
            if row.isSettled {
                Text("Settled up")
                    .foregroundStyle(Ink.secondary)
            } else {
                Text(row.amounts.map(caption(for:)).joined(separator: " \u{B7} "))
                    .monospacedDigit()
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.trailing)
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
