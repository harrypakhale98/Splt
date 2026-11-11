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
            EmptyStateView.dataUnavailable
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
    @State private var condensed = false
    @State private var showsRecap = false

    init(groupID: GroupID, services: DataServices) {
        _model = State(initialValue: GroupDetailViewModel(groupID: groupID, services: services))
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if let group = model.group {
                ScrollViewReader { proxy in
                List {
                    if model.segment == .expenses {
                        GroupHeroSection(
                            group: group,
                            members: model.members,
                            totals: model.myTotals,
                            canSettle: !model.transfers.isEmpty,
                            paid: model.primaryTotals?.byPerson ?? [],
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
                // only crossing the line writes state, so scrolling doesn't redraw the screen every frame
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 187
                } action: { _, isPast in
                    condensed = isPast
                }
                .modifier(ExpenseSearch(isOn: model.segment == .expenses, text: $model.filter.query))
                .toolbar { toolbar }
                // a bar on Totals opened its expenses: bring the filtered list into view from its top
                .onChange(of: model.drillRevision) {
                    Motion.perform(Motion.smooth) { proxy.scrollTo(Self.listTop, anchor: .top) }
                }
                }
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
            } else {
                RecapUnavailable()
            }
        }
        .sheet(isPresented: $showsAddExpense) {
            ExpenseFormView(mode: .add(groupID: model.groupID, prefill: nil))
        }
        .sheet(isPresented: $showsSettings) {
            GroupSettingsView(groupID: model.groupID, onGroupRemoved: { dismiss() })
        }
        .sheet(isPresented: $showsCustomRange) {
            DateRangeSheet(start: model.filter.customStart, end: model.filter.customEnd) { start, end in
                model.filter.customStart = start
                model.filter.customEnd = end
                model.filter.period = .custom
            }
        }
        .sheet(item: $settleRoute) { route in
            SettleUpSheet(route: route)
        }
        .closingSheetsOnLink {
            showsRecap = false
            showsAddExpense = false
            showsSettings = false
            showsCustomRange = false
            settleRoute = nil
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
            Group {
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
            .id(Self.listTop)
        }
    }

    private static let listTop = "group-list-top"

    @ViewBuilder
    private var content: some View {
        switch model.segment {
        case .expenses:
            expensesContent
        case .balances:
            GroupBalancesSection(model: model, onSettle: { settleRoute = model.settleRoute(for: $0) })
        case .totals:
            GroupSpendingSection(model: model, onRecap: { showsRecap = true })
        }
    }

    @ViewBuilder
    private var expensesContent: some View {
        let sections = model.sections
        if model.filter.isFiltering {
            Section {
                // says what the list is narrowed to, so a tap on a chart never leaves you guessing
                HStack(spacing: 12) {
                    Text(model.filterDescription(locale: locale) ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: 8)
                    Button("Clear") {
                        Motion.perform(Motion.smooth) { model.filter.clearFilters() }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear Filters")
                }
                // the Clear button is already 44pt tall, so the row adds no padding of its own
                .raisedRow(padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            }
            .raisedSection()
        }
        if model.expenses.isEmpty {
            Section {
                GroupPaperNote("Add the first expense to start splitting.")
            }
        } else if sections.isEmpty {
            Section {
                let query = model.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    GroupPaperNote("No expenses match these filters.")
                } else {
                    EmptyStateView.search(query: query)
                        .listRowBackground(Color.clear)
                }
            }
        } else {
            ForEach(sections) { section in
                Section {
                    RaisedRows {
                        ForEach(section.expenses) { expense in
                            NavigationLink(value: Route.expense(expense.id.rawValue)) {
                                GroupExpenseRow(
                                    expense: expense, summary: model.rowSummary(for: expense),
                                    memberIDs: model.group?.memberIDs ?? []
                                )
                            }
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
                    .sectionHeaderStyle()
                    .padding(.horizontal, Depth.pageMargin + 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                .raisedSection()
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
            Picker("Date", selection: presetPeriod) {
                ForEach(ExpenseFilter.Period.allCases.filter { $0 != .custom }) { Text($0.title).tag(Optional($0)) }
            }
            // a button rather than a picker choice, so the range can be opened again and Cancel changes nothing
            Button {
                showsCustomRange = true
            } label: {
                if model.filter.period == .custom {
                    Label("Custom Range…", systemImage: "checkmark")
                } else {
                    Text("Custom Range…")
                }
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

    /// The preset periods. Nil while a custom range is applied, so no preset shows as chosen.
    private var presetPeriod: Binding<ExpenseFilter.Period?> {
        Binding(
            get: { model.filter.period == .custom ? nil : model.filter.period },
            set: { if let period = $0 { model.filter.period = period } }
        )
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

/// Two dates for the custom filter period. Nothing changes until Apply.
private struct DateRangeSheet: View {
    let onApply: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftStart: Date
    @State private var draftEnd: Date

    init(start: Date, end: Date, onApply: @escaping (Date, Date) -> Void) {
        self.onApply = onApply
        _draftStart = State(initialValue: start)
        _draftEnd = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RaisedRows {
                        DatePicker("From", selection: $draftStart, displayedComponents: .date)
                        DatePicker("To", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
                    }
                }
                .raisedSection()
            }
            .paperBackground()
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draftStart, max(draftEnd, draftStart))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// One plain sentence on paper, for a list with nothing in it yet.
struct GroupPaperNote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Shown if the recap opens without anything to tell, so the cover can always be closed.
private struct RecapUnavailable: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                title: "No Recap Yet",
                systemImage: "play.rectangle",
                description: "The recap appears once the group has expenses."
            )
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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
