import Foundation
import Observation
import SpltCore

/// Events from the groups you are in, newest first and grouped by day.
@MainActor
@Observable
final class ActivityModel {
    struct DaySection: Identifiable, Equatable {
        var day: Date
        var entries: [ActivityEntry]

        var id: Date { day }
    }

    enum PaymentAction: Equatable, Sendable {
        case undo
        case restore
    }

    var typeFilter: ActivityTypeFilter = .all
    var groupFilter: GroupID?
    var errorMessage: String?

    private(set) var entries: [ActivityEntry] = []
    private(set) var groups: [GroupID: SplitGroup] = [:]
    private(set) var me: Person?
    private(set) var names: [PersonID: String] = [:]
    private(set) var paymentActions: [UUID: PaymentAction] = [:]
    private(set) var didLoad = false

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    static let pageSize = 300

    init(services: DataServices, calendar: Calendar = .current) {
        self.services = services
        self.calendar = calendar
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    func refresh() {
        do {
            me = try services.people.me()
            names = Dictionary(
                try services.people.allPeople().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
            )
            groups = Dictionary(
                try services.groups.groups(includeArchived: true).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            entries = try services.activity.entries(in: nil, limit: Self.pageSize)
            paymentActions = try loadPaymentActions()
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
        didLoad = true
    }

    // MARK: Showing

    var visibleEntries: [ActivityEntry] {
        entries.filter { entry in
            typeFilter.includes(entry.event.kind) && (groupFilter == nil || entry.groupID == groupFilter)
        }
    }

    var sections: [DaySection] {
        var result: [DaySection] = []
        for entry in visibleEntries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if let last = result.last, last.day == day {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(DaySection(day: day, entries: [entry]))
            }
        }
        return result
    }

    var isFiltering: Bool { typeFilter != .all || groupFilter != nil }

    func clearFilters() {
        typeFilter = .all
        groupFilter = nil
    }

    /// Groups that have events, for the group filter. Hidden two person groups are left out.
    var filterGroups: [SplitGroup] {
        let used = Set(entries.compactMap(\.groupID))
        return used.compactMap { groups[$0] }
            .filter { $0.kind != .friend }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var unreadCount: Int { entries.filter { !$0.isRead }.count }

    func text(for entry: ActivityEntry, locale: Locale = .current) -> String {
        GroupActivityText(currentPerson: me?.id, names: names, locale: locale).sentence(for: entry)
    }

    /// The group name to show under a row. Nil for the hidden group behind a friend.
    func groupName(for entry: ActivityEntry) -> String? {
        guard let id = entry.groupID, let group = groups[id], group.kind != .friend else { return nil }
        return group.name
    }

    /// Who did it, for the avatar on the timeline. Nil when the event has no known actor.
    func actor(for entry: ActivityEntry) -> (id: PersonID, name: String, isMe: Bool)? {
        guard let id = entry.actorID else { return nil }
        let isMe = id == me?.id
        let name = isMe ? (me?.name ?? String(localized: "You")) : names[id] ?? String(localized: "Someone")
        return (id, name, isMe)
    }

    func destination(for entry: ActivityEntry) -> Route? {
        ActivityDestination.route(for: entry, me: me?.id, groups: groups)
    }

    func title(for section: DaySection, now: Date = Date(), locale: Locale = .current) -> String {
        if calendar.isDate(section.day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(section.day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        var style = Date.FormatStyle(date: .complete, time: .omitted).locale(locale)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return section.day.formatted(style)
    }

    // MARK: Changes

    func markRead(_ entry: ActivityEntry) {
        guard !entry.isRead else { return }
        perform { try services.activity.markRead(ids: [entry.id]) }
    }

    func markAllRead() {
        perform { try services.activity.markAllRead() }
    }

    func perform(_ action: PaymentAction, on entry: ActivityEntry) {
        guard let payment = paymentID(of: entry) else { return }
        perform {
            switch action {
            case .undo: try services.payments.undo(id: payment)
            case .restore: try services.payments.restore(id: payment)
            }
        }
    }

    // MARK: Helpers

    private func paymentID(of entry: ActivityEntry) -> PaymentID? {
        switch entry.event {
        case .paymentRecorded(let payment), .paymentUndone(let payment): payment.id
        default: nil
        }
    }

    /// Only the newest event about a payment offers an action, so an old row never contradicts the current state.
    private func loadPaymentActions() throws -> [UUID: PaymentAction] {
        var seen = Set<PaymentID>()
        var actions: [UUID: PaymentAction] = [:]
        for entry in entries {
            guard let id = paymentID(of: entry), seen.insert(id).inserted,
                  let payment = try services.payments.payment(id: id) else { continue }
            actions[entry.id] = payment.isDeleted ? .restore : .undo
        }
        return actions
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
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

/// How many events are unread, for the badge on the Activity tab.
@MainActor
@Observable
final class UnreadActivityStore {
    private(set) var count = 0

    @ObservationIgnored private let activity: any ActivityRepository
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    init(services: DataServices) {
        activity = services.activity
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    func refresh() {
        count = (try? activity.unreadCount()) ?? 0
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
