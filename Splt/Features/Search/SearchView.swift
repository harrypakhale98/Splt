import SpltCore
import SwiftUI

/// The Search tab: friends, groups and expenses, and questions in plain language.
struct SearchView: View {
    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            SearchContent(services: services)
        } else {
            NavigationStack {
                EmptyStateView.dataUnavailable
                    .navigationTitle("Search")
            }
        }
    }
}

private struct SearchContent: View {
    @Environment(Router.self) private var router
    @State private var model: SearchModel

    init(services: DataServices) {
        _model = State(initialValue: SearchModel(services: services))
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var router = router

        NavigationStack(path: $router.searchPath) {
            List {
                // the intro floats over an empty list: content in the list would hide the search field
                if model.trimmedQuery.isEmpty {
                    recentSection
                } else {
                    results
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Ink.hairline)
            .paperBackground()
            .overlay { placeholder }
            .navigationTitle("Search")
            .toolbar { AccountToolbarItem() }
            .searchable(text: $model.query, prompt: "Friends, groups, expenses")
            .onSubmit(of: .search) { model.remember() }
            .onChange(of: router.searchPath) { old, new in
                // opening a result keeps the query as a recent search
                if old.isEmpty, !new.isEmpty, !model.trimmedQuery.isEmpty { model.remember() }
            }
            .task(id: model.query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.search()
            }
            .routeDestinations()
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if !model.people.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.people) { person in
                        NavigationLink(value: Route.friend(person.id.rawValue)) {
                            HStack(spacing: 12) {
                                AvatarView(person: person, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name)
                                    if person.isPlaceholder {
                                        Text("Not on Splt yet")
                                            .font(.footnote)
                                            .foregroundStyle(Ink.secondary)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } header: {
                SectionHeader("People")
            }
        }
        if !model.groups.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.groups) { group in
                        NavigationLink(value: Route.group(group.id.rawValue)) {
                            HStack(spacing: 12) {
                                GroupGlyph(symbol: group.symbol, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(group.name)
                                    Text("^[\(group.memberIDs.count) person](inflect: true)")
                                        .font(.footnote)
                                        .foregroundStyle(Ink.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } header: {
                SectionHeader("Groups")
            }
        }
        if !model.expenses.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.expenses) { expense in
                        NavigationLink(value: Route.expense(expense.id.rawValue)) {
                            ExpenseRowView(expense: expense, currentPerson: model.me?.id, people: model.knownPeople)
                        }
                    }
                }
            } header: {
                SectionHeader("Expenses")
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recents.isEmpty {
            Section {
                RaisedRows {
                    ForEach(model.recents, id: \.self) { recent in
                        Button {
                            model.query = recent
                        } label: {
                            Text(recent)
                                .foregroundStyle(Ink.text)
                        }
                    }
                }
            } header: {
                HStack {
                    SectionHeader("Recent")
                    Spacer()
                    Button("Clear") { model.clearRecents() }
                        .font(.footnote)
                        .foregroundStyle(Ink.text)
                        .textCase(nil)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.trimmedQuery.isEmpty, model.recents.isEmpty {
            intro
        } else if !model.trimmedQuery.isEmpty, model.hasSearched, model.isEmpty {
            EmptyStateView.search(query: model.trimmedQuery)
        }
    }

    /// The first thing you see: questions to try.
    @ViewBuilder
    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Try asking")
                    .padding(.horizontal, Depth.rowPadding.leading)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SearchModel.examples.enumerated()), id: \.element) { index, example in
                        if index > 0 { Divider().overlay(Ink.hairline) }
                        Button { model.query = example } label: {
                            Text(example)
                                .font(.body)
                                .foregroundStyle(Ink.text)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Depth.rowPadding.leading)
                .cardSurface()
            }
            .padding(.horizontal, Depth.pageMargin)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#if DEBUG
#Preview {
    SearchView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}
#endif
