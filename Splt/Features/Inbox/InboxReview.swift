import Foundation
import SpltCore

enum PaymentPriority: Int, Comparable, Sendable {
    /// Muted or recurring: kept, never asked about.
    case quiet
    /// Waits in the list and the evening summary.
    case normal
    /// Likely shared: worth a nudge.
    case high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Decides how loudly to ask about a payment. Big or shared-looking payments get a nudge, muted
/// merchants and subscriptions stay quiet, and the rest wait in the list.
struct PaymentScorer: Sendable {
    var calendar: Calendar = .current
    /// The days of a trip that covers the payment. Anything paid on a trip is likely shared.
    var tripRange: Range<Date>?

    static let sharedKinds: Set<ExpenseCategoryHint> = [.food, .drinks, .travel, .lodging, .transport, .entertainment]

    func priority(of payment: PendingPayment, in state: PaymentInboxState) -> PaymentPriority {
        let memory = state.memory(for: payment)
        if memory?.isMuted == true || state.isRecurring(payment) { return .quiet }
        if let tripRange, tripRange.contains(payment.date) { return .high }
        if let memory, memory.splitCount > 0 { return .high }
        let units = payment.amount.minorUnits
        guard let big = Self.bigAmount(for: payment.amount.currencyCode, in: state) else { return .normal }
        if units >= big { return .high }
        if let kind = Self.kind(of: payment), Self.sharedKinds.contains(kind), units * 2 >= big {
            // lunch alone is common, dinner and drinks are usually shared
            let isMeal = kind == .food || kind == .drinks
            if !isMeal || calendar.component(.hour, from: payment.date) >= 17 { return .high }
        }
        return .normal
    }

    static func kind(of payment: PendingPayment) -> ExpenseCategoryHint? {
        KeywordCategorySuggester().suggestNow(title: payment.merchant, merchant: payment.merchant)?.category
    }

    /// Minor units that count as a big payment: a fixed line for common currencies, or two and a half
    /// times what you usually pay, whichever is lower.
    static func bigAmount(for code: String, in state: PaymentInboxState) -> Int64? {
        let lines: [String: Int64] = [
            "USD": 40, "EUR": 40, "GBP": 35, "CAD": 50, "AUD": 60, "NZD": 60, "CHF": 40,
            "SGD": 50, "AED": 150, "INR": 2_000, "JPY": 5_000
        ]
        let line = lines[code].map { $0 * Currency.minorUnitScale(for: code) }
        let amounts = state.payments.filter { $0.amount.currencyCode == code }.map(\.amount.minorUnits).sorted()
        let usual = amounts.count >= 5 ? amounts[amounts.count / 2] * 5 / 2 : nil
        switch (line, usual) {
        case let (line?, usual?): return min(line, usual)
        default: return line ?? usual
        }
    }
}

/// Picks the group a payment most likely belongs in: the group a Focus points at, a trip on that day,
/// where this merchant went last time, an expense added within three hours, then your busiest group.
@MainActor
struct SplitTargetPicker {
    nonisolated static let focusGroupKey = "inbox.focusGroupID"

    /// Open groups you haven't left, friends' direct groups included.
    let groups: [SplitGroup]
    private let recent: [(group: GroupID, date: Date)]
    private let fallback: GroupID?
    private let focusGroupID: UUID?
    private let now: Date
    private let calendar: Calendar

    init(
        services: DataServices, now: Date, earliest: Date, calendar: Calendar = .current,
        defaults: UserDefaults = .standard, shared: UserDefaults = PaymentInboxFile.sharedDefaults
    ) {
        let left = LeftGroupsStore(defaults: defaults)
        let groups = ((try? services.groups.groups(includeArchived: false)) ?? []).filter { !left.contains($0.id) }
        self.groups = groups
        self.now = now
        self.calendar = calendar
        focusGroupID = shared.string(forKey: Self.focusGroupKey).flatMap(UUID.init(uuidString:))
        fallback = AddExpenseLauncher.startingGroup(
            among: groups, lastUsed: defaults.string(forKey: ExpenseFormModel.lastGroupKey) ?? "", left: left
        )
        var recent: [(group: GroupID, date: Date)] = []
        for group in groups {
            for expense in (try? services.expenses.expenses(in: group.id)) ?? [] where expense.date >= earliest {
                recent.append((group.id, expense.date))
            }
        }
        self.recent = recent
    }

