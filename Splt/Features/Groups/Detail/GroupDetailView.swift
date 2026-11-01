import SpltCore
import SwiftUI

/// One group: your balance, its expenses, who owes whom and the totals. Pushed with `Route.group`.
struct GroupDetailView: View {
    let groupID: GroupID

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            GroupDetailContent(groupID: groupID, services: services)
        } else {
            EmptyStateView(
                title: "Group Not Found",
                systemImage: "person.3",
                description: "Splt couldn't open its storage."
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct GroupDetailContent: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var model: GroupDetailViewModel
    @State private var showsAddExpense = false
    @State private var showsSettings = false
    @State private var showsActivity = false
    @State private var showsCustomRange = false
    @State private var settleRoute: SettleRoute?
    @State private var summary: String?

    init(groupID: GroupID, services: DataServices) {
        _model = State(initialValue: GroupDetailViewModel(groupID: groupID, services: services))
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if let group = model.group {
                List {
                    GroupHeaderSection(
                        group: group,
                        memberCount: model.members.count,
                        totals: model.myTotals,
                        canSettle: !model.transfers.isEmpty,
                        onSettleUp: { settleRoute = model.settleRoute() }
                    )
                    segmentPicker
                    content
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.filter.query, prompt: "Search expenses")
                .toolbar { toolbar }
            } else if model.didLoad {
                EmptyStateView(
                    title: "Group Not Found",
                    systemImage: "person.3",
                    description: "This group may have been deleted."
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: model.filter.query) {
            if !model.filter.query.isEmpty { model.segment = .expenses }
        }
        .onChange(of: model.filter.period) {
            if model.filter.period == .custom { showsCustomRange = true }
        }
        .task(id: model.insightInput) {
            guard let input = model.insightInput else {
                summary = nil
                return
            }
            summary = await InsightSummarizer().summarize(input)
        }
        .sheet(isPresented: $showsAddExpense) {
            ExpenseFormView(mode: .add(groupID: model.groupID, prefill: nil))
        }
        .sheet(isPresented: $showsSettings) {
            GroupSettingsView(groupID: model.groupID, onGroupRemoved: { dismiss() })
        }
        .sheet(isPresented: $showsCustomRange) {
            DateRangeSheet(start: $model.filter.customStart, end: $model.filter.customEnd)
        }
        .sheet(item: $settleRoute) { route in
            SettleUpStubSheet(route: route, names: model.names, currentPerson: model.me?.id)
        }
        .navigationDestination(isPresented: $showsActivity) {
            GroupActivityView(entries: model.activity, text: model.activityText)
        }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var segmentPicker: some View {
        @Bindable var model = model

        Section {
            if typeSize.isAccessibilitySize {
                Picker("Show", selection: $model.segment) {
                    ForEach(GroupDetailViewModel.Segment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Show", selection: $model.segment) {
                    ForEach(GroupDetailViewModel.Segment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.segment {
        case .expenses:
            expensesContent
        case .balances:
            GroupBalancesSection(model: model, onSettle: { settleRoute = model.settleRoute(for: $0) })
        case .totals:
            GroupTotalsSection(model: model, summary: summary)
        }
    }

    @ViewBuilder
    private var expensesContent: some View {
        if let recap = model.recap, !model.filter.isActive {
            TripRecapSection(recap: recap)
        }
        if model.filter.isFiltering {
            Section {
                Button("Clear Filters", systemImage: "xmark.circle") {
                    model.filter.clearFilters()
                }
            }
        }
        if model.expenses.isEmpty {
            Section {
                EmptyStateView(
                    title: "No Expenses",
                    systemImage: "tray",
                    description: "Add the first expense to start splitting.",
                    actionTitle: "Add Expense",
                    action: { showsAddExpense = true }
                )
                .listRowBackground(Color.clear)
            }
        } else if model.sections.isEmpty {
            Section {
                ContentUnavailableView.search(text: model.filter.query)
                    .listRowBackground(Color.clear)
            }
        } else {
            ForEach(model.sections) { section in
                Section(model.sectionTitle(section, locale: locale)) {
                    ForEach(section.expenses) { expense in
                        NavigationLink(value: Route.expense(expense.id.rawValue)) {
                            ExpenseRowView(expense: expense, currentPerson: model.me?.id, people: model.members)
                        }
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu
            Button("Add Expense", systemImage: "plus") {
                showsAddExpense = true
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button("Activity", systemImage: "list.bullet.rectangle") {
                showsActivity = true
            }
            Button("Recurring Expenses", systemImage: "arrow.triangle.2.circlepath") {
                router.push(.recurringExpenses(model.groupID.rawValue))
            }
            Button("Group Settings", systemImage: "gearshape") {
                showsSettings = true
            }
        }
    }

    private var filterMenu: some View {
        @Bindable var model = model

        return Menu {
            Picker("Paid By", selection: $model.filter.payer) {
                Text("Anyone").tag(PersonID?.none)
                ForEach(model.payers) { person in
                    Text(model.name(of: person.id)).tag(Optional(person.id))
                }
            }
            Picker("Category", selection: $model.filter.category) {
                Text("All Categories").tag(ExpenseCategory?.none)
                ForEach(model.categories, id: \.self) { category in
                    Label(category.title, systemImage: category.symbolName).tag(Optional(category))
                }
            }
            Picker("Date", selection: $model.filter.period) {
                ForEach(ExpenseFilter.Period.allCases) { Text($0.title).tag($0) }
            }
            if model.filter.isFiltering {
                Button("Clear Filters", systemImage: "xmark.circle", role: .destructive) {
                    model.filter.clearFilters()
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: model.filter.isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Two dates for the custom filter period.
private struct DateRangeSheet: View {
    @Binding var start: Date
    @Binding var end: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview("Trip") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    NavigationStack {
        if let trip {
            GroupDetailView(groupID: trip.id)
        }
    }
    .environment(Router())
    .environment(\.dataServices, services)
}

#Preview("Flat") {
    let services = SampleData.previewServices()
    let flat = (try? services.groups.groups(includeArchived: false).first { $0.name == "Flat 4B" }) ?? nil
    NavigationStack {
        if let flat {
            GroupDetailView(groupID: flat.id)
        }
    }
    .environment(Router())
    .environment(\.dataServices, services)
}
#endif
