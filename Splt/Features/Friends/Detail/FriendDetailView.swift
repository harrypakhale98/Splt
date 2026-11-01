import SpltCore
import SwiftUI

/// One friend: balance, settle up, add expense, the groups behind the balance and what you share.
/// Pushed with `Route.friend`.
struct FriendDetailView: View {
    let friendID: PersonID

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            FriendDetailContent(friendID: friendID, services: services)
        } else {
            EmptyStateView(
                title: "Friend Not Found",
                systemImage: "person.2",
                description: "Splt couldn't open its storage."
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ExpenseTarget: Identifiable {
    let groupID: GroupID
    var id: GroupID { groupID }
}

private struct FriendDetailContent: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.placeholderMerger) private var merger
    @Environment(\.dataServices) private var services

    @State private var model: FriendDetailModel
    @State private var settleRequest: SettleRequest?
    @State private var expenseTarget: ExpenseTarget?
    @State private var showsRemind = false
    @State private var showsRename = false
    @State private var showsMerge = false
    @State private var newName = ""
    private let visibility = FriendVisibilityStore()

    init(friendID: PersonID, services: DataServices) {
        _model = State(initialValue: FriendDetailModel(friendID: friendID, services: services))
    }

    var body: some View {
        Group {
            if let friend = model.friend {
                List {
                    header(friend)
                    actions(friend)
                    groupBreakdown
                    sharedExpenses
                    paymentHistory
                }
                .navigationTitle(friend.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(friend) }
            } else if model.didLoad {
                EmptyStateView(
                    title: "Friend Not Found",
                    systemImage: "person.2",
                    description: "This person may have been removed."
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .settleFlow($settleRequest)
        .sheet(item: $expenseTarget) { target in
            ExpenseFormView(mode: .add(groupID: target.groupID, prefill: nil))
        }
        .sheet(isPresented: $showsRemind) {
            if let friend = model.friend {
                RemindSheet(friend: friend, owed: model.owedToYou, groupNames: model.groupNamesOwedToYou)
            }
        }
        .sheet(isPresented: $showsMerge) {
            if let friend = model.friend, let merger, let services {
                MergeFriendView(placeholder: friend, services: services, merger: merger) { target in
                    router.friendsPath = [.friend(target.id.rawValue)]
                }
            }
        }
        .alert("Rename", isPresented: $showsRename) {
            TextField("Name", text: $newName)
            Button("Save") { model.rename(to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear(perform: openPendingSettle)
        .onChange(of: model.didLoad) { openPendingSettle() }
    }

    // MARK: Sections

    private func header(_ friend: Person) -> some View {
        Section {
            VStack(spacing: 10) {
                AvatarView(name: friend.name, size: 72)
                Text(friend.name)
                    .font(.title2.bold())
                if friend.isPlaceholder {
                    Text("Not on Splt yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                balanceSummary
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var balanceSummary: some View {
        let lines = model.balanceLines
        if lines.isEmpty {
            Label("Settled up", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(lines) { line in
                    HStack(spacing: 6) {
                        Text(line.direction == .owed ? "Owes you" : "You owe")
                            .foregroundStyle(.secondary)
                        MoneyLabel(money: line.money, style: .balance)
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func actions(_ friend: Person) -> some View {
        Section {
            if model.settleRequest != nil {
                Button {
                    settleRequest = model.settleRequest
                } label: {
                    Label("Settle Up", systemImage: "checkmark.circle")
                }
            }
            if !model.owedToYou.isEmpty {
                Button {
                    showsRemind = true
                } label: {
                    Label("Remind \(ReminderMessage.firstName(friend.name))", systemImage: "bell")
                }
            }
            Button {
                expenseTarget = model.expenseGroup().map(ExpenseTarget.init)
            } label: {
                Label("Add Expense", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var groupBreakdown: some View {
        if !model.groupRows.isEmpty {
            Section("By Group") {
                ForEach(model.groupRows) { row in
                    NavigationLink(value: Route.group(row.groupID.rawValue)) {
                        HStack {
                            Text(row.name)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing) {
                                ForEach(row.amounts, id: \.currencyCode) { amount in
                                    MoneyLabel(money: amount, style: .balance)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sharedExpenses: some View {
        Section("Shared Expenses") {
            if model.expenses.isEmpty {
                Text("Nothing shared yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.expenses) { expense in
                    NavigationLink(value: Route.expense(expense.id.rawValue)) {
                        ExpenseRowView(expense: expense, currentPerson: model.me?.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paymentHistory: some View {
        if !model.payments.isEmpty {
            Section("Payments") {
                ForEach(model.payments) { payment in
                    PaymentRow(payment: payment, model: model)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ friend: Person) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Expense", systemImage: "plus") {
                expenseTarget = model.expenseGroup().map(ExpenseTarget.init)
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Rename", systemImage: "pencil") {
                newName = friend.name
                showsRename = true
            }
        }
        if friend.isPlaceholder, merger != nil {
            ToolbarItem(placement: .secondaryAction) {
                Button("Merge With\u{2026}", systemImage: "person.2.badge.gearshape") { showsMerge = true }
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Hide", systemImage: "eye.slash") {
                visibility.set(.hidden, for: friend.id)
                dismiss()
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Block", systemImage: "nosign", role: .destructive) {
                visibility.set(.blocked, for: friend.id)
                dismiss()
            }
        }
    }

    // MARK: Helpers

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private func openPendingSettle() {
        guard router.pendingSettleFriend == model.friendID.rawValue, model.didLoad else { return }
        router.pendingSettleFriend = nil
        settleRequest = model.settleRequest
    }
}

private struct PaymentRow: View {
    let payment: Payment
    let model: FriendDetailModel

    @Environment(\.locale) private var locale

    var body: some View {
        let isUndone = payment.isDeleted
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(sentence)
                    .strikethrough(isUndone)
                Spacer(minLength: 8)
                MoneyLabel(money: payment.amount)
                    .strikethrough(isUndone)
            }
            HStack(spacing: 6) {
                Text(payment.date, format: .dateTime.day().month().year())
                if !payment.note.isEmpty {
                    Text(payment.note)
                }
                if isUndone {
                    Text("Undone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(isUndone ? .secondary : .primary)
        .accessibilityElement(children: .combine)
        .swipeActions {
            if isUndone {
                Button("Restore", systemImage: "arrow.uturn.forward") { model.restore(payment) }
                    .tint(.green)
            } else {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo(payment) }
                    .tint(.orange)
            }
        }
    }

    private var sentence: String {
        let payer = model.name(of: payment.payer), receiver = model.name(of: payment.receiver)
        if payment.payer == model.me?.id { return String(localized: "You paid \(receiver)") }
        if payment.receiver == model.me?.id { return String(localized: "\(payer) paid you") }
        return String(localized: "\(payer) paid \(receiver)")
    }
}

#if DEBUG
#Preview("Owes you") {
    let services = SampleData.previewServices()
    let maya = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000011")!)
    NavigationStack { FriendDetailView(friendID: maya) }
        .environment(Router())
        .environment(\.dataServices, services)
}

#Preview("Large text") {
    let services = SampleData.previewServices()
    let priya = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000013")!)
    NavigationStack { FriendDetailView(friendID: priya) }
        .environment(Router())
        .environment(\.dataServices, services)
        .dynamicTypeSize(.accessibility3)
}
#endif