    func target(for payment: PendingPayment, memory: MerchantMemory?) -> SplitGroup? {
        let regular = groups.filter { $0.kind != .friend }
        if let focus = group(focusGroupID) { return focus }
        if let trip = Self.activeTrip(among: regular, on: payment.date, calendar: calendar) { return trip }
        if let remembered = group(memory?.groupID) { return remembered }
        let near = recent.filter { abs($0.date.timeIntervalSince(payment.date)) <= 3 * 3_600 }.max { $0.date < $1.date }
        if let near, let found = groups.first(where: { $0.id == near.group }) { return found }
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        var counts: [GroupID: Int] = [:]
        for entry in recent where entry.date >= monthAgo { counts[entry.group, default: 0] += 1 }
        if let busiest = regular.max(by: { counts[$0.id, default: 0] < counts[$1.id, default: 0] }),
           counts[busiest.id, default: 0] > 0 {
            return busiest
        }
        return fallback.flatMap { id in groups.first { $0.id == id } }
    }

    private func group(_ id: UUID?) -> SplitGroup? {
        id.flatMap { id in groups.first { $0.id.rawValue == id } }
    }

    /// The whole days a trip covers, from the start of its first day to the end of its last.
    nonisolated static func tripRange(of group: SplitGroup, calendar: Calendar) -> Range<Date>? {
        guard group.kind == .trip, !group.isArchived, let start = group.tripStart else { return nil }
        let first = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: group.tripEnd ?? start)),
              end > first else { return nil }
        return first..<end
    }

    /// The trip on that day. When trips overlap, the one that started last.
    nonisolated static func activeTrip(among groups: [SplitGroup], on date: Date, calendar: Calendar) -> SplitGroup? {
        groups.filter { tripRange(of: $0, calendar: calendar)?.contains(date) == true }
            .max { ($0.tripStart ?? .distantPast) < ($1.tripStart ?? .distantPast) }
    }
}

/// The inbox worked out once: how loud each payment is, which group it goes to, and any trip to wrap up.
@MainActor
struct InboxReview {
    struct Row: Identifiable, Hashable {
        var payment: PendingPayment
        var priority: PaymentPriority
        var target: SplitGroup?
        var category: ExpenseCategory?
        var isStale: Bool
        /// Paid during the trip that is happening now.
        var isInActiveTrip: Bool
        var id: UUID { payment.id }
    }

    /// A trip that ended in the last two weeks with payments from it still waiting.
    struct WrapUp: Identifiable, Hashable {
        var trip: SplitGroup
        var payments: [PendingPayment]
        var id: GroupID { trip.id }
    }

    static let staleAfter: TimeInterval = 7 * 86_400
    static let wrapUpWindow: TimeInterval = 14 * 86_400

    let now: Date
    let rows: [Row]
    let activeTrip: SplitGroup?
    let wrapUps: [WrapUp]

    init(
        state: PaymentInboxState, services: DataServices, now: Date, calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.now = now
        let pending = state.pending
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        let earliest = min(pending.last?.date ?? monthAgo, monthAgo).addingTimeInterval(-3 * 3_600)
        let picker = SplitTargetPicker(services: services, now: now, earliest: earliest, calendar: calendar, defaults: defaults)
        let trips = picker.groups.filter { $0.kind == .trip }
        let current = SplitTargetPicker.activeTrip(among: trips, on: now, calendar: calendar)
        activeTrip = current
        rows = pending.map { payment in
            let trip = SplitTargetPicker.activeTrip(among: trips, on: payment.date, calendar: calendar)
            let scorer = PaymentScorer(
                calendar: calendar, tripRange: trip.flatMap { SplitTargetPicker.tripRange(of: $0, calendar: calendar) }
            )
            let memory = state.memory(for: payment)
            return Row(
                payment: payment,
                priority: scorer.priority(of: payment, in: state),
                target: picker.target(for: payment, memory: memory),
                category: memory?.category ?? PaymentScorer.kind(of: payment).map { ExpenseCategory($0) },
                isStale: now.timeIntervalSince(payment.date) > Self.staleAfter,
                isInActiveTrip: trip != nil && trip?.id == current?.id
            )
        }
        wrapUps = trips.compactMap { trip in
            guard let range = SplitTargetPicker.tripRange(of: trip, calendar: calendar), now >= range.upperBound,
                  now.timeIntervalSince(range.upperBound) < Self.wrapUpWindow else { return nil }
            let fromTrip = pending.filter { range.contains($0.date) }
            return fromTrip.isEmpty ? nil : WrapUp(trip: trip, payments: fromTrip)
        }
    }

    func row(for id: UUID) -> Row? {
        rows.first { $0.id == id }
    }

    /// Recent payments worth asking about.
    var toSplit: [Row] {
        rows.filter { !$0.isStale && $0.priority != .quiet }
    }

    /// Muted, recurring or more than a week old. Kept, never counted or announced.
    var everythingElse: [Row] {
        rows.filter { $0.isStale || $0.priority == .quiet }
    }
}
