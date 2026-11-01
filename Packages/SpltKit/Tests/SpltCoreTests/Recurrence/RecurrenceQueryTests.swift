import Foundation
import Testing
@testable import SpltCore

@Suite("Recurrence queries")
struct RecurrenceQueryTests {
    private let monthly = rule(.monthly, from: localDate(2025, 1, 31))

    private func text(_ dates: [Date]) -> [String] { dates.map { wallClock($0) } }

    @Test func nextOccurrenceBeforeTheStartIsTheStart() {
        #expect(monthly.nextOccurrence(after: localDate(2024, 6, 1)) == localDate(2025, 1, 31))
    }

    @Test func nextOccurrenceIsStrictlyAfter() {
        #expect(monthly.nextOccurrence(after: localDate(2025, 1, 31)) == localDate(2025, 2, 28))
        #expect(monthly.nextOccurrence(after: localDate(2025, 2, 27)) == localDate(2025, 2, 28))
        #expect(monthly.nextOccurrence(after: localDate(2025, 2, 28)) == localDate(2025, 3, 31))
        #expect(monthly.nextOccurrence(after: localDate(2025, 2, 28, 9, 1)) == localDate(2025, 3, 31))
    }

    @Test func nextOccurrenceFarInTheFuture() {
        let daily = rule(.daily, from: localDate(2025, 1, 1))
        #expect(daily.nextOccurrence(after: localDate(2125, 1, 1)) == localDate(2125, 1, 2))
        let yearly = rule(.yearly, from: localDate(2025, 6, 1))
        #expect(yearly.nextOccurrence(after: localDate(2500, 6, 1)) == localDate(2501, 6, 1))
    }

    @Test func nextOccurrenceStopsAtTheEnd() {
        let limited = rule(.daily, from: localDate(2025, 1, 1), until: localDate(2025, 1, 3))
        #expect(limited.nextOccurrence(after: localDate(2025, 1, 2)) == localDate(2025, 1, 3))
        #expect(limited.nextOccurrence(after: localDate(2025, 1, 3)) == nil)
        #expect(limited.nextOccurrence(after: localDate(2030, 1, 3)) == nil)
        let capped = rule(.daily, from: localDate(2025, 1, 1), max: 3)
        #expect(capped.nextOccurrence(after: localDate(2025, 1, 3)) == nil)
    }

    @Test func occurrencesBetweenTwoDatesIncludeBothEnds() {
        let found = monthly.occurrences(from: localDate(2025, 2, 28), through: localDate(2025, 5, 31))
        #expect(text(found) == ["2025-02-28 09:00", "2025-03-31 09:00", "2025-04-30 09:00", "2025-05-31 09:00"])
    }

    @Test func occurrencesBeforeTheStartAreSkipped() {
        let found = monthly.occurrences(from: localDate(2020, 1, 1), through: localDate(2025, 3, 1))
        #expect(text(found) == ["2025-01-31 09:00", "2025-02-28 09:00"])
    }

    @Test func emptyWhenNothingFits() {
        #expect(monthly.occurrences(from: localDate(2025, 3, 1), through: localDate(2025, 3, 30)).isEmpty)
        #expect(monthly.occurrences(from: localDate(2025, 5, 1), through: localDate(2025, 4, 1)).isEmpty)
        #expect(monthly.occurrences(from: localDate(2020, 1, 1), through: localDate(2020, 12, 31)).isEmpty)
    }

    @Test func occurrencesRespectTheEndAndTheCap() {
        let limited = rule(.daily, from: localDate(2025, 1, 1), until: localDate(2025, 1, 4))
        #expect(limited.occurrences(from: localDate(2025, 1, 2), through: localDate(2025, 12, 31)).count == 3)
        let capped = rule(.daily, from: localDate(2025, 1, 1), max: 5)
        #expect(capped.occurrences(from: localDate(2025, 1, 1), through: localDate(2025, 12, 31)).count == 5)
    }

    @Test func limitStopsHugeRanges() {
        let daily = rule(.daily, from: localDate(2025, 1, 1))
        let found = daily.occurrences(from: localDate(2025, 1, 1), through: localDate(2125, 1, 1), limit: 10)
        #expect(found.count == 10)
        #expect(daily.occurrences(from: localDate(2025, 1, 1), through: localDate(2025, 12, 31)).count == 365)
    }

    @Test func dueOccurrencesCatchUpAfterBeingAway() {
        let weekly = rule(.weekly, from: localDate(2025, 1, 1))
        let due = weekly.dueOccurrences(after: localDate(2025, 1, 8), through: localDate(2025, 1, 30))
        #expect(text(due) == ["2025-01-15 09:00", "2025-01-22 09:00", "2025-01-29 09:00"])
    }

    @Test func dueOccurrencesStartAtTheFirstWhenNothingWasCreated() {
        let weekly = rule(.weekly, from: localDate(2025, 1, 1))
        #expect(text(weekly.dueOccurrences(after: nil, through: localDate(2025, 1, 9))) == ["2025-01-01 09:00", "2025-01-08 09:00"])
        #expect(weekly.dueOccurrences(after: nil, through: localDate(2024, 12, 31)).isEmpty)
    }

    @Test func dueOccurrencesIgnoreTheFuture() {
        let weekly = rule(.weekly, from: localDate(2025, 1, 1))
        #expect(weekly.dueOccurrences(after: localDate(2025, 1, 8), through: localDate(2025, 1, 14)).isEmpty)
        #expect(weekly.dueOccurrences(after: localDate(2025, 1, 8), through: localDate(2025, 1, 15)).count == 1)
    }

    @Test func dueOccurrencesNeverRepeatWhatWasCreated() {
        let weekly = rule(.weekly, from: localDate(2025, 1, 1))
        let first = weekly.dueOccurrences(after: nil, through: localDate(2025, 1, 20))
        let second = weekly.dueOccurrences(after: first.last, through: localDate(2025, 2, 20))
        #expect(Set(first).isDisjoint(with: Set(second)))
        #expect(first.count + second.count == weekly.occurrences(from: localDate(2025, 1, 1), through: localDate(2025, 2, 20)).count)
    }

    @Test func searchMatchesAStraightScanForEveryFrequency() {
        var generator = SeededGenerator(seed: 11)
        let zones = ["UTC", "America/New_York", "Europe/London", "Asia/Kolkata", "Pacific/Auckland"]
        for frequency in RecurrenceFrequency.allCases {
            for _ in 0..<12 {
                let zone = zones.randomElement(using: &generator)!
                let start = localDate(
                    Int.random(in: 2020...2026, using: &generator), Int.random(in: 1...12, using: &generator),
                    Int.random(in: 1...28, using: &generator), Int.random(in: 0...23, using: &generator),
                    Int.random(in: 0...59, using: &generator), in: zone
                )
                let schedule = rule(frequency, from: start, zone: zone)
                let all = (0..<900).compactMap { schedule.occurrence(at: $0) }
                #expect(all.count == 900)
                #expect(zip(all, all.dropFirst()).allSatisfy { $0 < $1 })

                for _ in 0..<10 {
                    let probe = start.addingTimeInterval(Double.random(in: -86_400 * 20...86_400 * 700, using: &generator))
                    let expected = all.first { $0 > probe }
                    if let expected {
                        #expect(schedule.nextOccurrence(after: probe) == expected)
                    }
                    let from = probe, to = probe.addingTimeInterval(86_400 * 90)
                    #expect(schedule.occurrences(from: from, through: to) == all.filter { $0 >= from && $0 <= to })
                }
            }
        }
    }
}
