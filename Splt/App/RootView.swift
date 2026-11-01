import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

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
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .newGroup:
                CreateGroupView { router.open(.group($0.rawValue)) }
            case .addExpense:
                AddExpenseLauncher()
            default:
                PlaceholderSheet(sheet: sheet)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
}
