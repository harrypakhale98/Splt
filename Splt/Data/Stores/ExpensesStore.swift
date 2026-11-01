import Foundation
import Observation
import SpltCore
import SwiftData

/// The expenses of one group or one friendship, newest first, for the detail screens.
@MainActor
@Observable
final class ExpensesStore {
    enum Scope: Hashable, Sendable {
        case group(GroupID)
        case friend(PersonID)
    }

    private(set) var scope: Scope?
    private(set) var rows: [ExpenseRow] = []
    private(set) var didFailToLoad = false

    @ObservationIgnored private let expenses: any ExpenseRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    init(expenses: any ExpenseRepository, people: any PersonRepository, container: ModelContainer? = nil) {
        self.expenses = expenses
        self.people = people
        if let container {
            observer = ContainerChangeObserver(container: container) { [weak self] in self?.scheduleRefresh() }
        }
    }

    func load(group: GroupID) {
        scope = .group(group)
        refresh()
    }

    func load(friend: PersonID) {
        scope = .friend(friend)
        refresh()
    }

    func refresh() {
        guard let scope else {
            rows = []
            return
        }
        do {
            let loaded: [Expense]
            switch scope {
            case .group(let group): loaded = try expenses.expenses(in: group, includeDeleted: true)
            case .friend(let friend): loaded = try expenses.sharedExpenses(with: friend)
            }
            let me = try people.me()?.id
            let everyone = Dictionary(
                try people.allPeople().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            rows = loaded.map { Self.row(for: $0, me: me, people: everyone) }
            didFailToLoad = false
        } catch {
            didFailToLoad = true
        }
    }

    func add(_ expense: Expense, extras: ExpenseExtras = ExpenseExtras()) throws {
        try expenses.add(expense, extras: extras)
        refresh()
    }

    func update(_ expense: Expense, extras: ExpenseExtras? = nil) throws {
        try expenses.update(expense, extras: extras)
        refresh()
    }

    func delete(_ id: ExpenseID) throws {
        try expenses.delete(id: id)
        refresh()
    }

    func restore(_ id: ExpenseID) throws {
        try expenses.restore(id: id)
        refresh()
    }

    /// Other expenses that look like `expense`, to warn before saving a duplicate.
    func possibleDuplicates(of expense: Expense) -> [Expense] {
        (try? expenses.duplicates(of: expense, withinDays: 3)) ?? []
    }

    private static func row(for expense: Expense, me: PersonID?, people: [PersonID: Person]) -> ExpenseRow {
        let payers = expense.payers.keys.sorted().compactMap { people[$0] }
        var myNet: Money?
        if let me, expense.participants.contains(me), let nets = try? expense.netBalances() {
            myNet = nets[me] ?? .zero(currencyCode: expense.total.currencyCode)
        }
        return ExpenseRow(
            expense: expense, payers: payers, paidByMe: me.map { expense.payers.keys.contains($0) } ?? false,
            myNet: myNet
        )
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
