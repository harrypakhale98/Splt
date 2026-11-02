import Foundation
import Observation
import SpltCore
import SwiftData

/// Everything the group screen shows, loaded from the repositories and kept current as the data changes.
@MainActor
@Observable
final class GroupDetailViewModel {
    enum Segment: String, CaseIterable, Identifiable, Sendable {
        case expenses
        case balances
        case totals

        var id: String { rawValue }

        var title: String {
            switch self {
            case .expenses: String(localized: "Expenses")
            case .balances: String(localized: "Balances")
            case .totals: String(localized: "Totals")
            }
        }
    }

    let groupID: GroupID
    var segment: Segment = .expenses
    var filter = ExpenseFilter()
    var errorMessage: String?

    private(set) var group: SplitGroup?
    private(set) var me: Person?
    private(set) var members: [Person] = []
    private(set) var peopleByID: [PersonID: Person] = [:]
    /// Live expenses, newest first.
    private(set) var expenses: [Expense] = []
    private(set) var balances: GroupBalances?
    private(set) var activity: [ActivityEntry] = []
    private(set) var didLoad = false

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let expenseRepository: any ExpenseRepository
    @ObservationIgnored private let activityRepository: any ActivityRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var memo = Memo()

    /// Work that depends only on the loaded data, kept until the next refresh so a screen that reads
    /// it again while it redraws does not repeat it for thousands of expenses.
    private struct Memo {
        struct SectionsKey: Equatable {
            var revision: Int
            var filter: ExpenseFilter
            var grouping: ExpenseGrouping
        }

        var totalsRevision = -1
        var totals: [GroupTotals] = []
        var recapRevision = -1
        var recap: TripRecap?
        var sectionsKey: SectionsKey?
        var sections: [ExpenseSection] = []
    }

