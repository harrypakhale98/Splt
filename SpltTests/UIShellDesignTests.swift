import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Net position")
struct UINetPositionTests {
    private func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currencyCode: "USD") }
    private func eur(_ minor: Int64) -> Money { Money(minorUnits: minor, currencyCode: "EUR") }

    @Test func settledWhenNothingIsOwed() {
        let position = NetPosition(totals: .zero)
        #expect(position.isSettled)
        #expect(position.others.isEmpty)
    }

    @Test func netsWhatIsOwedAgainstWhatYouOwe() {
        let position = NetPosition(totals: BalanceTotals(owedToYou: [usd(60_000)], youOwe: [usd(8_815)]))
        #expect(position.primary == usd(51_185))
    }

    @Test func owingMoreGivesANegativeFigure() {
        let position = NetPosition(totals: BalanceTotals(owedToYou: [usd(1_000)], youOwe: [usd(2_500)]))
        #expect(position.primary == usd(-1_500))
    }

    @Test func equalAmountsInOneCurrencyAreSquare() {
        let position = NetPosition(totals: BalanceTotals(owedToYou: [usd(1_000)], youOwe: [usd(1_000)]))
        #expect(position.isSettled)
    }

    @Test func theBiggestSwingLeadsAndTheRestFollowByCode() {
        let totals = BalanceTotals(owedToYou: [usd(500), eur(9_000)], youOwe: [Money(minorUnits: 300, currencyCode: "GBP")])
        let position = NetPosition(totals: totals)
        #expect(position.primary == eur(9_000))
        #expect(position.others.map(\.currencyCode) == ["GBP", "USD"])
        #expect(position.others.first?.minorUnits == -300)
    }
}

@Suite("Onboarding gate")
struct UIOnboardingGateTests {
    @Test func showsOnFirstLaunch() {
        #expect(OnboardingGate.shouldShow(arguments: [], completed: false))
    }

    @Test func staysAwayOnceCompleted() {
        #expect(!OnboardingGate.shouldShow(arguments: [], completed: true))
    }

    @Test func testRunsSkipIt() {
        #expect(!OnboardingGate.shouldShow(arguments: ["-uitesting"], completed: false))
        #expect(!OnboardingGate.shouldShow(arguments: ["-sampledata"], completed: false))
    }

    @Test func theFlagForcesIt() {
        #expect(OnboardingGate.shouldShow(arguments: ["-onboarding", "-uitesting"], completed: true))
    }
}

@MainActor
@Suite("Shell design")
struct UIShellDesignTests {
    @Test func onlyGroupAndFriendRoutesZoom() {
        let id = UUID()
        #expect(Route.group(id).zoomSourceID == .group(id))
        #expect(Route.friend(id).zoomSourceID == .friend(id))
        #expect(Route.expense(id).zoomSourceID == nil)
        #expect(Route.settings.zoomSourceID == nil)
    }

    @Test func onboardingCompletionIsStored() {
        let suite = "splt.tests.onboarding.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        #expect(!Preferences(store: store).onboardingCompleted)
        Preferences(store: store).onboardingCompleted = true
        #expect(Preferences(store: store).onboardingCompleted)
        store.removePersistentDomain(forName: suite)
    }

    @Test func routerOpensTheTour() {
        let router = Router()
        #expect(!router.showsOnboarding)
        router.showsOnboarding = true
        #expect(router.showsOnboarding)
    }
}
