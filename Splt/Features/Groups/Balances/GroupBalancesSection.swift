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

    /// The ring's text cannot grow, so VoiceOver and the largest text sizes start with the list, as the Split Bar does.
    private var mode: Mode { chosenMode ?? (voiceOverOn || typeSize.isAccessibilitySize ? .list : .orbit) }

    private var simplifyToggle: some View {
        Toggle("Simplify Debts", isOn: Binding(
            get: { model.simplifiesDebts },
            set: { model.setSimplifiesDebts($0) }
        ))
            .tint(Ink.switchOn)
    }

    /// One quiet text button that swaps the ring for the list, so no second segmented control
    /// sits under the screen's own.
    private var modeButton: some View {
        Button {
            Motion.perform { chosenMode = mode == .orbit ? .list : .orbit }
        } label: {
            if mode == .orbit {
                Text("Show List")
            } else {
                Text("Show Orbit")
            }
        }
        .buttonStyle(.borderless)
        .font(.footnote)
        .foregroundStyle(Ink.text)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var currency: String {
        if let chosenCurrency, model.balanceCurrencies.contains(chosenCurrency) { return chosenCurrency }
        return model.balanceCurrencies.first ?? "USD"
    }

    var body: some View {
        Section {
            if mode == .orbit {
                if model.balanceCurrencies.count > 1 {
                    Picker("Currency", selection: Binding(get: { currency }, set: { chosenCurrency = $0 })) {
                        ForEach(model.balanceCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    .raisedRow()
                }
                // the ring holds the screen's big figure, so it sits on paper rather than in a card
                BalanceOrbitView(
                    board: model.orbitBoard(currency: currency),
                    members: model.group?.memberIDs ?? [],
                    onSettle: onSettle
                )
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                RaisedRows {
                    if model.transfers.isEmpty {
                        Text("Settled up")
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
            }
        } header: {
            HStack(alignment: .center) {
                SectionHeader("Who owes whom")
                Spacer()
                modeButton
            }
            .textCase(nil)
            .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()

        Section {
            simplifyToggle
                .raisedRow()
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

        if mode == .list, model.netRows.contains(where: { !$0.isSettled }) {
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
                AvatarView(name: avatarName, id: debt.debtor, members: members, size: 28)
                if typeSize.isAccessibilitySize {
                    // the sentence and the amount each get the full width rather than squeezing side by side
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sentence)
                            .foregroundStyle(Ink.text)
                        amount
                            .minimumScaleFactor(0.5)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(sentence)
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: 8)
                    amount
                        .minimumScaleFactor(0.7)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens settle up")
    }

    /// Signed and colored when it involves you; otherwise the sentence says who pays whom.
    private var amount: some View {
        Text(MoneyFormatting.string(displayAmount, locale: locale, showsSign: involvesMe))
            .font(Typeface.figure)
            .foregroundStyle(involvesMe ? Ink.direction(of: displayAmount.minorUnits) : Ink.text)
            .lineLimit(1)
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

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            AvatarView(name: row.person.name, id: row.person.id, members: members, size: 28)
            if typeSize.isAccessibilitySize {
                // name above, balance below, so neither is squeezed off the card
                VStack(alignment: .leading, spacing: 4) {
                    name
                    status(alignment: .leading)
                }
                Spacer(minLength: 0)
            } else {
                name
                    .lineLimit(1)
                Spacer(minLength: 8)
                status(alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var name: Text {
        Text(isMe ? String(localized: "You") : row.person.name)
    }

    @ViewBuilder
    private func status(alignment: HorizontalAlignment) -> some View {
        if row.isSettled {
            Text("Settled up")
                .foregroundStyle(Ink.secondary)
        } else {
            VStack(alignment: alignment, spacing: 2) {
                ForEach(row.amounts, id: \.currencyCode) { amount in
                    caption(for: amount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .monospacedDigit()
            .foregroundStyle(Ink.secondary)
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
    }

    /// The words stay grey and the figure takes the direction's color, as in the transfer rows.
    private func caption(for amount: Money) -> Text {
        let value = Text(MoneyFormatting.magnitudeString(amount, locale: locale))
            .font(Typeface.figure)
            .foregroundStyle(Ink.direction(of: amount.minorUnits))
        switch (amount.minorUnits > 0, isMe) {
        case (true, true): return Text("are owed \(value)")
        case (true, false): return Text("is owed \(value)")
        case (false, true): return Text("owe \(value)")
        case (false, false): return Text("owes \(value)")
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
