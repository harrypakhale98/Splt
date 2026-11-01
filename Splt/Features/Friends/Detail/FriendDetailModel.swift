import Foundation
import Observation
import SpltCore

/// One friend: what is owed in each currency and group, the expenses you share and the payments between you.
@MainActor
@Observable
final class FriendDetailModel {
    struct GroupRow: Identifiable, Equatable {
        var groupID: GroupID
        var name: String
        var amounts: [Money]

        var id: GroupID { groupID }
    }

    let friendID: PersonID
    var errorMessage: String?

    private(set) var friend: Person?
    private(set) var me: Person?
    private(set) var balance: [Money] = []
    private(set) var groupRows: [GroupRow] = []
    private(set) var legs: [SettleLeg] = []
    /// Live expenses that you and the friend both take part in, newest first.
    private(set) var expenses: [Expense] = []
    /// Payments between the two of you, newest first. Undone ones stay in the list.
    private(set) var payments: [Payment] = []
    private(set) var people: [PersonID: Person] = [:]
    private(set) var groupNames: [GroupID: String] = [:]
    private(set) var didLoad = false

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    init(friendID: PersonID, services: DataServices) {
        self.friendID = friendID
        self.services = services
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    func refresh() {
        do {
            friend = try services.people.person(id: friendID)
            me = try services.people.me()
            people = Dictionary(try services.people.allPeople().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let allGroups = try services.groups.groups(includeArchived: true)
            let byID = Dictionary(allGroups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            groupNames = byID.mapValues(SettleLeg.displayName(of:))
            let summary = try services.people.friendBalance(with: friendID)
            balance = summary.total
            groupRows = summary.byGroup.map {
                GroupRow(groupID: $0.groupID, name: groupNames[$0.groupID] ?? String(localized: "Group"), amounts: $0.amounts)
            }
            legs = me.map { SettleLeg.make(from: summary.byGroup, friend: friendID, me: $0.id, groups: byID) } ?? []
            expenses = try services.expenses.sharedExpenses(with: friendID).filter { !$0.isDeleted }
            payments = try loadPayments(in: allGroups)
        } catch {
            errorMessage = SettleErrorMessage.text(for: error)
        }
        didLoad = true
    }

    private func loadPayments(in groups: [SplitGroup]) throws -> [Payment] {
        guard let me else { return [] }
        let pair: Set<PersonID> = [me.id, friendID]
        var found: [Payment] = []
        for group in groups where pair.isSubset(of: group.memberIDs) {
            found += try services.payments.payments(in: group.id, includeDeleted: true)
                .filter { Set([$0.payer, $0.receiver]) == pair }
        }
        return found.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    // MARK: Balance

    var balanceLines: [BalanceLine] { BalanceLine.lines(for: balance) }
    var isSettled: Bool { balance.isEmpty }
    var owedToYou: [Money] { balance.filter(\.isPositive) }

    var settleRequest: SettleRequest? {
        guard let friend, !legs.isEmpty else { return nil }
        return SettleRequest(friendName: friend.name, legs: legs)
    }

    var groupNamesOwedToYou: [String] {
        var seen = Set<String>()
        return legs.filter { !$0.youOwe }.map(\.groupName).filter { seen.insert($0).inserted }
    }

    func name(of id: PersonID) -> String {
        if id == me?.id { return String(localized: "You") }
        return people[id]?.name ?? String(localized: "Someone")
    }

    // MARK: Changes

    /// The group a new expense with this friend goes into.
    func expenseGroup() -> GroupID? {
        do {
            return try DirectGroupResolver.group(with: friendID, services: services)
        } catch {
            errorMessage = SettleErrorMessage.text(for: error)
            return nil
        }
    }

    func rename(to name: String) {
        let trimmed = name.tidied
        guard var friend, !trimmed.isEmpty, trimmed != friend.name else { return }
        friend.name = trimmed
        perform { try services.people.update(friend) }
    }

    func undo(_ payment: Payment) {
        perform { try services.payments.undo(id: payment.id) }
    }

    func restore(_ payment: Payment) {
        perform { try services.payments.restore(id: payment.id) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = SettleErrorMessage.text(for: error)
        }
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }
}
