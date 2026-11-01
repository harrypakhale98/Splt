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
                EmptyStateView(
                    title: "Search Splt",
                    systemImage: "magnifyingglass",
                    description: "Splt couldn't open its storage."
                )
                .navigationTitle("Search")
            }
        }
    }
}

private struct SearchContent: View {
    @State private var model: SearchModel
    @State private var path: [Route] = []

    init(services: DataServices) {
        _model = State(initialValue: SearchModel(services: services))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack(path: $path) {
            List {
                if model.trimmedQuery.isEmpty {
                    recentSection
                } else {
                    results
                }
            }
            .overlay { placeholder }
            .navigationTitle("Search")
            .searchable(text: $model.query, prompt: "Friends, groups, expenses")
            .onSubmit(of: .search) { model.remember() }
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
        if !model.understood.isEmpty {
            Section {
                UnderstoodText(items: model.understood)
            } header: {
                Text("Showing")
            }
        }
        if !model.people.isEmpty {
            Section("People") {
                ForEach(model.people) { person in
                    NavigationLink(value: Route.friend(person.id.rawValue)) {
                        Label {
                            Text(person.name)
                        } icon: {
                            AvatarView(name: person.name, size: 32)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.remember() })
                }
            }
        }
        if !model.groups.isEmpty {
            Section("Groups") {
                ForEach(model.groups) { group in
                    NavigationLink(value: Route.group(group.id.rawValue)) {
                        Label {
                            Text(group.name)
                        } icon: {
                            Image(systemName: group.symbol)
                                .foregroundStyle(GroupAppearance.color(for: group.id))
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.remember() })
                }
            }
        }
        if !model.expenses.isEmpty {
            Section("Expenses") {
                ForEach(model.expenses) { expense in
                    NavigationLink(value: Route.expense(expense.id.rawValue)) {
                        ExpenseRowView(expense: expense, currentPerson: model.me?.id, people: Array(model.peopleByID.values))
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.remember() })
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recents.isEmpty {
            Section {
                ForEach(model.recents, id: \.self) { recent in
                    Button {
                        model.query = recent
                    } label: {
                        Label(recent, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { model.clearRecents() }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.trimmedQuery.isEmpty, model.recents.isEmpty {
            EmptyStateView(
                title: "Search Splt",
                systemImage: "magnifyingglass",
                description: "Find friends, groups and expenses. Try \"dinners Sam paid in March\"."
            )
        } else if !model.trimmedQuery.isEmpty, model.hasSearched, model.isEmpty {
            ContentUnavailableView.search(text: model.query)
        }
    }
}

/// How a question was read, as one line.
private struct UnderstoodText: View {
    let items: [String]

    var body: some View {
        Text(items.joined(separator: "  \u{00B7}  "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel(items.joined(separator: ", "))
    }
}

#if DEBUG
#Preview {
    SearchView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}
#endif
