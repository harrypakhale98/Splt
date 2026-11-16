import Foundation

/// Trip start and end dates are calendar days, not moments.
///
/// They used to be saved as midnight where the trip was made. Anyone a few time zones west, a member at
/// home or the traveller after a flight, then read every trip day as the day before. A day is now saved as
/// 11:30 GMT on that date and read back in GMT, so it names the same day everywhere. 11:30 GMT is midnight
/// in no time zone in use, so a day saved this way is never mistaken for one saved the old way.
enum TripDay {
    private static let savedHour = 11
    private static let savedMinute = 30

    /// What to save for the day `date` falls on in `calendar`, the one the date picker showed.
    static func stored(_ date: Date, calendar: Calendar = .current) -> Date {
        saved(gregorian(calendar.timeZone).dateComponents([.year, .month, .day], from: date)) ?? date
    }

    /// The start of the saved day in `calendar`, for trip ranges and day numbers.
    static func startOfDay(_ stored: Date, calendar: Calendar = .current) -> Date {
        let local = gregorian(calendar.timeZone)
        return local.startOfDay(for: noon(stored, calendar: calendar))
    }

    /// Noon on the saved day in `calendar`: safely inside the day, for date pickers and labels.
    static func noon(_ stored: Date, calendar: Calendar = .current) -> Date {
        var parts = day(of: stored, timeZone: calendar.timeZone)
        parts.hour = 12
        return gregorian(calendar.timeZone).date(from: parts) ?? stored
    }

    /// The saved day as it is saved now, so a day saved the old way compares equal to the same day picked again.
    static func normalized(_ stored: Date, calendar: Calendar = .current) -> Date {
        saved(day(of: stored, timeZone: calendar.timeZone)) ?? stored
    }

    /// The year, month and day a saved date names. `timeZone` matters only for dates saved the old way.
    static func day(of stored: Date, timeZone: TimeZone) -> DateComponents {
        let parts = gregorian(.gmt).dateComponents([.year, .month, .day], from: stored)
        if saved(parts) == stored { return parts }
        let local = gregorian(timeZone)
        var day = local.startOfDay(for: stored)
        // An old midnight from another time zone lands on a whole quarter hour here, since every zone is a
        // whole number of quarter hours from GMT. The nearest midnight is the day that was meant whenever the
        // two places are less than 12 hours apart. Any other time is read as the day it falls on here.
        if isWholeQuarterHour(stored), let next = local.date(byAdding: .day, value: 1, to: day),
           next.timeIntervalSince(stored) < stored.timeIntervalSince(day) {
            day = next
        }
        return local.dateComponents([.year, .month, .day], from: day)
    }

    private static func saved(_ day: DateComponents) -> Date? {
        var parts = DateComponents(year: day.year, month: day.month, day: day.day)
        parts.hour = savedHour
        parts.minute = savedMinute
        return gregorian(.gmt).date(from: parts)
    }

    private static func isWholeQuarterHour(_ date: Date) -> Bool {
        date.timeIntervalSince1970.truncatingRemainder(dividingBy: 900) == 0
    }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
