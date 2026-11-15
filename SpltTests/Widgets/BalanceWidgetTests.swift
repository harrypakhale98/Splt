import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Your Balance widget")
@MainActor
struct BalanceWidgetTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func friend(_ name: String, _ balance: [Money]) -> FriendSummary {
        FriendSummary(person: Person(name: name), balance: balance, byGroup: [])
    }

    @Test func keepsTheHeroTotalsAndTheBiggestBalancesFirst() {
        let small = friend("Sam", [usd(500)])
        let big = friend("Priya", [usd(-9_000)])
        let middle = friend("Jo", [usd(2_000)])
        let extra = friend("Alex", [usd(100)])
        let settled = friend("Lee", [])
        let totals = BalanceTotals(owedToYou: [usd(2_600)], youOwe: [usd(9_000)])
        let snapshot = BalanceWidgetPublisher.snapshot(
            summaries: [small, big, middle, extra, settled], totals: totals, hidden: [], hidesDetails: false
        )
        #expect(snapshot.owedToYou == [usd(2_600)])
        #expect(snapshot.youOwe == [usd(9_000)])
        #expect(snapshot.friends.map(\.name) == ["Priya", "Jo", "Sam"])
        #expect(snapshot.position.primary == usd(-6_400))
    }

    @Test func leavesOutHiddenFriends() {
        let hidden = friend("Sam", [usd(9_000)])
        let shown = friend("Jo", [usd(100)])
        let snapshot = BalanceWidgetPublisher.snapshot(
            summaries: [hidden, shown], totals: .zero, hidden: [hidden.id], hidesDetails: false
        )
        #expect(snapshot.friends.map(\.name) == ["Jo"])
    }

    @Test func keepsNothingWithTheLockOn() {
        let snapshot = BalanceWidgetPublisher.snapshot(
            summaries: [friend("Sam", [usd(9_000)])], totals: BalanceTotals(owedToYou: [usd(9_000)], youOwe: []),
            hidden: [], hidesDetails: true
        )
        #expect(snapshot == .hidden)
        #expect(snapshot.friends.isEmpty && snapshot.owedToYou.isEmpty && snapshot.youOwe.isEmpty)
    }

    @Test func sentenceMatchesTheHero() {
        #expect(NetPosition.sentence(owedToYou: [], youOwe: []) == "Nobody owes anything.")
        #expect(NetPosition.sentence(owedToYou: [usd(1_000)], youOwe: []).hasPrefix("You're owed "))
        #expect(NetPosition.sentence(owedToYou: [], youOwe: [usd(1_000)]).hasPrefix("You owe "))
    }

    @Test func survivesAWriteAndRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "BalanceWidgetTests"))
        defaults.removePersistentDomain(forName: "BalanceWidgetTests")
        #expect(BalanceWidgetSnapshot.load(from: defaults) == nil)
        let snapshot = BalanceWidgetSnapshot(
            owedToYou: [usd(100)], friends: [.init(id: UUID(), name: "Sam", balance: [usd(100)])]
        )
        snapshot.save(to: defaults)
        #expect(BalanceWidgetSnapshot.load(from: defaults) == snapshot)
    }
}
