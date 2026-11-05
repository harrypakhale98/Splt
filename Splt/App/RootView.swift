import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @State private var unread: UnreadActivityStore?

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
        .settleUndoBanner()
        .task {
            if unread == nil, let services { unread = UnreadActivityStore(services: services) }
        }
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
