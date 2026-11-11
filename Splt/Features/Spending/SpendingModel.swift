import Foundation
import Observation
import SpltCore

/// Your share of everything, in every group and with every friend, in your default currency.
///
/// Each expense in another currency is converted at the reference rate published for its day,
/// or at its group's pinned rate when that covers the pair. Rates are looked up in the background
/// and cached for good. An amount with no rate is never given one: it stays in its own currency,
/// outside the total, and the screen says so.
@MainActor
@Observable
final class SpendingModel {
    struct Row: Identifiable, Equatable {
        var id: GroupID
        var label: String
        var share: Money
        /// The friend a friend row stands for.
        var friend: PersonID?
    }

    var range: SpendingRange {
        didSet {
            guard range != oldValue else { return }
            rebuild()
            loadRates()
        }
    }

    private(set) var summary = SpendingSummary(months: [], buckets: [])
    private(set) var currencyCode: String
    private(set) var groups: [GroupID: SplitGroup] = [:]
    private(set) var isLoadingRates = false
    private(set) var didLoad = false

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let leftGroups: LeftGroupsStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var me: PersonID?
    @ObservationIgnored private var names: [PersonID: String] = [:]
    @ObservationIgnored private var expenses: [Expense] = []
    /// Rate tables against `currencyCode`, by day as `yyyy-MM-dd`. Today's and later use `latestKey`.
    @ObservationIgnored private var tables: [String: RateTable] = [:]
    @ObservationIgnored private var tried: Set<String> = []
    @ObservationIgnored private var ratesTask: Task<Void, Never>?
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    private static let latestKey = "latest"

