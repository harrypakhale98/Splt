import Foundation
import Observation
import SpltCore

/// People, groups and expenses that match what was typed, including questions in plain language.
@MainActor
@Observable
final class SearchModel {
    var query = ""

    private(set) var people: [Person] = []
    private(set) var groups: [SplitGroup] = []
    private(set) var expenses: [Expense] = []
    /// What the question was read as, when it was more than plain words. Empty otherwise.
    private(set) var understood: [String] = []
    private(set) var recents: [String] = []
    private(set) var me: Person?
    private(set) var peopleByID: [PersonID: Person] = [:]
    /// Everyone known, for naming payers in expense rows. Built once per search, not per row.
    private(set) var knownPeople: [Person] = []
    private(set) var hasSearched = false

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let recentStore: RecentSearchesStore
    @ObservationIgnored private let visibility: FriendVisibilityStore
    @ObservationIgnored private let leftGroups: LeftGroupsStore
    @ObservationIgnored private let reader: any SearchIntentReader
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false
    /// How the model read the current question, kept so a refresh does not have to ask it again.
    @ObservationIgnored private var modelReading: (text: String, filter: SearchFilter)?

    static let resultLimit = 40

    /// Questions that show what the search understands.
    static let examples = [
        String(localized: "dinners paid last month"),
        String(localized: "rent over 500"),
        String(localized: "coffee this week")
    ]

