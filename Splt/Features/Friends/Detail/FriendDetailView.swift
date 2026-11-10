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
            EmptyStateView.dataUnavailable
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
    @Environment(\.dataServices) private var services

    @State private var model: FriendDetailModel
    @State private var settleRequest: SettleRequest?
    @State private var expenseTarget: ExpenseTarget?
    @State private var showsRemind = false
    @State private var showsRename = false
    @State private var showsMerge = false
    @State private var showsBlockConfirmation = false
    @State private var newName = ""
    private let visibility = FriendVisibilityStore()

    init(friendID: PersonID, services: DataServices) {
        _model = State(initialValue: FriendDetailModel(friendID: friendID, services: services))
    }

    var body: some View {
        Group {
            if let friend = model.friend {
                List {
                    hero(friend)
                    groupBreakdown
                    timeline
                    paymentHistory
                }
                .listStyle(.plain)
                .listRowSeparatorTint(Ink.hairline)
                .paperBackground()
                .navigationTitle(friend.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(friend) }
            } else if model.didLoad {
                EmptyStateView(
                    title: "Friend not found",
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
            if let friend = model.friend, let services {
                MergeFriendView(placeholder: friend, services: services, merger: LivePlaceholderMerger(services: services)) { target in
                    router.friendsPath = [.friend(target.id.rawValue)]
                }
            }
        }
        .closingSheetsOnLink {
            expenseTarget = nil
            showsRemind = false
            showsMerge = false
        }
        .alert("Rename", isPresented: $showsRename) {
            TextField("Name", text: $newName)
            Button("Save") { model.rename(to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block \(firstName)?",
            isPresented: $showsBlockConfirmation, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { setVisibility(.blocked) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They stay out of your friends, search and reminders on this device.")
        }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear(perform: openPendingSettle)
        .onChange(of: model.didLoad) { openPendingSettle() }
        .onChange(of: router.pendingSettleFriend) { openPendingSettle() }
    }

    // MARK: Sections

    private func hero(_ friend: Person) -> some View {
        Section {
            FriendHero(
                friend: friend, balance: model.balance, canSettle: model.settleRequest != nil,
                onSettle: { settleRequest = model.settleRequest },
                onAdd: { expenseTarget = model.expenseGroup().map(ExpenseTarget.init) }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var groupBreakdown: some View {
        if !model.groupRows.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.groupRows) { row in
                        NavigationLink(value: Route.group(row.groupID.rawValue)) {
                            HStack {
                                Text(row.name)
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing) {
                                    ForEach(row.amounts, id: \.currencyCode) { amount in
                                        BalanceFigure(money: amount)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } header: {
                SectionHeader("By group")
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if model.expenses.isEmpty {
            Section {
                Text("Nothing shared yet.")
                    .foregroundStyle(Ink.secondary)
                    .raisedRow()
            } header: {
                SectionHeader("Shared expenses")
            }
        } else {
            ForEach(model.timeline) { month in
                Section {
                    RaisedRows {
                        ForEach(month.expenses, id: \.id) { expense in
                            NavigationLink(value: Route.expense(expense.id.rawValue)) {
                                FriendTimelineRow(
                                    expense: expense, payerName: model.payerText(for: expense),
                                    myNet: model.myNet(in: expense)
                                )
                            }
                        }
                    }
                } header: {
                    Text(month.start, format: .dateTime.month(.wide).year()).sectionHeaderStyle()
                }
            }
        }
    }

    @ViewBuilder
    private var paymentHistory: some View {
        if !model.payments.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.payments) { payment in
                        PaymentRow(payment: payment, model: model)
                    }
                }
            } header: {
                SectionHeader("Payments")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ friend: Person) -> some ToolbarContent {
        if !model.owedToYou.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Button("Remind \(ReminderMessage.firstName(friend.name))", systemImage: "bell") { showsRemind = true }
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Rename", systemImage: "pencil") {
                newName = friend.name
                showsRename = true
            }
        }
        if friend.isPlaceholder {
            ToolbarItem(placement: .secondaryAction) {
                Button("Merge With\u{2026}", systemImage: "person.2.badge.gearshape") { showsMerge = true }
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Hide", systemImage: "eye.slash") { setVisibility(.hidden) }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Block\u{2026}", systemImage: "nosign", role: .destructive) { showsBlockConfirmation = true }
        }
    }

    // MARK: Helpers

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var firstName: String {
        model.friend.map { ReminderMessage.firstName($0.name) } ?? ""
    }

    /// The store tells the Friends list, which refreshes before this screen finishes closing.
    private func setVisibility(_ state: FriendVisibilityStore.State) {
        visibility.set(state, for: model.friendID)
        dismiss()
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
                Text(MoneyFormatting.magnitudeString(payment.amount, locale: locale))
                    .font(Typeface.figure)
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
            .font(.footnote)
            .foregroundStyle(Ink.secondary)
        }
        .foregroundStyle(isUndone ? Ink.secondary : Ink.text)
        .accessibilityElement(children: .combine)
        .swipeActions {
            if isUndone {
                Button("Restore Payment", systemImage: "arrow.uturn.forward") { model.restore(payment) }
                    .tint(Ink.text)
            } else {
                Button("Undo Payment", systemImage: "arrow.uturn.backward") { model.undo(payment) }
                    .tint(Ink.owe)
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

/// An amount in a row with a sign and a word, so direction never rests on color.
private struct BalanceFigure: View {
    let money: Money

    @Environment(\.locale) private var locale

    var body: some View {
        Text(MoneyFormatting.string(money, locale: locale, showsSign: true))
            .font(Typeface.figure)
            .foregroundStyle(Ink.direction(of: money.minorUnits))
            .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let amount = MoneyFormatting.magnitudeString(money, locale: locale)
        return money.isPositive ? String(localized: "owes you \(amount)") : String(localized: "you owe \(amount)")
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
