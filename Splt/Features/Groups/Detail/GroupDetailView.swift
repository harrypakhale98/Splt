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
    @State private var condenseProgress = 0.0
    @State private var showsRecap = false

    private var condensed: Bool { condenseProgress > 0.85 }

    init(groupID: GroupID, services: DataServices) {
        _model = State(initialValue: GroupDetailViewModel(groupID: groupID, services: services))
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if let group = model.group {
                List {
                    if model.segment == .expenses {
                        GroupHeroSection(
                            group: group,
                            members: model.members,
                            totals: model.myTotals,
                            canSettle: !model.transfers.isEmpty,
                            onSettleUp: { settleRoute = model.settleRoute() }
                        )
                    }
                    segmentPicker
                    content
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
                .listSectionSpacing(10)
                .paperBackground()
                .onScrollGeometryChange(for: Double.self) { geometry in
                    let offset = geometry.contentOffset.y + geometry.contentInsets.top
                    return min(max(offset / 220, 0), 1)
                } action: { _, progress in
                    condenseProgress = progress
                }
                .modifier(ExpenseSearch(isOn: model.segment == .expenses, text: $model.filter.query))
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
        .fullScreenCover(isPresented: $showsRecap) {
            if let group = model.group, let stats = model.recapStats {
                TripRecapStoryView(group: group, stats: stats, members: group.memberIDs, summary: summary)
            }
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
            SettleUpSheet(route: route)
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
                .labelsHidden()
                .accessibilityLabel("Show")
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
            GroupTotalsSection(model: model, summary: summary, onRecap: { showsRecap = true })
        }
    }

    @ViewBuilder
    private var expensesContent: some View {
        let sections = model.sections
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
        } else if sections.isEmpty {
            Section {
                ContentUnavailableView.search(text: model.filter.query)
                    .listRowBackground(Color.clear)
            }
        } else {
            ForEach(sections) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        NavigationLink(value: Route.expense(expense.id.rawValue)) {
                            GroupExpenseRow(
                                expense: expense, currentPerson: model.me?.id,
                                people: model.members, members: model.group?.memberIDs ?? []
                            )
                        }
                    }
                } header: {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout())
                    layout {
                        Text(model.sectionTitle(section, locale: locale))
                        if !typeSize.isAccessibilitySize { Spacer() }
                        if let total = section.total {
                            Text(MoneyFormatting.string(total, locale: locale))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.group?.name ?? "")
                .font(.headline)
                .lineLimit(1)
            .opacity(condensed || model.segment != .expenses ? 1 : 0)
            .motion(.smooth, value: condensed)
            .accessibilityHidden(!(condensed || model.segment != .expenses))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.segment == .expenses { filterMenu }
            Button("Add Expense", systemImage: "plus") {
                showsAddExpense = true
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button("Activity", systemImage: "list.bullet.rectangle") {
                showsActivity = true
            }
            Button("Recap", systemImage: "play.rectangle") {
                showsRecap = true
            }
            .disabled(model.recapStats == nil)
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

/// The expense search field, shown only while the Expenses screen is open.
private struct ExpenseSearch: ViewModifier {
    let isOn: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isOn {
            content.searchable(text: $text, prompt: "Search expenses")
        } else {
            content
        }
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
