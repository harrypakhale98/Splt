import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @State private var unread: UnreadActivityStore?

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Friends", systemImage: "person.2", value: AppTab.friends) {
                FriendsView()
            }
            Tab("Groups", systemImage: "person.3", value: AppTab.groups) {
                GroupsListView()
            }
            Tab("Activity", systemImage: "list.bullet.rectangle", value: AppTab.activity) {
                ActivityView()
            }
            .badge(unread?.count ?? 0)
            Tab("Account", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
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
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .newGroup:
                CreateGroupView { router.open(.group($0.rawValue)) }
            case .addExpense:
                AddExpenseLauncher()
            case .newFriend:
                AddFriendView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
}
