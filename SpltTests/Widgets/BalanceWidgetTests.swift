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
        // each friend keeps the avatar the Friends tab draws
        #expect(snapshot.friends[0].initials == "P")
        let hue = PersonPalette.index(for: big.id)
        #expect(snapshot.friends[0].color.lightFill == PersonPalette.hexPair(at: hue, dark: false).fill)
        #expect(snapshot.friends[0].color.darkText == PersonPalette.hexPair(at: hue, dark: true).text)
        #expect(snapshot.position.primary == usd(-6_400))
        // the strip runs as under the Friends tab hero: everyone who owes you, then everyone you owe
        let stripFill = { (summary: FriendSummary) in PersonPalette.hexPair(at: PersonPalette.index(for: summary.id), dark: false).fill }
        #expect(snapshot.strip.map(\.lightFill) == [small, middle, extra, big].map(stripFill))
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

    @Test func savesOnlyWhatChanged() throws {
        let defaults = try #require(UserDefaults(suiteName: "BalanceWidgetTests.saves"))
        defaults.removePersistentDomain(forName: "BalanceWidgetTests.saves")
        let first = BalanceWidgetSnapshot(owedToYou: [usd(100)])
        #expect(BalanceWidgetPublisher.saveIfChanged(first, to: defaults))
        // the same balance again leaves the widget alone
        #expect(!BalanceWidgetPublisher.saveIfChanged(first, to: defaults))
        #expect(BalanceWidgetPublisher.saveIfChanged(BalanceWidgetSnapshot(owedToYou: [usd(250)]), to: defaults))
        #expect(BalanceWidgetSnapshot.load(from: defaults)?.owedToYou == [usd(250)])
    }

    @Test func survivesAWriteAndRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "BalanceWidgetTests"))
        defaults.removePersistentDomain(forName: "BalanceWidgetTests")
        #expect(BalanceWidgetSnapshot.load(from: defaults) == nil)
        let snapshot = BalanceWidgetSnapshot(
            owedToYou: [usd(100)],
            friends: [.init(
                id: UUID(), name: "Sam", balance: [usd(100)], initials: "S",
                color: .init(lightFill: 0x96437F, lightText: 0xFFFFFF, darkFill: 0xDD9CCB, darkText: 0x0E0E12)
            )]
        )
        snapshot.save(to: defaults)
        #expect(BalanceWidgetSnapshot.load(from: defaults) == snapshot)
    }
}
