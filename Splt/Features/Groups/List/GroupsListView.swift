import SpltCore
import SwiftUI

/// The Groups tab: your balance in every group, with search, archive and a way to start a new one.
struct GroupsListView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.groupsPath) {
            Group {
                if let services {
                    GroupsListContent(services: services)
                } else {
                    EmptyStateView(
                        title: "No Groups Yet",
                        systemImage: "person.3",
                        description: "Create a group for a trip, a home or a night out.",
                        actionTitle: "Create Group",
                        action: { router.present(.newGroup) }
                    )
                    .navigationTitle("Groups")
                }
            }
            .routeDestinations()
        }
    }
}

private struct GroupsListContent: View {
    @Environment(Router.self) private var router
    @State private var model: GroupsListViewModel
    @State private var pendingDelete: SplitGroup?
    @State private var showsImport = false

    init(services: DataServices) {
        _model = State(initialValue: GroupsListViewModel(services: services))
    }

    var body: some View {
        @Bindable var model = model

        List {
            if model.hasGroups && !model.isSearching {
                OverallBalanceSection(totals: model.totals)
            }
            if !model.active.isEmpty {
                Section {
                    ForEach(model.active) { summary in
                        row(summary)
                    }
                }
            }
            if !model.archived.isEmpty {
                Section("Archived") {
                    ForEach(model.archived) { summary in
                        row(summary)
                    }
                }
            }
        }
        .overlay { emptyState }
        .navigationTitle("Groups")
        .searchable(text: $model.query, prompt: "Search groups")
        .refreshable { model.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Group", systemImage: "plus") {
                    router.present(.newGroup)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Import from Splitwise", systemImage: "square.and.arrow.down") {
                    showsImport = true
                }
            }
        }
        .sheet(isPresented: $showsImport) {
            SplitwiseImportSheet()
        }
        .onAppear { model.refresh() }
        .confirmationDialog(
            "Delete Group?", isPresented: deleteBinding, titleVisibility: .visible, presenting: pendingDelete
        ) { group in
            Button("Delete \(group.name)", role: .destructive) {
                model.delete(group.id)
            }
        } message: { _ in
            Text("Every expense and payment in this group is removed for everyone. This can't be undone.")
        }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.hasGroups {
            EmptyStateView(
                title: "No Groups Yet",
                systemImage: "person.3",
                description: "Create a group for a trip, a home or a night out.",
                actionTitle: "Create Group",
                action: { router.present(.newGroup) }
            )
        } else if model.isSearching && !model.hasResults {
            ContentUnavailableView.search(text: model.query)
        }
    }

    private func row(_ summary: GroupSummary) -> some View {
        NavigationLink(value: Route.group(summary.group.id.rawValue)) {
            GroupRowView(summary: summary)
        }
        .swipeActions(edge: .trailing) {
            if summary.group.isArchived {
                Button("Restore", systemImage: "tray.and.arrow.up") {
                    model.restore(summary.group.id)
                }
                .tint(.blue)
            } else {
                Button("Archive", systemImage: "archivebox") {
                    model.archive(summary.group.id)
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if summary.group.isArchived {
                Button("Restore", systemImage: "tray.and.arrow.up") {
                    model.restore(summary.group.id)
                }
            } else {
                Button("Archive", systemImage: "archivebox") {
                    model.archive(summary.group.id)
                }
            }
            Button("Group Settings", systemImage: "gearshape") {
                router.push(.groupSettings(summary.group.id.rawValue), in: .groups)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingDelete = summary.group
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

#if DEBUG
#Preview("Sample data") {
    GroupsListView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}

#Preview("Empty") {
    GroupsListView()
        .environment(Router())
        .environment(\.dataServices, try? DataServices.inMemory())
}
#endif
