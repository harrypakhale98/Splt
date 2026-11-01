import SwiftUI

struct FriendsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.friendsPath) {
            EmptyStateView(
                title: "No Friends Yet",
                systemImage: "person.2",
                description: "Add friends to split bills and see who owes what.",
                actionTitle: "Add Friend",
                action: { router.present(.newFriend) }
            )
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Friend", systemImage: "person.badge.plus") {
                        router.present(.newFriend)
                    }
                }
            }
            .routeDestinations()
        }
    }
}

#Preview {
    FriendsView()
        .environment(Router())
}
