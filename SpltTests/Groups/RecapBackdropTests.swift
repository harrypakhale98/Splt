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

    @Test func everyPageHasOneToThreeDistinctHues() throws {
        let (group, stats) = try setup()
        for page in pages {
            let hues = RecapBackdrop.hues(for: page, group: group, stats: stats)
            #expect((1...3).contains(hues.count), "\(page)")
            #expect(Set(hues).count == hues.count, "\(page)")
            #expect(hues.allSatisfy { (0..<PersonPalette.count).contains($0) })
        }
    }

    @Test func thePayerPageUsesThePayersColor() throws {
        let (group, stats) = try setup()
        let hues = RecapBackdrop.hues(for: .payer, group: group, stats: stats)
        #expect(hues.first == PersonPalette.index(for: ben, in: group.memberIDs))
    }

    @Test func theBiggestAndCategoryPagesUseTheCategoryColor() throws {
        let (group, stats) = try setup()
        let lodging = RecapBackdrop.categoryHue(.lodging)
        #expect(RecapBackdrop.hues(for: .biggest, group: group, stats: stats).first == lodging)
        #expect(RecapBackdrop.hues(for: .categories, group: group, stats: stats).first == lodging)
    }

    @Test func theStoryOpensAndClosesInTheGroupsOwnColors() throws {
        let (group, stats) = try setup()
        let own = GroupHeroTint.hues(for: group)
        #expect(RecapBackdrop.hues(for: .total, group: group, stats: stats) == own)
        #expect(RecapBackdrop.hues(for: .summary, group: group, stats: stats) == own)
    }

    @Test func pagesDoNotAllLookTheSame() throws {
        let (group, stats) = try setup()
        let firsts = Set(pages.map { RecapBackdrop.hues(for: $0, group: group, stats: stats).first })
        #expect(firsts.count >= 3)
    }

    @Test func categoryHuesAreStable() {
        #expect(RecapBackdrop.categoryHue(.dining) == RecapBackdrop.categoryHue(.dining))
        let hues = Set(ExpenseCategory.allCases.map(RecapBackdrop.categoryHue))
        #expect(hues.count >= 6)
    }
}