    init(
        services: DataServices,
        range: SpendingRange = .last12Months,
        defaults: UserDefaults = .standard,
        leftGroups: LeftGroupsStore = LeftGroupsStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.services = services
        self.range = range
        self.defaults = defaults
        self.leftGroups = leftGroups
        self.now = now
        self.calendar = calendar
        currencyCode = Self.defaultCurrency(in: defaults)
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    func refresh() {
        let code = Self.defaultCurrency(in: defaults)
        if code != currencyCode {
            currencyCode = code
            tables = [:]
            tried = []
        }
        me = try? services.people.me()?.id
        names = Dictionary(
            ((try? services.people.allPeople()) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let all = (try? services.groups.groups(includeArchived: true)) ?? []
        let kept = all.filter { !leftGroups.contains($0.id) }
        groups = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        expenses = kept.flatMap { (try? services.expenses.expenses(in: $0.id, includeDeleted: false)) ?? [] }
        rebuild()
        didLoad = true
        loadRates()
    }

    /// Waits for any rate lookups under way, for tests.
    func ratesLoaded() async {
        await ratesTask?.value
    }

    // MARK: Reading

    /// Your share in the default currency.
    var share: Money {
        summary.buckets.first?.shareMoney ?? .zero(currencyCode: currencyCode)
    }

    var bucket: SpendingSummary.Bucket? { summary.buckets.first }

    /// Your share per group, largest first, without the hidden groups behind friends.
    var groupRows: [Row] {
        rows { $0.kind != .friend }
    }

    /// Your share with each friend outside any group, largest first.
    var friendRows: [Row] {
        rows { $0.kind == .friend }
    }

    var groupCount: Int {
        summary.yourGroups.filter { groups[$0].map { $0.kind != .friend } ?? false }.count
    }

    var friendCount: Int {
        summary.yourGroups.filter { groups[$0]?.kind == .friend }.count
    }

    /// Amounts in other currencies that are in the total, in their own currency, largest first.
    var convertedAmounts: [Money] {
        Self.amounts(summary.converted)
    }

    /// Amounts with no rate, kept out of the total.
    var notConvertedAmounts: [Money] {
        Self.amounts(summary.notConverted)
    }

    /// Each group whose expenses were converted, with the currencies, as "Lisbon trip" and ["EUR"].
    var convertedGroups: [(name: String, currencies: [String])] {
        summary.convertedByGroup
            .compactMap { id, codes in
                guard let group = groups[id] else { return nil }
                return (label(for: group), codes.sorted())
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// True when a group's pinned rate was used for something converted, rather than the day's rate.
    var usedPinnedRate: Bool {
        summary.convertedByGroup.contains { id, codes in
            guard let pinned = groups[id]?.pinnedRate else { return false }
            return codes.contains { Self.covers(pinned, $0, currencyCode) }
        }
    }

    // MARK: Building

    private func rebuild() {
        let target = currencyCode
        let today = Self.today(now())
        let convert = SpendingSummary.converter(into: target) { [tables, groups] expense in
            let day = RatesService.dayString(expense.date, timeZone: .current)
            // today's and later expenses take the latest rates, which are today's
            let table = day >= today ? tables[Self.latestKey] : tables[day]
            let pinned = expense.groupID.flatMap { groups[$0]?.pinnedRate }
            return RatesService.exchangeRates(table: table, pinned: pinned)
        }
        summary = SpendingSummary.make(
            expenses: expenses, me: me, range: range, now: now(), calendar: calendar, target: target, convert: convert
        )
    }

    /// Looks up the rates still missing for the expenses in range, then builds again.
    private func loadRates() {
        let target = currencyCode
        let today = Self.today(now())
        let window = range.dateRange(now: now(), calendar: calendar)
        var wanted: [String: Date] = [:]
        for expense in expenses where expense.total.currencyCode != target && !expense.isDeleted {
            if let window, !window.contains(expense.date) { continue }
            // only your share is shown, so an expense you have no part in needs no rate
            guard let me, expense.split.participants.contains(me) else { continue }
            if let pinned = expense.groupID.flatMap({ groups[$0]?.pinnedRate }),
               Self.covers(pinned, expense.total.currencyCode, target) { continue }
            let day = RatesService.dayString(expense.date, timeZone: .current)
            let key = day >= today ? Self.latestKey : day
            if tables[key] == nil, !tried.contains(key) { wanted[key] = expense.date }
        }
        ratesTask?.cancel()
        guard !wanted.isEmpty else {
            isLoadingRates = false
            return
        }
        isLoadingRates = true
        let rates = services.rates
        ratesTask = Task { [weak self] in
            for (key, date) in wanted.sorted(by: { $0.key < $1.key }) {
                if Task.isCancelled { return }
                let table = key == Self.latestKey
                    ? await rates.latestTable(base: target)
                    : await rates.historicalTable(base: target, on: date)
                guard let self, self.currencyCode == target else { return }
                self.tried.insert(key)
                if let table { self.tables[key] = table }
            }
            guard let self else { return }
            self.isLoadingRates = false
            self.rebuild()
        }
    }

    private func rows(where include: (SplitGroup) -> Bool) -> [Row] {
        guard let bucket else { return [] }
        return bucket.groups.compactMap { id, share -> Row? in
            guard share != 0, let group = groups[id], include(group) else { return nil }
            return Row(
                id: id, label: label(for: group), share: Money(minorUnits: share, currencyCode: bucket.currencyCode),
                friend: friend(in: group)
            )
        }
        .sorted { lhs, rhs in
            lhs.share.minorUnits != rhs.share.minorUnits
                ? lhs.share.minorUnits > rhs.share.minorUnits
                : lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    private func friend(in group: SplitGroup) -> PersonID? {
        guard group.kind == .friend else { return nil }
        return group.memberIDs.first { $0 != me }
    }

    /// A group's name, or for the hidden group behind a friend, the friend's.
    private func label(for group: SplitGroup) -> String {
        if let friend = friend(in: group) { return names[friend] ?? group.name }
        return group.name
    }

    private static func amounts(_ byCode: [String: Int64]) -> [Money] {
        byCode.filter { $0.value != 0 }
            .map { Money(minorUnits: $0.value, currencyCode: $0.key) }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    private static func covers(_ pinned: PinnedRate, _ first: String, _ second: String) -> Bool {
        let a = first.uppercased(), b = second.uppercased()
        return (pinned.from == a && pinned.to == b) || (pinned.from == b && pinned.to == a)
    }

    private static func today(_ now: Date) -> String {
        RatesService.dayString(now, timeZone: .current)
    }

    static func defaultCurrency(in defaults: UserDefaults) -> String {
        defaults.string(forKey: Preferences.Key.defaultCurrency) ?? Preferences.systemCurrencyCode
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
