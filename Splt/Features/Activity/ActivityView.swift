import SpltCore
import SwiftUI

/// The Activity tab: what happened in your groups, newest first.
struct ActivityView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.activityPath) {
            Group {
                if let services {
                    ActivityContent(services: services)
                } else {
                    EmptyStateView.dataUnavailable
                }
            }
            .navigationTitle("Activity")
            .routeDestinations()
        }
    }
}

private struct ActivityContent: View {
    @Environment(Router.self) private var router
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var model: ActivityModel

    init(services: DataServices) {
        _model = State(initialValue: ActivityModel(services: services))
    }

    var body: some View {
        List {
            if !model.entries.isEmpty { typePicker }
            ForEach(model.sections) { section in
                Section {
                    RaisedRows(padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)) {
                        ForEach(section.entries, id: \.id) { entry in
                            Button { open(entry) } label: {
                                ActivityRowView(
                                    entry: entry,
                                    text: model.text(for: entry, locale: locale),
                                    groupName: model.groupName(for: entry)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                if !entry.isRead {
                                    Button("Read", systemImage: "envelope.open") { model.markRead(entry) }
                                        .tint(Ink.text)
                                }
                            }
                            .swipeActions(edge: .trailing) { paymentAction(for: entry) }
                        }
                    }
                } header: {
                    Text(model.title(for: section, locale: locale))
                        .sectionHeaderStyle()
                        // a pinned plain header has no backing of its own, so rows would draw through the date
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Depth.pageMargin + 4)
                        .padding(.vertical, 6)
                        .background(Ink.paper)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .paperBackground()
        .overlay { emptyState }
        .toolbar { toolbar }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func paymentAction(for entry: ActivityEntry) -> some View {
        switch model.paymentActions[entry.id] {
        case .undo:
            Button("Undo Payment", systemImage: "arrow.uturn.backward") { model.perform(.undo, on: entry) }
                .tint(Ink.owe)
        case .restore:
            Button("Restore Payment", systemImage: "arrow.uturn.forward") { model.perform(.restore, on: entry) }
                .tint(Ink.owed)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.entries.isEmpty, model.didLoad {
            EmptyStateView(
                title: "No activity yet",
                systemImage: "list.bullet.rectangle",
                description: "Expenses and payments from your groups will show up here.",
                actionTitle: "Add Expense",
                action: { router.present(.addExpense) }
            )
        } else if model.sections.isEmpty, model.didLoad {
            EmptyStateView(
                title: "Nothing matches",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "Try a different filter."
            )
        }
    }

    /// Switches the kind of event shown, like the group screen's picker: segmented, and scrolling with the feed.
    @ViewBuilder
    private var typePicker: some View {
        @Bindable var model = model

        Section {
            Group {
                if typeSize.isAccessibilitySize {
                    Picker("Show", selection: $model.typeFilter) {
                        ForEach(ActivityTypeFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("Show")
                } else {
                    Picker("Show", selection: $model.typeFilter) {
                        ForEach(ActivityTypeFilter.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: Depth.pageMargin, bottom: 8, trailing: Depth.pageMargin))
        }
    }

    /// Narrows the feed to one group, from the toolbar, the way the group screen filters its expenses.
    private var groupFilterMenu: some View {
        @Bindable var model = model

        return Menu {
            Picker("Group", selection: $model.groupFilter) {
                Text("All Groups").tag(GroupID?.none)
                ForEach(model.filterGroups) { group in
                    Label(group.name, systemImage: group.symbol).tag(Optional(group.id))
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: model.groupFilter != nil
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        AccountToolbarItem()
        ToolbarItemGroup(placement: .primaryAction) {
            if model.filterGroups.count > 1 { groupFilterMenu }
            Button("Mark All Read", systemImage: "envelope.open") { model.markAllRead() }
                .disabled(model.unreadCount == 0)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Add Expense", systemImage: "plus") { router.present(.addExpense) }
        }
    }

    private func open(_ entry: ActivityEntry) {
        model.markRead(entry)
        if let route = model.destination(for: entry) {
            router.push(route, in: .activity)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

#if DEBUG
#Preview("Feed") {
    ActivityView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}

#Preview("Empty") {
    ActivityView()
        .environment(Router())
        .environment(\.dataServices, try? DataServices.inMemory())
}

#Preview("Large text") {
    ActivityView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
        .dynamicTypeSize(.accessibility3)
}
#endif
