import SpltCore
import SwiftUI

/// The add expense sheet opened from anywhere in the app. It starts in the group you used last,
/// or your newest group. Expenses with one friend are started from the Friends tab instead.
struct AddExpenseLauncher: View {
    @Environment(\.dataServices) private var services
    @Environment(Router.self) private var router
    @AppStorage(ExpenseFormModel.lastGroupKey) private var lastGroupID = ""
    /// The group, looked up once when the sheet opens. Saving changes the remembered group,
    /// and the open form must not switch under the person.
    @State private var resolution: Resolution?

    private enum Resolution: Equatable {
        case group(GroupID)
        case noGroups
    }

    var body: some View {
        Group {
            switch resolution {
            case .group(let groupID)?:
                ExpenseFormView(mode: .add(groupID: groupID, prefill: nil))
            case .noGroups?:
                noGroups
            case nil:
                Ink.paper.ignoresSafeArea()
            }
        }
        .onAppear {
            if resolution == nil { resolution = resolve() }
        }
    }

    private var noGroups: some View {
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

    private func resolve() -> Resolution {
        let groups = (try? services?.groups.groups(includeArchived: false)) ?? []
        return Self.startingGroup(among: groups, lastUsed: lastGroupID, left: LeftGroupsStore()).map { .group($0) } ?? .noGroups
    }

    /// The group you used last, or the newest one. A friend's direct group is left out even when it
    /// was used last, since it is not a group you see on the Groups tab.
    static func startingGroup(among groups: [SplitGroup], lastUsed: String, left: LeftGroupsStore) -> GroupID? {
        let open = groups.filter { $0.kind != .friend && !left.contains($0.id) }
        if let remembered = UUID(uuidString: lastUsed), open.contains(where: { $0.id.rawValue == remembered }) {
            return GroupID(rawValue: remembered)
        }
        return open.first?.id
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
