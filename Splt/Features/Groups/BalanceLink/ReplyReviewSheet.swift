import SpltCore
import SwiftUI

/// Shows an expense or a payment a friend sent back from a balance link, laid out like the expense
/// screen, so you can check it before it goes into the group. Nothing is added until you tap Add.
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
        // the split is what needs checking, so the sheet opens tall enough to show it
        .presentationDetents([.large])
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
            EmptyStateView(
                title: "Already Added",
                systemImage: "checkmark.circle",
                description: "This is already in \(groupName).",
                actionTitle: "Open \(groupName)",
                action: { router.open(.group(group.rawValue)) }
            )
        case .problem(let problem):
            problemView(problem)
        }
    }

    // MARK: Ready

    private func ready(_ proposal: ReplyReviewModel.Proposal) -> some View {
        List {
            header(proposal)
            if case .expense(let expense, _, let shares) = proposal.item {
                splitSection(expense, shares: shares, group: proposal.group)
            }
            Text(sentLine(proposal))
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
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

    /// The expense screen's header: what it was, the one big number, who paid and when.
    private func header(_ proposal: ReplyReviewModel.Proposal) -> some View {
        Section {
            VStack(spacing: 8) {
                Text(headline(proposal))
                    .font(Typeface.heading)
                    .multilineTextAlignment(.center)
                HeroAmount(amount(proposal), showsSign: false)
                Text(quietLine(proposal))
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                if case .expense(_, _, let shares) = proposal.item {
                    ShareStrip(
                        people: shares.map(\.person.id),
                        members: proposal.group.memberIDs,
                        weights: shares.map { Double(max($0.amount.minorUnits, 0)) },
                        isGrooved: true
                    )
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Each person's share, as the expense screen lists them.
    private func splitSection(_ expense: Expense, shares: [ReplyReviewModel.ShareLine], group: SplitGroup) -> some View {
        Section {
            RaisedRows {
                ForEach(shares) { line in
                    HStack {
                        AvatarView(person: line.person, members: group.memberIDs, size: 28)
                        Text(line.person.name)
                        Spacer(minLength: 8)
                        MoneyLabel(money: line.amount).font(Typeface.figure)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            SectionHeader("Split")
        } footer: {
            Text(SplitMethod(expense.split).title)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        }
        // a plain list draws a section footer on white, not on the paper behind it
        .listRowBackground(Ink.paper)
    }

    // MARK: Words

    private func amount(_ proposal: ReplyReviewModel.Proposal) -> Money {
        switch proposal.item {
        case .expense(let expense, _, _): expense.total
        case .payment(let payment, _, _): payment.amount
        }
    }

    private func headline(_ proposal: ReplyReviewModel.Proposal) -> String {
        switch proposal.item {
        case .expense(let expense, _, _): expense.title
        case .payment: String(localized: "Payment")
        }
    }

    /// "Maya Chen paid · 11 Nov 2026", or who paid whom for a payment.
    private func quietLine(_ proposal: ReplyReviewModel.Proposal) -> String {
        switch proposal.item {
        case .expense(let expense, let payer, _):
            let who = ExpenseSummary.payerText(expense.payers, currentPerson: proposal.me, names: [payer.id: payer.name])
            return [who, expense.date.formatted(.dateTime.day().month(.abbreviated).year())].joined(separator: " \u{00B7} ")
        case .payment(let payment, let from, let to):
            let who: String = if from.id == proposal.me {
                String(localized: "You paid \(to.name)")
            } else if to.id == proposal.me {
                String(localized: "\(from.name) paid you")
            } else {
                String(localized: "\(from.name) paid \(to.name)")
            }
            return [who, payment.date.formatted(.dateTime.day().month(.abbreviated).year())].joined(separator: " \u{00B7} ")
        }
    }

    private func sentLine(_ proposal: ReplyReviewModel.Proposal) -> String {
        let name = proposal.author.name
        let when = proposal.sentAt.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Sent by \(name) from a balance link on \(when). Nothing is added until you tap below, and you can edit or delete it afterwards.")
    }

    private func addLabel(_ proposal: ReplyReviewModel.Proposal) -> String {
        switch proposal.item {
        case .expense: String(localized: "Add to \(proposal.groupName)")
        case .payment: String(localized: "Record Payment")
        }
    }

    // MARK: Problems

    @ViewBuilder
    private func problemView(_ problem: ReplyReviewModel.Problem) -> some View {
        switch problem {
        case .unreadable:
            EmptyStateView(
                title: "This Link Doesn't Open", systemImage: "link",
                description: "It may have been cut short when it was copied. Ask for it to be sent again."
            )
        case .newerVersion:
            EmptyStateView(
                title: "Update Splt", systemImage: "arrow.down.circle",
                description: "This was sent from a newer balance page than this version of Splt reads. Update Splt and open the link again."
            )
        case .otherPhone(let groupName):
            EmptyStateView(
                title: "Open This on the Other iPhone", systemImage: "iphone",
                description: "This answers a balance link for \(groupName) that was shared from another iPhone, or more than six months ago. Only the iPhone that shared the link can add it."
            )
        case .groupMissing(let groupName):
            EmptyStateView(
                title: "Group Not Found", systemImage: "questionmark.circle",
                description: "\(groupName) isn't on this iPhone anymore."
            )
        case .unknownPerson:
            EmptyStateView(
                title: "This Link Doesn't Open", systemImage: "link",
                description: "It names someone the balance link didn't. Ask for it to be sent again."
            )
        case .personMissing(let name, let groupName):
            EmptyStateView(
                title: "Someone Is Missing", systemImage: "person.crop.circle.badge.questionmark",
                description: "\(name) isn't in \(groupName) anymore, so this can't be added."
            )
        case .personLeft(let name, let groupName):
            EmptyStateView(
                title: "Someone Left", systemImage: "person.crop.circle.badge.minus",
                description: "\(name) has left \(groupName), so this can't be added."
            )
        case .cannotSplit:
            EmptyStateView(
                title: "This Can't Be Split", systemImage: "divide",
                description: "The amount doesn't divide between these people. Ask for it to be sent again."
            )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