    init(
        groupID: GroupID,
        services: DataServices,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.groupID = groupID
        groups = services.groups
        people = services.people
        expenseRepository = services.expenses
        activityRepository = services.activity
        self.now = now
        self.calendar = calendar
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    func refresh() {
        revision += 1
        do {
            guard let loaded = try groups.group(id: groupID) else {
                group = nil
                didLoad = true
                return
            }
            group = loaded
            me = try people.me()
            peopleByID = Dictionary(try people.allPeople().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            members = loaded.memberIDs.compactMap { peopleByID[$0] }
            expenses = try expenseRepository.expenses(in: groupID, includeDeleted: false)
            balances = try groups.balances(for: groupID)
            activity = try activityRepository.entries(in: groupID, limit: 100)
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
        didLoad = true
    }

    // MARK: Names

    var names: [PersonID: String] {
        peopleByID.mapValues(\.name)
    }

    func name(of id: PersonID) -> String {
        if id == me?.id { return String(localized: "You") }
        return peopleByID[id]?.name ?? String(localized: "Someone")
    }

    // MARK: Header

    /// Your balance, one line per currency. Empty when you are square.
    var myBalance: [BalanceLine] {
        guard let me, let balances else { return [] }
        return BalanceLine.lines(for: balances.net(for: me.id))
    }

    var myTotals: BalanceTotals {
        BalanceTotals(amounts: myBalance.map(\.money))
    }

    var isSettled: Bool {
        balances?.isSettled ?? true
    }

    // MARK: Expenses

    var grouping: ExpenseGrouping {
        group?.kind == .trip ? .day : .month
    }

    var visibleExpenses: [Expense] {
        filter.apply(to: expenses, names: names, now: now(), calendar: calendar)
    }

    var sections: [ExpenseSection] {
        let key = Memo.SectionsKey(revision: revision, filter: filter, grouping: grouping)
        _ = expenses
        if memo.sectionsKey == key { return memo.sections }
        let built = ExpenseSectioning.sections(visibleExpenses, grouping: grouping, calendar: calendar)
        memo.sectionsKey = key
        memo.sections = built
        return built
    }

    func sectionTitle(_ section: ExpenseSection, locale: Locale) -> String {
        ExpenseSectioning.title(
            for: section, grouping: grouping, tripStart: group?.tripStart, calendar: calendar, locale: locale
        )
    }

    /// People who paid for at least one expense, for the payer filter.
    var payers: [Person] {
        let ids = Set(expenses.flatMap { $0.payers.keys })
        return ids.compactMap { peopleByID[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Categories in use, for the category filter.
    var categories: [ExpenseCategory] {
        Set(expenses.map(\.category)).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The numbers for the recap story, or nil when nothing was spent in the group's currency.
    var recapStats: RecapStats? {
        group.flatMap { RecapStats(group: $0, expenses: expenses, names: names, now: now(), calendar: calendar) }
    }

    var recap: TripRecap? {
        _ = expenses
        if memo.recapRevision == revision { return memo.recap }
        let built = group.flatMap { TripRecap(group: $0, expenses: expenses, now: now(), calendar: calendar) }
        memo.recapRevision = revision
        memo.recap = built
        return built
    }

    // MARK: Balances

    var simplifiesDebts: Bool {
        group?.simplifiesDebts ?? true
    }

    /// The payments that would settle the group, in the way the group settles.
    var transfers: [Debt] {
        balances?.suggestedSettlements ?? []
    }

    /// Everyone's net position, largest owed first. Positive means the person is owed.
    var netRows: [NetBalanceRow] {
        guard let balances else { return [] }
        let rows = members.map { NetBalanceRow(person: $0, amounts: BalanceLine.lines(for: balances.net(for: $0.id)).map(\.money)) }
        return rows.sorted { lhs, rhs in
            let left = lhs.amounts.first?.minorUnits ?? 0, right = rhs.amounts.first?.minorUnits ?? 0
            return left != right ? left > right : lhs.person.name.localizedStandardCompare(rhs.person.name) == .orderedAscending
        }
    }

    /// Currencies that have payments to make, or the group's own when everyone is square.
    var balanceCurrencies: [String] {
        let codes = Set(transfers.map(\.amount.currencyCode))
        guard !codes.isEmpty else { return [group?.currencyCode ?? "USD"] }
        return codes.sorted { lhs, rhs in
            if lhs == group?.currencyCode { return true }
            if rhs == group?.currencyCode { return false }
            return lhs < rhs
        }
    }

    /// The ring for one currency: everyone in the group and the payments in that currency.
    func orbitBoard(currency: String) -> OrbitBoard {
        OrbitBoard(
            members: members,
            me: me?.id,
            nets: balances?.netBalances[currency] ?? [:],
            debts: transfers,
            currencyCode: currency,
            extraPeople: peopleByID
        )
    }

    func setSimplifiesDebts(_ value: Bool) {
        guard var group, group.simplifiesDebts != value else { return }
        group.simplifiesDebts = value
        perform { try groups.update(group) }
    }

    func settleRoute(for debt: Debt? = nil) -> SettleRoute? {
        let debts = debt.map { [$0] } ?? transfers
        guard !debts.isEmpty else { return nil }
        return SettleRoute(groupID: groupID, debts: debts)
    }

    // MARK: Totals

    var totals: [GroupTotals] {
        _ = expenses
        if memo.totalsRevision == revision { return memo.totals }
        let built = GroupTotals.make(expenses: expenses, names: names)
        memo.totalsRevision = revision
        memo.totals = built
        return built
    }

    /// The totals in the group's own currency, or the biggest one when that has no spending.
    var primaryTotals: GroupTotals? {
        let all = totals
        return all.first { $0.currencyCode == group?.currencyCode } ?? all.first
    }

    /// The facts for the on-device summary, read off the group's main currency. Nil when nothing was spent.
    var insightInput: InsightInput? {
        guard let group, let totals = primaryTotals else { return nil }
        return totals.insightInput(groupName: group.name, kind: group.kind)
    }

    // MARK: Activity

    var activityText: GroupActivityText {
        GroupActivityText(currentPerson: me?.id, names: names)
    }

    // MARK: Changes

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
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

/// One member's net position in the group.
struct NetBalanceRow: Identifiable, Equatable {
    var person: Person
    /// Positive means the person is owed. Empty when square.
    var amounts: [Money]

    var id: PersonID { person.id }
    var isSettled: Bool { amounts.isEmpty }
}
