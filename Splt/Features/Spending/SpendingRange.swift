import Foundation

/// The period a spending screen covers. It always runs to the end of the current month, in whole months.
enum SpendingRange: String, CaseIterable, Identifiable, Sendable {
    case last12Months
    case thisYear
    case allTime
    /// The Activity header's month. The menu doesn't offer it.
    case thisMonth

    /// What the range menu offers.
    static let menu: [SpendingRange] = [.last12Months, .thisYear, .allTime]

    var id: String { rawValue }

    /// The menu's label.
    var title: String {
        switch self {
        case .last12Months: String(localized: "Last 12 months")
        case .thisYear: String(localized: "This year")
        case .allTime: String(localized: "All time")
        case .thisMonth: String(localized: "This month")
        }
    }

    /// The range in the middle of a sentence: "Your share · last 12 months".
    var phrase: String {
        switch self {
        case .last12Months: String(localized: "last 12 months")
        case .thisYear: String(localized: "this year")
        case .allTime: String(localized: "all time")
        case .thisMonth: String(localized: "this month")
        }
    }

    /// The first instant of every month the range covers, oldest first. All time starts at the month of
    /// `earliest`, the oldest expense, and is just this month when there is none.
    func months(now: Date, earliest: Date?, calendar: Calendar) -> [Date] {
        guard let current = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        let first: Date
        switch self {
        case .thisMonth:
            first = current
        case .last12Months:
            first = calendar.date(byAdding: .month, value: -11, to: current) ?? current
        case .thisYear:
            first = calendar.dateInterval(of: .year, for: now)?.start ?? current
        case .allTime:
            let start = earliest.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? current
            first = min(start, current)
        }
        var months: [Date] = []
        var month = first
        while month <= current {
            months.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
            month = next
        }
        return months
    }

    /// The dates the range covers, from its first month to the end of this one. Nil for all time.
    func dateRange(now: Date, calendar: Calendar) -> Range<Date>? {
        guard self != .allTime,
              let first = months(now: now, earliest: nil, calendar: calendar).first,
              let end = calendar.dateInterval(of: .month, for: now)?.end else { return nil }
        return first..<end
    }
}
