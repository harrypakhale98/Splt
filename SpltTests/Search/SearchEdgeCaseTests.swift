import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Search edge cases")
@MainActor
struct SearchEdgeCaseTests {
    private struct NoModel: SearchIntentReader {
        var isAvailable: Bool { false }
        func read(_ query: String, names: [String]) async throws -> SearchIntentReading { SearchIntentReading() }
    }

    private func model(_ fixture: Fixture) -> SearchModel {
        let defaults = UserDefaults(suiteName: "splt-tests-\(UUID().uuidString)") ?? .standard
        let start = fixture.clock.start
        return SearchModel(
            services: fixture.services, recentStore: RecentSearchesStore(defaults: defaults),
            reader: NoModel(), now: { start }
        )
    }

    private func parser(_ fixture: Fixture, extra: [Person] = []) -> NaturalSearchParser {
        NaturalSearchParser(people: [fixture.me, fixture.sam, fixture.priya] + extra, now: fixture.clock.start)
    }

    @Test func aBareNumberStillFindsItsAmount() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Sofa", cents: 200_000)
        let search = model(fixture)
        search.query = "2000"
        await search.search()
        #expect(search.expenses.map(\.title) == ["Sofa"])
        #expect(search.understood.isEmpty)
    }

    @Test func aQuestionWithNoMatchStaysEmpty() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Sofa", cents: 200_000)
        let search = model(fixture)
        search.query = "dinners last year"
        await search.search()
        #expect(search.expenses.isEmpty)
        #expect(!search.understood.isEmpty)
    }
}
