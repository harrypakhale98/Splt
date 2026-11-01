import Foundation
@testable import SpltCore

/// A date from wall clock parts in a named time zone.
func localDate(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0,
    in zone: String = "UTC"
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// The wall clock parts of a date in a named time zone, as "yyyy-mm-dd hh:mm".
func wallClock(_ date: Date, in zone: String = "UTC") -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return String(format: "%04d-%02d-%02d %02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
}

func rule(
    _ frequency: RecurrenceFrequency, from start: Date, zone: String = "UTC",
    until end: Date? = nil, max: Int? = nil
) -> RecurrenceRule {
    RecurrenceRule(
        frequency: frequency, startDate: start, timeZone: TimeZone(identifier: zone)!,
        endDate: end, maxOccurrences: max
    )
}
