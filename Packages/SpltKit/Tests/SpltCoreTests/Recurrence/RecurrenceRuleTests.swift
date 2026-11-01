import Foundation
import Testing
@testable import SpltCore

@Suite("Recurrence dates")
struct RecurrenceRuleTests {
    private func days(_ rule: RecurrenceRule, count: Int, zone: String = "UTC") -> [String] {
        (0..<count).compactMap { rule.occurrence(at: $0) }.map { wallClock($0, in: zone) }
    }

    @Test func firstOccurrenceIsTheStartDate() {
        for frequency in RecurrenceFrequency.allCases {
            let start = localDate(2025, 3, 17, 14, 30)
            #expect(rule(frequency, from: start).occurrence(at: 0) == start)
        }
    }

    @Test func negativeIndexesDoNotExist() {
        #expect(rule(.daily, from: localDate(2025, 1, 1)).occurrence(at: -1) == nil)
    }

    @Test func daily() {
        #expect(days(rule(.daily, from: localDate(2025, 2, 26)), count: 5) == [
            "2025-02-26 09:00", "2025-02-27 09:00", "2025-02-28 09:00", "2025-03-01 09:00", "2025-03-02 09:00"
        ])
    }

    @Test func weeklyAndBiweekly() {
        let start = localDate(2025, 12, 29)
        #expect(days(rule(.weekly, from: start), count: 3) == ["2025-12-29 09:00", "2026-01-05 09:00", "2026-01-12 09:00"])
        #expect(days(rule(.biweekly, from: start), count: 3) == ["2025-12-29 09:00", "2026-01-12 09:00", "2026-01-26 09:00"])
    }

    @Test func monthlyFromTheThirtyFirstClampsAndComesBack() {
        #expect(days(rule(.monthly, from: localDate(2025, 1, 31)), count: 6) == [
            "2025-01-31 09:00", "2025-02-28 09:00", "2025-03-31 09:00",
            "2025-04-30 09:00", "2025-05-31 09:00", "2025-06-30 09:00"
        ])
    }

    @Test func monthlyHandlesLeapYears() {
        #expect(days(rule(.monthly, from: localDate(2024, 1, 31)), count: 3) == [
            "2024-01-31 09:00", "2024-02-29 09:00", "2024-03-31 09:00"
        ])
        #expect(days(rule(.monthly, from: localDate(2023, 12, 30)), count: 3) == [
            "2023-12-30 09:00", "2024-01-30 09:00", "2024-02-29 09:00"
        ])
    }

    @Test func monthlyRollsOverYears() {
        #expect(days(rule(.monthly, from: localDate(2025, 11, 15)), count: 4) == [
            "2025-11-15 09:00", "2025-12-15 09:00", "2026-01-15 09:00", "2026-02-15 09:00"
        ])
    }

    @Test func quarterly() {
        #expect(days(rule(.quarterly, from: localDate(2025, 11, 30)), count: 4) == [
            "2025-11-30 09:00", "2026-02-28 09:00", "2026-05-30 09:00", "2026-08-30 09:00"
        ])
    }

    @Test func yearlyFromLeapDay() {
        #expect(days(rule(.yearly, from: localDate(2024, 2, 29)), count: 5) == [
            "2024-02-29 09:00", "2025-02-28 09:00", "2026-02-28 09:00", "2027-02-28 09:00", "2028-02-29 09:00"
        ])
    }

    @Test func semiMonthlyFromTheFirst() {
        #expect(days(rule(.semiMonthly, from: localDate(2025, 1, 1)), count: 5) == [
            "2025-01-01 09:00", "2025-01-16 09:00", "2025-02-01 09:00", "2025-02-16 09:00", "2025-03-01 09:00"
        ])
    }

    @Test func semiMonthlyFromTheFifteenth() {
        #expect(days(rule(.semiMonthly, from: localDate(2025, 1, 15)), count: 5) == [
            "2025-01-15 09:00", "2025-01-30 09:00", "2025-02-15 09:00", "2025-02-28 09:00", "2025-03-15 09:00"
        ])
    }

    @Test func semiMonthlyFromTheLateInTheMonth() {
        #expect(days(rule(.semiMonthly, from: localDate(2025, 1, 20)), count: 5) == [
            "2025-01-20 09:00", "2025-02-05 09:00", "2025-02-20 09:00", "2025-03-05 09:00", "2025-03-20 09:00"
        ])
        #expect(days(rule(.semiMonthly, from: localDate(2025, 1, 31)), count: 5) == [
            "2025-01-31 09:00", "2025-02-16 09:00", "2025-02-28 09:00", "2025-03-16 09:00", "2025-03-31 09:00"
        ])
    }

    @Test func wallClockTimeSurvivesDaylightSaving() {
        let zone = "America/New_York"
        let start = localDate(2025, 3, 8, 9, 0, in: zone)
        let daily = rule(.daily, from: start, zone: zone)
        #expect(days(daily, count: 4, zone: zone) == [
            "2025-03-08 09:00", "2025-03-09 09:00", "2025-03-10 09:00", "2025-03-11 09:00"
        ])
        // the clocks went forward on the morning of 9 March, so that day's gap is 23 hours
        let first = daily.occurrence(at: 0)!, second = daily.occurrence(at: 1)!, third = daily.occurrence(at: 2)!
        #expect(second.timeIntervalSince(first) == 23 * 3600)
        #expect(third.timeIntervalSince(second) == 24 * 3600)
    }

    @Test func monthlyRuleAcrossDaylightSavingKeepsLocalTime() {
        let zone = "Europe/Berlin"
        let monthly = rule(.monthly, from: localDate(2025, 3, 15, 8, 30, in: zone), zone: zone)
        #expect(days(monthly, count: 3, zone: zone) == ["2025-03-15 08:30", "2025-04-15 08:30", "2025-05-15 08:30"])
    }

    @Test func dayOfMonthIsReadInTheRulesTimeZone() {
        // 22:00 on 31 January in Los Angeles is already 1 February in UTC
        let zone = "America/Los_Angeles"
        let start = localDate(2025, 1, 31, 22, 0, in: zone)
        let inLosAngeles = rule(.monthly, from: start, zone: zone)
        #expect(days(inLosAngeles, count: 3, zone: zone) == ["2025-01-31 22:00", "2025-02-28 22:00", "2025-03-31 22:00"])

        let inUTC = rule(.monthly, from: start, zone: "UTC")
        #expect(days(inUTC, count: 3) == ["2025-02-01 06:00", "2025-03-01 06:00", "2025-04-01 06:00"])
    }

    @Test func farEastTimeZones() {
        let zone = "Pacific/Kiritimati"
        let monthly = rule(.monthly, from: localDate(2025, 1, 31, 1, 0, in: zone), zone: zone)
        #expect(days(monthly, count: 2, zone: zone) == ["2025-01-31 01:00", "2025-02-28 01:00"])
    }

    @Test func aTimeThatDoesNotExistStillLandsOnTheRightDay() {
        // 2:30 does not exist in New York on 9 March 2025
        let zone = "America/New_York"
        let monthly = rule(.monthly, from: localDate(2025, 2, 9, 2, 30, in: zone), zone: zone)
        let march = monthly.occurrence(at: 1)!
        #expect(wallClock(march, in: zone).hasPrefix("2025-03-09"))
    }

    @Test func endDateIsInclusive() {
        let limited = rule(.daily, from: localDate(2025, 1, 1), until: localDate(2025, 1, 3))
        #expect(days(limited, count: 10) == ["2025-01-01 09:00", "2025-01-02 09:00", "2025-01-03 09:00"])
        #expect(limited.occurrence(at: 3) == nil)
    }

    @Test func maxOccurrencesCountsTheFirst() {
        let limited = rule(.weekly, from: localDate(2025, 1, 1), max: 2)
        #expect(days(limited, count: 10) == ["2025-01-01 09:00", "2025-01-08 09:00"])
    }

    @Test func ruleSurvivesJSON() throws {
        let original = rule(.semiMonthly, from: localDate(2025, 1, 20, in: "Asia/Tokyo"), zone: "Asia/Tokyo", until: localDate(2026, 1, 1), max: 10)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.timeZone.identifier == "Asia/Tokyo")
    }

    @Test func unknownTimeZoneFallsBackToGMT() throws {
        var broken = rule(.daily, from: localDate(2025, 1, 1))
        broken.timeZoneIdentifier = "Mars/Olympus"
        #expect(broken.timeZone == .gmt)
        #expect(broken.occurrence(at: 1) == localDate(2025, 1, 2))
    }
}
