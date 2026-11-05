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
                    EmptyStateView(
                        title: "No Activity Yet",
                        systemImage: "list.bullet.rectangle",
                        description: "Splt couldn't open its storage."
                    )
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

    @State private var model: ActivityModel

    init(services: DataServices) {
        _model = State(initialValue: ActivityModel(services: services))
    }

    var body: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.entries, id: \.id) { entry in
                        Button { open(entry) } label: {
                            ActivityRowView(
                                entry: entry,
                                text: model.text(for: entry, locale: locale),
                                groupName: model.groupName(for: entry)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Ink.hairline)
                        .swipeActions(edge: .leading) {
                            if !entry.isRead {
                                Button("Read", systemImage: "envelope.open") { model.markRead(entry) }
                                    .tint(Ink.text)
                            }
                        }
                        .swipeActions(edge: .trailing) { paymentAction(for: entry) }
                    }
                } header: {
                    Text(model.title(for: section, locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .paperBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.entries.isEmpty { ActivityFilterChips(model: model) }
        }
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
                title: "No Activity Yet",
                systemImage: "list.bullet.rectangle",
                description: "Expenses and payments from your groups will show up here.",
                actionTitle: "Add Expense",
                action: { router.present(.addExpense) }
            )
        } else if model.sections.isEmpty, model.didLoad {
            ContentUnavailableView(
                "Nothing Matches",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try a different filter.")
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        AccountToolbarItem()
        ToolbarItem(placement: .primaryAction) {
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
