import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Trip days")
struct TripDayTests {
    private static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private let paris = Self.calendar("Europe/Paris")
    private let newYork = Self.calendar("America/New_York")

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func day(_ date: Date, in calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// A trip made in Paris on the new group sheet, 10 to 16 November.
    private func parisTrip() throws -> SplitGroup {
        let services = try DataServices.inMemory()
        let model = CreateGroupViewModel(
            services: services, defaultCurrencyCode: "EUR", today: date(paris, 11, 10, hour: 9), calendar: paris
        )
        model.name = "Lisbon"
        model.selectTemplate(.trip)
        let id = try model.create()
        return try #require(try services.groups.group(id: id))
    }

    @Test func aTripMadeInParisHasTheSameDaysInNewYork() throws {
        let trip = try parisTrip()
        let range = try #require(SplitTargetPicker.tripRange(of: trip, calendar: newYork))
        #expect(range.lowerBound == date(newYork, 11, 10))
        #expect(range.upperBound == date(newYork, 11, 17))
        #expect(SplitTargetPicker.activeTrip(among: [trip], on: date(newYork, 11, 16, hour: 22), calendar: newYork)?.id == trip.id)
        #expect(SplitTargetPicker.activeTrip(among: [trip], on: date(newYork, 11, 9, hour: 22), calendar: newYork) == nil)

        #expect(ExpenseSectioning.dayNumber(of: date(newYork, 11, 10, hour: 8), tripStart: trip.tripStart, calendar: newYork) == 1)
        #expect(ExpenseSectioning.dayNumber(of: date(newYork, 11, 16, hour: 20), tripStart: trip.tripStart, calendar: newYork) == 7)
    }

    @Test func aTripSavedAsParisMidnightByAnOlderVersionReadsTheSameInNewYork() throws {
        let trip = SplitGroup(
            name: "Lisbon", currencyCode: "EUR", kind: .trip,
            tripStart: date(paris, 11, 10), tripEnd: date(paris, 11, 16)
        )
        let range = try #require(SplitTargetPicker.tripRange(of: trip, calendar: newYork))
        #expect(range.lowerBound == date(newYork, 11, 10))
        #expect(range.upperBound == date(newYork, 11, 17))
        #expect(ExpenseSectioning.dayNumber(of: date(newYork, 11, 10, hour: 8), tripStart: trip.tripStart, calendar: newYork) == 1)
        // and still the same days in Paris itself
        let home = try #require(SplitTargetPicker.tripRange(of: trip, calendar: paris))
        #expect(home == date(paris, 11, 10)..<date(paris, 11, 17))
    }

    @Test func aSavedDayIsTheSameDayAcrossTheDateLine() {
        let saved = TripDay.stored(date(paris, 11, 10, hour: 15), calendar: paris)
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Pacific/Auckland", "America/Los_Angeles", "Asia/Kolkata"] {
            let calendar = Self.calendar(zone)
            #expect(day(TripDay.startOfDay(saved, calendar: calendar), in: calendar) == DateComponents(year: 2026, month: 11, day: 10))
            #expect(day(TripDay.noon(saved, calendar: calendar), in: calendar) == DateComponents(year: 2026, month: 11, day: 10))
        }
    }

    @Test func aDateSavedAtAnyOtherTimeIsTheDayItFallsOn() {
        // older versions kept the time of day when a group became a trip in settings
        let saved = newYork.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 21, minute: 13, second: 7))!
        #expect(TripDay.startOfDay(saved, calendar: newYork) == date(newYork, 11, 10))
    }

    @Test func recapAndBalanceLinkUseTheSavedDays() throws {
        let trip = try parisTrip()
        let expense = Expense(
            title: "Dinner", total: Money(minorUnits: 5000, currencyCode: "EUR"), date: date(newYork, 11, 12, hour: 19),
            paidBy: PersonID(), split: .equal(participants: [PersonID()])
        )
        let stats = try #require(RecapStats(group: trip, expenses: [expense], names: [:], now: date(newYork, 11, 20), calendar: newYork))
        #expect(stats.first == date(newYork, 11, 10))
        #expect(stats.last == date(newYork, 11, 16))

        let snapshot = BalanceSnapshot(
            group: trip, me: nil, people: [:], expenses: [], balances: nil, includesExpenses: false,
            now: date(newYork, 11, 20), calendar: newYork
        )
        #expect(snapshot.tripDays == ["2026-11-10", "2026-11-16"])
    }

    @Test func settingsShowAndKeepTheSavedDays() throws {
        let fixture = try Fixture()
        // saved as Paris midnight by an older version, edited in New York
        let trip = SplitGroup(
            name: "Lisbon", currencyCode: "EUR", kind: .trip, memberIDs: [fixture.me.id],
            tripStart: date(paris, 11, 10), tripEnd: date(paris, 11, 16)
        )
        try fixture.services.groups.create(trip)
        let model = GroupSettingsViewModel(groupID: trip.id, services: fixture.services, calendar: newYork)
        #expect(day(model.tripStart, in: newYork) == DateComponents(year: 2026, month: 11, day: 10))
        #expect(day(model.tripEnd, in: newYork) == DateComponents(year: 2026, month: 11, day: 16))
        #expect(!model.hasFieldEdits)

        model.tripEnd = date(newYork, 11, 18, hour: 12)
        #expect(model.hasFieldEdits)
        try model.save()
        let saved = try #require(try fixture.services.groups.group(id: trip.id))
        #expect(saved.tripStart.map { TripDay.startOfDay($0, calendar: paris) } == date(paris, 11, 10))
        #expect(saved.tripEnd.map { TripDay.startOfDay($0, calendar: paris) } == date(paris, 11, 18))
    }
}
