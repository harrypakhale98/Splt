import SwiftUI

struct GroupsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.groupsPath) {
            EmptyStateView(
                title: "No Groups Yet",
                systemImage: "person.3",
                description: "Create a group for a trip, a home or a night out.",
                actionTitle: "Create Group",
                action: { router.present(.newGroup) }
            )
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Group", systemImage: "plus") {
                        router.present(.newGroup)
                    }
                }
            }
            .routeDestinations()
        }
    }
}

#Preview {
    GroupsView()
        .environment(Router())
}
