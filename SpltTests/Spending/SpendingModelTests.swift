import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Spending everywhere")
struct SpendingModelTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore() -> UserDefaults {
        let name = "spending-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        store.set("USD", forKey: Preferences.Key.defaultCurrency)
        return store
    }

    @Test func convertsAtTheRateOfEachExpensesDayAndKeepsTheRestApart() async throws {
        let provider = StubRatesProvider()
        let rates = RatesService(provider: provider, cache: RatesCache(directory: nil), now: { [now] in now })
        let services = try DataServices.inMemory(rates: rates, now: { [now] in now })
        let me = try services.people.ensureMe(name: "Me")
        let leo = Person(name: "Leo")
        try services.people.add(leo)
        let flat = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id, leo.id])
        let trip = SplitGroup(name: "Lisbon", currencyCode: "EUR", memberIDs: [me.id, leo.id])
        let ski = SplitGroup(name: "Ski", currencyCode: "JPY", memberIDs: [me.id, leo.id])
        let friend = SplitGroup(name: "Leo", currencyCode: "USD", kind: .friend, memberIDs: [me.id, leo.id])
        for group in [flat, trip, ski, friend] { try services.groups.create(group) }

        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let day = RatesService.dayString(threeDaysAgo, timeZone: .current)
        provider.setHistorical(table("USD", day: day, fetchedAt: now, rates: ["EUR": Decimal(string: "0.8")!]), base: "USD", day: day)

        func add(_ group: SplitGroup, _ cents: Int64, _ code: String) throws {
            try services.expenses.add(Expense(
                groupID: group.id, title: "Thing", total: Money(minorUnits: cents, currencyCode: code), date: threeDaysAgo,
                paidBy: leo.id, split: .equal(participants: [me.id, leo.id])
            ))
        }
        try add(flat, 4_000, "USD")
        try add(trip, 2_000, "EUR")
        try add(ski, 3_000, "JPY")
        try add(friend, 1_000, "USD")

        let model = SpendingModel(services: services, defaults: makeStore(), leftGroups: LeftGroupsStore(defaults: makeStore()), now: { [now] in now })
        await model.ratesLoaded()

        // $20 + €10 at 0.8 = $12.50 + $5; the yen has no rate and stays out
        #expect(model.share == usdAmount(3_750))
        #expect(model.convertedAmounts == [Money(minorUnits: 1_000, currencyCode: "EUR")])
        #expect(model.notConvertedAmounts == [Money(minorUnits: 1_500, currencyCode: "JPY")])
        #expect(model.groupRows.map(\.label) == ["Flat", "Lisbon"])
        #expect(model.friendRows.map(\.label) == ["Leo"])
        #expect(model.friendRows.first?.friend == leo.id)
        #expect(model.summary.yourExpenseCount == 4)
        #expect(model.groupCount == 3)
        #expect(model.friendCount == 1)
        #expect(model.convertedGroups.map(\.name) == ["Lisbon"])
        #expect(!model.usedPinnedRate)
        #expect(!model.isLoadingRates)
    }

    @Test func aPinnedRateWinsForItsGroup() async throws {
        let services = try DataServices.inMemory(now: { [now] in now })
        let me = try services.people.ensureMe(name: "Me")
        let trip = SplitGroup(
            name: "Lisbon", currencyCode: "EUR", memberIDs: [me.id],
            pinnedRate: PinnedRate(from: "EUR", to: "USD", rate: 2)
        )
        try services.groups.create(trip)
        try services.expenses.add(Expense(
            groupID: trip.id, title: "Tram", total: Money(minorUnits: 1_000, currencyCode: "EUR"),
            date: now.addingTimeInterval(-86_400), paidBy: me.id, split: .equal(participants: [me.id])
        ))
        let model = SpendingModel(services: services, defaults: makeStore(), leftGroups: LeftGroupsStore(defaults: makeStore()), now: { [now] in now })
        await model.ratesLoaded()
        #expect(model.share == usdAmount(2_000))
        #expect(model.usedPinnedRate)
    }
}
