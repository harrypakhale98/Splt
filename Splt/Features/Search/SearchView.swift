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
                UnderstoodChips(items: model.understood)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Showing")
            }
        }
        if !model.people.isEmpty {
            Section("People") {
                ForEach(model.people) { person in
                    NavigationLink(value: Route.friend(person.id.rawValue)) {
                        HStack(spacing: 12) {
                            AvatarView(person: person, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name)
                                if person.isPlaceholder {
                                    Text("Not on Splt yet")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .simultaneousGesture(TapGesture().onEnded { model.remember() })
                }
            }
        }
        if !model.groups.isEmpty {
            Section("Groups") {
                ForEach(model.groups) { group in
                    NavigationLink(value: Route.group(group.id.rawValue)) {
                        HStack(spacing: 12) {
                            GroupGlyph(symbol: group.symbol, members: group.memberIDs, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.name)
                                Text("\(group.memberIDs.count) people")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
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
            intro
        } else if !model.trimmedQuery.isEmpty, model.hasSearched, model.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing matches \u{201C}\(model.trimmedQuery)\u{201D}. Check the spelling, or ask a question such as \u{201C}\(SearchModel.examples[1])\u{201D}.")
            }
        }
    }

    /// The first thing you see: the orbit, what search can do, and questions to try.
    private var intro: some View {
        ScrollView {
            VStack(spacing: 20) {
                OrbitMotif(size: 160) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                VStack(spacing: 8) {
                    Text("Search Splt")
                        .font(.title2.bold())
                    Text("Find friends, groups and expenses, or ask in your own words.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                GlassEffectContainer(spacing: 8) {
                    FlowLayout(spacing: 8) {
                        ForEach(SearchModel.examples, id: \.self) { example in
                            Button { model.query = example } label: {
                                GlassPill(isInteractive: true) {
                                    Text(example)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contentShape(.capsule)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(example)
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// How a question was read, as small capsules that wrap onto more lines when needed.
private struct UnderstoodChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: .capsule)
            }
        }
        .accessibilityElement(children: .ignore)
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
