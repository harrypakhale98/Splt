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

    @Test func replacingTheTopStaysOnTheTabTheScreenIsIn() {
        let other = UUID()
        let router = Router(selectedTab: .search)
        router.searchPath = [.group(other), .friend(other)]
        router.replaceTop(with: .friend(id))
        #expect(router.selectedTab == .search)
        #expect(router.searchPath == [.group(other), .friend(id)])
        #expect(router.friendsPath.isEmpty)

        router.selectedTab = .friends
        router.friendsPath = [.friend(other)]
        router.replaceTop(with: .friend(id))
        #expect(router.friendsPath == [.friend(id)])
    }

    @Test func anInvitationGoesWhenTheAddFriendSheetIsSwipedAway() {
        let router = Router()
        let invite = FriendInvite(name: "Maya Chen", personID: id)
        router.open(.invite(invite))
        #expect(router.sheet == .newFriend)
        #expect(router.pendingInvite == invite)
        // a swipe down only clears the sheet binding
        router.sheet = nil
        #expect(router.pendingInvite == nil)

        router.present(.newFriend)
        #expect(router.pendingInvite == nil)
    }

    @Test func anInvitationSurvivesReplacingAnotherSheet() {
        let router = Router()
        let invite = FriendInvite(name: "Maya Chen", personID: id)
        router.present(.account)
        router.open(.invite(invite))
        #expect(router.sheet == .newFriend)
        #expect(router.pendingInvite == invite)

        let second = FriendInvite(name: "Zoe", personID: nil)
        router.open(.invite(second))
        #expect(router.pendingInvite == second)
        router.open(.group(id))
        #expect(router.pendingInvite == nil)
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

    @Test func aLinkWaitsForAFormWithUnsavedWork() {
        let router = Router()
        router.sheet = .addExpense
        router.hasUnsavedForm = true
        router.open(.group(id))
        #expect(router.sheet == .addExpense)
        #expect(router.groupsPath.isEmpty)

        router.hasUnsavedForm = false
        #expect(router.groupsPath == [.group(id)])
    }

    @Test func aLinkClosesASheetWithNothingToLose() {
        let router = Router()
        router.sheet = .addExpense
        router.open(.group(id))
        #expect(router.sheet == nil)
        #expect(router.groupsPath == [.group(id)])
    }

    @Test func anOpenedLinkTellsScreensToCloseTheirOwnSheets() {
        let router = Router()
        #expect(router.openedLinks == 0)
        router.open(.group(id))
        #expect(router.openedLinks == 1)
        router.open(.activity)
        router.open(.addExpense)
        #expect(router.openedLinks == 3)
        #expect(!router.open(URL(string: "splt://unknown")!))
        #expect(router.openedLinks == 3)
    }

    @Test func aWaitingLinkClosesNothingUntilTheFormIsGone() {
        let router = Router()
        router.hasUnsavedForm = true
        router.open(.friend(id))
        #expect(router.openedLinks == 0)
        router.hasUnsavedForm = false
        #expect(router.openedLinks == 1)
        #expect(router.friendsPath == [.friend(id)])
    }

    @Test func onlyTheLatestLinkIsKeptWhileAFormIsOpen() {
        let router = Router()
        router.sheet = .addExpense
        router.hasUnsavedForm = true
        router.open(.friend(id))
        router.open(.group(id))
        router.hasUnsavedForm = false
        #expect(router.groupsPath == [.group(id)])
        #expect(router.friendsPath.isEmpty)
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
