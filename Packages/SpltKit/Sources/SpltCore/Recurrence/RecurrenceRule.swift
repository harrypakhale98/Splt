import Foundation

/// A repeating schedule that starts at `startDate`, which is its first occurrence.
///
/// Occurrences are worked out in the rule's time zone and keep the same wall clock time, so
/// a 9:00 expense stays at 9:00 across daylight saving changes. Each occurrence is computed
/// from the start date rather than from the previous one, so a monthly rule starting on the
/// 31st lands on the 28th or 30th in short months and returns to the 31st afterwards.
public struct RecurrenceRule: Hashable, Sendable, Codable {
    public var frequency: RecurrenceFrequency
    public var startDate: Date
    public var timeZoneIdentifier: String
    /// No occurrence is later than this date. It is inclusive.
    public var endDate: Date?
    /// The most occurrences the rule produces, counting the first.
    public var maxOccurrences: Int?

    public init(
        frequency: RecurrenceFrequency,
        startDate: Date,
        timeZone: TimeZone = .current,
        endDate: Date? = nil,
        maxOccurrences: Int? = nil
    ) {
        self.frequency = frequency
        self.startDate = startDate
        self.timeZoneIdentifier = timeZone.identifier
        self.endDate = endDate
        self.maxOccurrences = maxOccurrences
    }

    /// The rule's time zone, falling back to GMT if the stored identifier is unknown.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    /// The occurrence at a zero based position, or nil past the end of the rule.
    public func occurrence(at index: Int) -> Date? {
        guard index >= 0 else { return nil }
        if let maxOccurrences, index >= maxOccurrences { return nil }
        guard let date = unboundedOccurrence(at: index, calendar: calendar) else { return nil }
        if let endDate, date > endDate { return nil }
        return date
    }

    /// The first occurrence strictly after `date`, or nil if the rule has ended.
    public func nextOccurrence(after date: Date) -> Date? {
        guard let index = firstIndex(where: { $0 > date }) else { return nil }
        return occurrence(at: index)
    }

    /// Every occurrence from `start` to `end`, both included, oldest first.
    ///
    /// - Parameter limit: stops after this many dates, as a guard against a huge range.
    public func occurrences(from start: Date, through end: Date, limit: Int = 1_000) -> [Date] {
        guard start <= end, let first = firstIndex(where: { $0 >= start }) else { return [] }
        return collect(startingAt: first, through: end, limit: limit)
    }

    /// Occurrences that are due: later than `lastCreated` (or from the very first occurrence
    /// when nothing was created yet) and not later than `now`.
    public func dueOccurrences(after lastCreated: Date?, through now: Date, limit: Int = 1_000) -> [Date] {
        guard let lastCreated else {
            return collect(startingAt: 0, through: now, limit: limit)
        }
        guard let first = firstIndex(where: { $0 > lastCreated }) else { return [] }
        return collect(startingAt: first, through: now, limit: limit)
    }

    private func collect(startingAt first: Int, through end: Date, limit: Int) -> [Date] {
        var result: [Date] = []
        var index = first
        while result.count < limit, let date = occurrence(at: index), date <= end {
            result.append(date)
            index += 1
        }
        return result
    }
}
