import Foundation
import Testing
@testable import Splt

@MainActor
@Suite("Router")
struct UIRouterTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func startsOnGroupsWithEmptyPaths() {
        let router = Router()
        #expect(router.selectedTab == .groups)
        #expect(router.sheet == nil)
        #expect(router.groupsPath.isEmpty)
    }

    @Test func pushSelectsTabAndAppendsRoute() {
        let router = Router()
        router.push(.expense(id), in: .activity)
        #expect(router.selectedTab == .activity)
        #expect(router.activityPath == [.expense(id)])
        #expect(router.groupsPath.isEmpty)
    }

    @Test func settingsRouteShowsTheAccountScreen() {
        let router = Router()
        router.accountPath = [.expense(id)]
        router.push(.settings, in: .groups)
        #expect(router.selectedTab == .groups)
        #expect(router.sheet == .account)
        #expect(router.accountPath.isEmpty)
    }

    @Test func welcomeTourWaitsForAnOpenSheetToClose() {
        let router = Router()
        router.openAccount()
        router.showWelcomeTour()
        #expect(router.sheet == nil)
        #expect(!router.showsOnboarding)
        router.sheetDidDismiss()
        #expect(router.showsOnboarding)
    }

    @Test func welcomeTourOpensAtOnceWithNoSheet() {
        let router = Router()
        router.showWelcomeTour()
        #expect(router.showsOnboarding)
    }

    @Test func activityLinkSelectsTheActivityTab() {
        let router = Router()
        router.present(.newGroup)
        router.open(.activity)
        #expect(router.selectedTab == .activity)
        #expect(router.sheet == nil)
    }

    @Test func pushWithoutTabUsesSelectedTab() {
        let router = Router(selectedTab: .friends)
        router.push(.friend(id))
        #expect(router.friendsPath == [.friend(id)])
    }

    @Test func groupSettingsRouteIsPushedOnTheGroupsTab() {
        let router = Router(selectedTab: .friends)
        router.push(.groupSettings(id), in: .groups)
        #expect(router.selectedTab == .groups)
        #expect(router.groupsPath == [.groupSettings(id)])
    }

    @Test func presentSetsSheet() {
        let router = Router()
        router.present(.newGroup)
        #expect(router.sheet == .newGroup)
    }

    @Test func groupLinkReplacesPathAndDismissesSheet() {
        let router = Router(selectedTab: .activity)
        router.present(.addExpense)
        router.groupsPath = [.group(UUID()), .group(UUID())]
        router.open(.group(id))
        #expect(router.selectedTab == .groups)
        #expect(router.groupsPath == [.group(id)])
        #expect(router.sheet == nil)
    }

    @Test func friendLinkSelectsFriendsTab() {
        let router = Router()
        router.open(.friend(id))
        #expect(router.selectedTab == .friends)
        #expect(router.friendsPath == [.friend(id)])
    }

    @Test func addExpenseLinkPresentsSheetWithoutChangingTab() {
        let router = Router(selectedTab: .friends)
        router.open(.addExpense)
        #expect(router.sheet == .addExpense)
        #expect(router.selectedTab == .friends)
    }

    @Test func openURLHandlesKnownAndUnknownLinks() {
        let router = Router()
        #expect(router.open(URL(string: "splt://add-expense")!))
        #expect(router.sheet == .addExpense)
        #expect(!router.open(URL(string: "https://example.com/group/\(id)")!))
        #expect(!router.open(URL(string: "splt://unknown")!))
    }
}

@Suite("Deep links")
struct UIDeepLinkTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func parsesGroup() {
        #expect(DeepLink(url: URL(string: "splt://group/\(id.uuidString)")!) == .group(id))
    }

    @Test func parsesFriend() {
        #expect(DeepLink(url: URL(string: "splt://friend/\(id.uuidString)")!) == .friend(id))
    }

    @Test func parsesAddExpense() {
        #expect(DeepLink(url: URL(string: "splt://add-expense")!) == .addExpense)
    }

    @Test func schemeAndHostIgnoreCase() {
        #expect(DeepLink(url: URL(string: "SPLT://Add-Expense")!) == .addExpense)
    }

    @Test func rejectsBadInput() {
        #expect(DeepLink(url: URL(string: "splt://group/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "splt://group")!) == nil)
        #expect(DeepLink(url: URL(string: "splt://add-expense/extra")!) == nil)
        #expect(DeepLink(url: URL(string: "splt://")!) == nil)
        #expect(DeepLink(url: URL(string: "http://group/\(id.uuidString)")!) == nil)
    }

    @Test func urlRoundTrips() {
        for link in [DeepLink.group(id), .friend(id), .addExpense] {
            #expect(DeepLink(url: link.url) == link)
        }
    }
}
