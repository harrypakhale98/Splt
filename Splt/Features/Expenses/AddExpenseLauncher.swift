import SpltCore
import SwiftUI

/// The add expense sheet opened from anywhere in the app. It starts in the group you used last,
/// or your newest group, and the form lets you switch.
struct AddExpenseLauncher: View {
    @Environment(\.dataServices) private var services
    @Environment(Router.self) private var router
    @AppStorage(ExpenseFormModel.lastGroupKey) private var lastGroupID = ""

    var body: some View {
        if let groupID = resolvedGroup {
            ExpenseFormView(mode: .add(groupID: groupID, prefill: nil))
        } else {
            NavigationStack {
                EmptyStateView(
                    title: "Create a Group First",
                    systemImage: "person.3",
                    description: "Expenses are shared inside a group. Make one for your trip, home or night out.",
                    actionTitle: "Create Group",
                    action: { router.present(.newGroup) }
                )
                .navigationTitle("New Expense")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", role: .close) { router.sheet = nil }
                    }
                }
            }
        }
    }

    private var resolvedGroup: GroupID? {
        let left = LeftGroupsStore()
        let groups = ((try? services?.groups.groups(includeArchived: false)) ?? []).filter { !left.contains($0.id) }
        if let remembered = UUID(uuidString: lastGroupID), groups.contains(where: { $0.id.rawValue == remembered }) {
            return GroupID(rawValue: remembered)
        }
        return groups.first?.id
    }
}

#if DEBUG
#Preview("With groups") {
    let scene = ExpensePreviewSupport.scene()
    AddExpenseLauncher()
        .environment(\.dataServices, scene.services)
        .environment(Router())
}

#Preview("No groups") {
    AddExpenseLauncher()
        .environment(\.dataServices, try? DataServices.inMemory())
        .environment(Router())
}
#endif
