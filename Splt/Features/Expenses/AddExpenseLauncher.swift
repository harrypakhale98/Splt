import SpltCore
import SwiftUI

/// The add expense sheet opened from anywhere in the app. It starts in the group you used last,
/// or your newest group.
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
        if let remembered = UUID(uuidString: lastGroupID), groups.contains(where: { $0.id.rawValue == remembered }) {
            return .group(GroupID(rawValue: remembered))
        }
        return groups.first.map { .group($0.id) } ?? .noGroups
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
