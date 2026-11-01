import Foundation
import Observation

/// Owns tab selection, one navigation path per tab and the presented sheet.
/// Features push routes through it so deep links and in-app taps share one path.
@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .groups
    var sheet: AppSheet?
    /// An invite that was opened from a link or a scan, waiting for the add friend sheet to confirm it.
    var pendingInvite: FriendInvite?
    /// A friend whose settle up sheet should open as soon as their screen appears.
    var pendingSettleFriend: UUID?

    var friendsPath: [Route] = []
    var groupsPath: [Route] = []
    var activityPath: [Route] = []
    var accountPath: [Route] = []

    init(selectedTab: AppTab = .groups) {
        self.selectedTab = selectedTab
    }

    func push(_ route: Route, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        selectedTab = target
        switch target {
        case .friends: friendsPath.append(route)
        case .groups: groupsPath.append(route)
        case .activity: activityPath.append(route)
        case .account: accountPath.append(route)
        case .search: break
        }
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    func popToRoot(in tab: AppTab) {
        switch tab {
        case .friends: friendsPath = []
        case .groups: groupsPath = []
        case .activity: activityPath = []
        case .account: accountPath = []
        case .search: break
        }
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        open(link)
        return true
    }

    func open(_ link: DeepLink) {
        switch link {
        case .group(let id):
            sheet = nil
            groupsPath = [.group(id)]
            selectedTab = .groups
        case .friend(let id):
            sheet = nil
            friendsPath = [.friend(id)]
            selectedTab = .friends
        case .settle(let id):
            sheet = nil
            friendsPath = [.friend(id)]
            pendingSettleFriend = id
            selectedTab = .friends
        case .addExpense:
            sheet = .addExpense
        case .invite(let invite):
            pendingInvite = invite
            sheet = .newFriend
        }
    }
}
