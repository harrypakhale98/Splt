import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Recap backdrops")
@MainActor
struct RecapBackdropTests {
    private let ana = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    private let ben = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!)

    private func setup() throws -> (SplitGroup, RecapStats) {
        PersonColorBook.reset()
        PersonColorBook.update(
            people: [Person(id: ana, name: "Ana"), Person(id: ben, name: "Ben", createdAt: Date(timeIntervalSinceNow: 60))],
            me: nil
        )
        let group = SplitGroup(
            id: GroupID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000C3")!),
            name: "Trip", currencyCode: "USD", kind: .trip, memberIDs: [ana, ben],
            tripStart: utcDate(2026, 5, 8), tripEnd: utcDate(2026, 5, 10)
        )
        let expenses = [
            Expense(
                title: "Hotel", total: usdAmount(9000), date: utcDate(2026, 5, 8), category: .lodging,
                paidBy: ben, split: .equal(participants: [ana, ben])
            ),
            Expense(
                title: "Lunch", total: usdAmount(1000), date: utcDate(2026, 5, 9), category: .dining,
                paidBy: ana, split: .equal(participants: [ana, ben])
            )
        ]
        let stats = try #require(RecapStats(
            group: group, expenses: expenses, names: [ana: "Ana", ben: "Ben"], now: utcDate(2026, 5, 20),
            calendar: GroupsTestCalendar.utc
        ))
        return (group, stats)
    }

    private let pages: [RecapPage] = [.total, .days, .biggest, .payer, .categories, .summary]

    @Test func everyPageStripHoldsEachMemberOnce() throws {
        let (group, stats) = try setup()
        for page in pages {
            let segments = RecapBackdrop.segments(for: page, members: group.memberIDs, stats: stats)
            #expect(segments.map(\.person) == group.memberIDs, "\(page)")
            #expect(segments.allSatisfy { $0.weight > 0 })
        }
    }

    @Test func thePayerPageGivesTheTopPayerTheWidestShare() throws {
        let (group, stats) = try setup()
        let segments = RecapBackdrop.segments(for: .payer, members: group.memberIDs, stats: stats)
        let widest = try #require(segments.max { $0.weight < $1.weight })
        #expect(widest.person == ben)
        #expect(widest.weight > (segments.first { $0.person == ana }?.weight ?? 0))
    }

    @Test func otherPagesShareTheStripEvenly() throws {
        let (group, stats) = try setup()
        for page in pages where page != .payer {
            let weights = Set(RecapBackdrop.segments(for: page, members: group.memberIDs, stats: stats).map(\.weight))
            #expect(weights.count == 1, "\(page)")
        }
    }
}
