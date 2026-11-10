import Foundation
import Observation

/// Owns tab selection, one navigation path per tab and the presented sheet.
/// Features push routes through it so deep links and in-app taps share one path.
@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .groups
    var sheet: AppSheet?
    /// True while an open form holds typed work. A link then waits, so it cannot close the form
    /// or the screen under it, and opens once the form is gone.
    var hasUnsavedForm = false {
        didSet {
            guard !hasUnsavedForm, let link = waitingLink else { return }
            waitingLink = nil
            open(link)
        }
    }
    @ObservationIgnored private var waitingLink: DeepLink?
    /// Counts the links that were opened. A screen watches it to close the sheets it presents
    /// itself, which the router cannot reach, so a link never opens out of sight under one.
    private(set) var openedLinks = 0
    /// The welcome tour, shown on first launch and from Account.
    var showsOnboarding = false
    private var showsTourAfterSheet = false
    /// An invite that was opened from a link or a scan, waiting for the add friend sheet to confirm it.
    var pendingInvite: FriendInvite?
    /// A friend whose settle up sheet should open as soon as their screen appears.
    var pendingSettleFriend: UUID?

    var friendsPath: [Route] = []
    var groupsPath: [Route] = []
    var activityPath: [Route] = []
    var searchPath: [Route] = []
    var accountPath: [Route] = []

    init(selectedTab: AppTab = .groups) {
        self.selectedTab = selectedTab
    }

    func push(_ route: Route, in tab: AppTab? = nil) {
        if route == .settings {
            // the settings sections are the Account screen itself
            openAccount()
            return
        }
        let target = tab ?? selectedTab
        selectedTab = target
        switch target {
        case .friends: friendsPath.append(route)
        case .groups: groupsPath.append(route)
        case .activity: activityPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    /// Opens the Account sheet at its top, whatever tab you are on.
    func openAccount() {
        accountPath = []
        sheet = .account
    }

    /// Shows the tour, closing any sheet first because a full screen cover can't open over one.
    func showWelcomeTour() {
        guard sheet != nil else {
            showsOnboarding = true
            return
        }
        showsTourAfterSheet = true
        sheet = nil
    }

    func sheetDidDismiss() {
        guard showsTourAfterSheet else { return }
        showsTourAfterSheet = false
        showsOnboarding = true
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        open(link)
        return true
    }

    /// Shows what a link points at. The router's own sheet is closed here and the sheets screens
    /// present themselves close through `closingSheetsOnLink`, unless a form holds unsaved work.
    func open(_ link: DeepLink) {
        guard !hasUnsavedForm else {
            waitingLink = link
            return
        }
        openedLinks += 1
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
        case .activity:
            sheet = nil
            selectedTab = .activity
        case .invite(let invite):
            pendingInvite = invite
            sheet = .newFriend
        }
    }
}