    init(
        services: DataServices,
        recentStore: RecentSearchesStore = RecentSearchesStore(),
        visibility: FriendVisibilityStore = FriendVisibilityStore(),
        leftGroups: LeftGroupsStore = LeftGroupsStore(),
        reader: any SearchIntentReader = FoundationModelsSearchReader(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.services = services
        self.recentStore = recentStore
        self.visibility = visibility
        self.leftGroups = leftGroups
        self.reader = reader
        self.now = now
        self.calendar = calendar
        self.locale = locale
        recents = recentStore.queries
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
    }

    var trimmedQuery: String { query.tidied }
    var isEmpty: Bool { people.isEmpty && groups.isEmpty && expenses.isEmpty }

    /// Runs the search for the current text. Plain words answer at once; a question the rules
    /// could not read is offered to the on-device model afterwards, when it is available.
    func search() async {
        let text = trimmedQuery
        modelReading = nil
        guard let known = searchByRules(text) else { return }
        await askModel(text, known: known)
    }

    /// Runs the current search again after the data changed, so a deleted expense or a renamed
    /// person does not linger in the results. The model is not asked again.
    func refresh() {
        let text = trimmedQuery
        guard hasSearched, !text.isEmpty else { return }
        _ = searchByRules(text)
        if let modelReading, modelReading.text == text { apply(modelReading.filter) }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// The part of a search that needs no model. Returns everyone known when the rules could not
    /// read the text as a question, which is when the model may be asked.
    private func searchByRules(_ text: String) -> [Person]? {
        guard !text.isEmpty else {
            clearResults()
            return nil
        }
        do {
            let known = try services.people.allPeople()
            peopleByID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            knownPeople = known
            me = known.first(where: \.isMe)
            // a group you left is still in the shared data, but it is no longer yours to find; it is
            // skipped before the result limit, so its expenses can't crowd out the ones you can open
            let left = Set(try services.groups.groups(includeArchived: true).map(\.id).filter(leftGroups.contains))
            let base = try services.search.search(text, limit: Self.resultLimit, excludingGroups: left)
            let blocked = visibility.ids(in: .blocked)
            people = base.people.filter { !$0.isMe && !blocked.contains($0.id) }
            groups = base.groups.filter { $0.kind != .friend }
            let textMatches = base.expenses
            let filter = NaturalSearchParser(people: known, now: now(), calendar: calendar, locale: locale).parse(text)
            if filter.isStructured {
                apply(filter)
                if expenses.isEmpty, !textMatches.isEmpty {
                    expenses = textMatches
                    understood = []
                }
            } else {
                expenses = textMatches
                understood = []
            }
            hasSearched = true
            return filter.isStructured ? nil : known
        } catch {
            clearResults()
            return nil
        }
    }

    func remember() {
        recentStore.add(trimmedQuery)
        recents = recentStore.queries
    }

    func clearRecents() {
        recentStore.clear()
        recents = []
    }

    // MARK: Questions

    private func askModel(_ text: String, known: [Person]) async {
        guard text.split(whereSeparator: \.isWhitespace).count >= 3, reader.isAvailable else { return }
        let names = known.filter { !$0.isMe }.map(\.name)
        guard let reading = try? await reader.read(text, names: names), trimmedQuery == text else { return }
        let filter = SearchIntentValidator(people: known, now: now(), calendar: calendar).filter(from: reading, query: text)
        guard filter.isStructured else { return }
        modelReading = (text, filter)
        apply(filter)
    }

    private func apply(_ filter: SearchFilter) {
        let allGroups = (try? services.groups.groups(includeArchived: true)) ?? []
        let groupNames = Dictionary(allGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let names = peopleByID.mapValues(\.name)
        let yours = allGroups.filter { !leftGroups.contains($0.id) }
        let scale = SearchFilter.AmountScale(
            currency: filter.amountCurrency ?? amountCurrency(among: yours),
            unitValues: services.rates.snapshot.unitValues()
        )
        var found: [Expense] = []
        for group in yours {
            let inGroup = (try? services.expenses.expenses(in: group.id, includeDeleted: false)) ?? []
            found += inGroup.filter { filter.matches($0, groupName: groupNames[group.id], names: names, scale: scale, locale: locale) }
        }
        expenses = Array(found.sorted { ($0.date, $0.id) > ($1.date, $1.id) }.prefix(Self.resultLimit))
        understood = description(of: filter)
    }

    /// The currency "over 50" means when the question names none: your own, when a group of yours uses it,
    /// else the one most of your groups use.
    private func amountCurrency(among groups: [SplitGroup]) -> String {
        let own = locale.currency?.identifier
        let counts = Dictionary(groups.map { ($0.currencyCode.uppercased(), 1) }, uniquingKeysWith: +)
        if let own, counts[own] != nil { return own }
        let common = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        return common ?? own ?? "USD"
    }

    /// Short phrases saying how the question was read, shown above the results.
    func description(of filter: SearchFilter) -> [String] {
        var parts: [String] = []
        if let category = filter.category { parts.append(category.title) }
        if let payer = filter.payer {
            let name = payer == me?.id ? String(localized: "you") : peopleByID[payer]?.name ?? ""
            parts.append(String(localized: "Paid by \(name)"))
        }
        if let participant = filter.participant, let name = peopleByID[participant]?.name {
            parts.append(String(localized: "With \(name)"))
        }
        if let period = filter.period {
            parts.append(Self.periodText(period, calendar: calendar))
        }
        if let minimum = filter.minAmount {
            parts.append(String(localized: "Over \(minimum.formatted())"))
        }
        if let maximum = filter.maxAmount {
            parts.append(String(localized: "Under \(maximum.formatted())"))
        }
        parts += filter.terms
        return parts
    }

    private static func periodText(_ period: Range<Date>, calendar: Calendar) -> String {
        var style = Date.FormatStyle()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let lastDay = period.upperBound.addingTimeInterval(-1)
        if calendar.dateInterval(of: .month, for: period.lowerBound)?.end == period.upperBound {
            return period.lowerBound.formatted(style.month(.wide).year())
        }
        if calendar.dateInterval(of: .year, for: period.lowerBound)?.end == period.upperBound {
            return period.lowerBound.formatted(style.year())
        }
        let short = style.month(.abbreviated).day()
        let from = period.lowerBound.formatted(short), to = lastDay.formatted(short)
        return String(localized: "\(from) to \(to)")
    }

    private func clearResults() {
        people = []
        groups = []
        expenses = []
        understood = []
        hasSearched = false
    }
}
