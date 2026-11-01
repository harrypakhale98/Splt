/// How often a recurring expense repeats.
public enum RecurrenceFrequency: String, Hashable, Sendable, Codable, CaseIterable {
    case daily
    /// Every 7 days.
    case weekly
    /// Every 14 days.
    case biweekly
    /// Twice a month, 15 days apart: on the start day and the day 15 days away from it in the
    /// month. A start on the 1st repeats on the 1st and 16th, a start on the 15th on the 15th
    /// and 30th, a start on the 31st on the 16th and the last day of each month.
    case semiMonthly
    /// Once a month on the start day, or the last day of shorter months.
    case monthly
    /// Every three months.
    case quarterly
    /// Once a year on the start date, using 28 February for 29 February in non leap years.
    case yearly
}
