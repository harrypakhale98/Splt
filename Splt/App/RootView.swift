import SwiftUI

struct RootView: View {
    @Environment(\.dataServices) private var services

    var body: some View {
        // the unread store is made with the tabs, so the Activity badge is there on the first frame
        RootTabs(services: services)
            .id(services.map { ObjectIdentifier($0) })
    }
}

private struct RootTabs: View {
    @Environment(Router.self) private var router
    @State private var unread: UnreadActivityStore?

    init(services: DataServices?) {
        _unread = State(initialValue: services.map { UnreadActivityStore(services: $0) })
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Groups", systemImage: "square.stack", value: AppTab.groups) {
                GroupsListView()
            }
            Tab("Friends", systemImage: "person.2", value: AppTab.friends) {
                FriendsView()
            }
            Tab("Activity", systemImage: "clock", value: AppTab.activity) {
                ActivityView()
            }
            .badge(unread?.count ?? 0)
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .generatesRecurringExpenses()
        .foldsItemClaims()
        .settleUndoBanner()
        .sheet(item: $router.sheet, onDismiss: router.sheetDidDismiss) { sheet in
            switch sheet {
            case .newGroup:
                CreateGroupView { router.open(.group($0.rawValue)) }
            case .addExpense:
                AddExpenseLauncher()
            case .newFriend:
                AddFriendView()
            case .account:
                AccountView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
}
