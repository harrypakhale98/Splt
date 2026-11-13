import SpltCore
import SwiftUI

/// Shows an expense or a payment a friend sent back from a balance link, so you can check it before
/// it goes into the group. Nothing is added until you tap Add.
struct ReplyReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var model: ReplyReviewModel

    init(fragment: String, services: DataServices) {
        _model = State(initialValue: ReplyReviewModel(fragment: fragment, services: services))
    }

    var body: some View {
        NavigationStack {
            content
                .paperBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", role: .close) { dismiss() }
                    }
                }
                .alert("Couldn't Add", isPresented: errorBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("reply.sheet")
    }

    private var title: LocalizedStringKey {
        switch model.state {
        case .ready(let proposal):
            if case .payment = proposal.item { "Check Payment" } else { "Check Expense" }
        default:
            "Balance Link"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .ready(let proposal):
            ready(proposal)
        case .alreadyAdded(let groupName, let group):
            ContentUnavailableView {
                Label("Already Added", systemImage: "checkmark.circle")
            } description: {
                Text("This is already in \(groupName).")
            } actions: {
                Button("Open \(groupName)") { router.open(.group(group.rawValue)) }
                    .buttonStyle(.bordered)
            }
        case .problem(let title, let message):
            ContentUnavailableView {
                Label(title, systemImage: "link")
            } description: {
                Text(message)
            }
        }
    }

    private func ready(_ proposal: ReplyReviewModel.Proposal) -> some View {
        List {
            Section {
                RaisedRows {
                    HStack(spacing: 12) {
                        AvatarView(person: proposal.author, members: proposal.group.memberIDs, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sentLine(proposal))
                                .font(.subheadline.weight(.semibold))
                            Text("For \(proposal.groupName) · \(proposal.sentAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .raisedSection()

            Section {
                RaisedRows {
                    switch proposal.item {
                    case .expense(let expense, let payer, let participants):
                        expenseRows(expense, payer: payer, participants: participants, group: proposal.group)
                    case .payment(let payment, let from, let to):
                        paymentRows(payment, from: from, to: to, group: proposal.group)
                    }
                }
            } footer: {
                Text("Nothing is added until you tap below. You can edit or delete it afterwards, like anything else in the group.")
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
        .safeAreaInset(edge: .bottom) {
            Button(addLabel(proposal)) {
                if let group = model.add() {
                    router.open(.group(group.rawValue))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Depth.pageMargin + 4)
            .padding(.bottom, 8)
            .accessibilityIdentifier("reply.add")
        }
    }

    @ViewBuilder
    private func expenseRows(_ expense: Expense, payer: Person, participants: [Person], group: SplitGroup) -> some View {
        detail("What for", expense.title)
        detail("Amount", MoneyFormatting.string(expense.total))
        detail("Date", expense.date.formatted(date: .abbreviated, time: .omitted))
        HStack {
            Text("Paid by")
            Spacer()
            AvatarView(person: payer, members: group.memberIDs, size: 22)
            Text(payer.name).foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split equally")
                Spacer()
                if let each = equalShare(expense, count: participants.count) {
                    Text("\(each) each").foregroundStyle(Ink.secondary)
                }
            }
            Text(ListFormatter.localizedString(byJoining: participants.map(\.name)))
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func paymentRows(_ payment: Payment, from: Person, to: Person, group: SplitGroup) -> some View {
        HStack(spacing: 8) {
            AvatarView(person: from, members: group.memberIDs, size: 22)
            Text("\(from.name) paid \(to.name)")
            Spacer()
            Text(MoneyFormatting.string(payment.amount))
                .foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        detail("Date", payment.date.formatted(date: .abbreviated, time: .omitted))
    }

    private func detail(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func sentLine(_ proposal: ReplyReviewModel.Proposal) -> String {
        switch proposal.item {
        case .expense: String(localized: "\(proposal.author.name) sent an expense")
        case .payment: String(localized: "\(proposal.author.name) sent a payment")
        }
    }

    private func addLabel(_ proposal: ReplyReviewModel.Proposal) -> String {
        switch proposal.item {
        case .expense: String(localized: "Add to \(proposal.groupName)")
        case .payment: String(localized: "Record Payment")
        }
    }

    /// What each person's share comes to, when it splits evenly to the cent.
    private func equalShare(_ expense: Expense, count: Int) -> String? {
        guard count > 0, expense.total.minorUnits % Int64(count) == 0 else { return nil }
        return MoneyFormatting.string(Money(minorUnits: expense.total.minorUnits / Int64(count), currencyCode: expense.total.currencyCode))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
