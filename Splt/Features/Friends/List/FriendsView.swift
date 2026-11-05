import SpltCore
import SwiftUI

/// The Friends tab: everyone you split with and what is owed between you.
struct FriendsView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @Namespace private var zoomNamespace

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.friendsPath) {
            Group {
                if let services {
                    FriendsContent(services: services)
                } else {
                    EmptyStateView(
                        title: "No Friends Yet",
                        systemImage: "person.2",
                        description: "Splt couldn't open its storage."
                    )
                }
            }
            .navigationTitle("Friends")
            .environment(\.zoomNamespace, zoomNamespace)
            .routeDestinations()
        }
    }
}

private struct FriendsContent: View {
    @Environment(Router.self) private var router
    @Environment(\.locale) private var locale

    @State private var model: FriendsViewModel
    @State private var settleRequest: SettleRequest?
    @State private var remindTarget: RemindTarget?

    init(services: DataServices) {
        _model = State(initialValue: FriendsViewModel(services: services))
    }

    var body: some View {
        @Bindable var model = model
        let sections = model.sections

        List {
            if !model.hasNoFriends, model.query.isEmpty {
                Section {
                    NetPositionHero(
                        scope: "With Friends",
                        totals: model.totals,
                        owedBy: model.summaries.filter { $0.balance.contains(where: \.isPositive) }.map(\.person),
                        owedTo: model.summaries.filter { !$0.balance.isEmpty && !$0.balance.contains(where: \.isPositive) }.map(\.person)
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            section("Owes you", sections.owesYou)
            section("You owe", sections.youOwe)
            section("Both ways", sections.mixed)
            section("Settled up", sections.settled)
            if model.query.isEmpty, !model.hiddenSummaries.isEmpty {
                Section {
                    NavigationLink {
                        HiddenFriendsView(model: model)
                    } label: {
                        LabeledContent("Hidden and Blocked", value: model.hiddenSummaries.count, format: .number)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .searchable(text: $model.query, prompt: "Search friends")
        .overlay { emptyState(sections) }
        .toolbar {
            AccountToolbarItem()
            ToolbarItem(placement: .primaryAction) {
                Button("Add Friend", systemImage: "person.badge.plus") {
                    router.present(.newFriend)
                }
            }
        }
        .task(id: model.summaries) { await model.cancelRemindersForFriendsWhoOweNothing() }
        .settleFlow($settleRequest)
        .sheet(item: $remindTarget) { target in
            RemindSheet(friend: target.person, owed: target.owed, groupNames: target.groupNames)
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ summaries: [FriendSummary]) -> some View {
        if !summaries.isEmpty {
            Section {
                ForEach(summaries) { summary in
                    NavigationLink(value: Route.friend(summary.id.rawValue)) {
                        FriendRow(summary: summary)
                    }
                    .listRowBackground(Color.clear)
                    .zoomSource(for: .friend(summary.id.rawValue))
                    .swipeActions(edge: .leading) {
                        if !summary.isSettled {
                            Button("Settle", systemImage: "checkmark.circle") {
                                settleRequest = model.settleRequest(for: summary)
                            }
                            .tint(Ink.owed)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Hide", systemImage: "eye.slash") {
                            model.setState(.hidden, for: summary.id)
                        }
                        .tint(Ink.secondary)
                        if summary.balance.contains(where: \.isPositive) {
                            Button("Remind", systemImage: "bell") {
                                remindTarget = RemindTarget(summary: summary, model: model)
                            }
                            .tint(Ink.text)
                        }
                    }
                    .contextMenu { menu(for: summary) }
                }
            } header: {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func menu(for summary: FriendSummary) -> some View {
        if !summary.isSettled {
            Button("Settle Up", systemImage: "checkmark.circle") {
                settleRequest = model.settleRequest(for: summary)
            }
        }
        if summary.balance.contains(where: \.isPositive) {
            Button("Remind", systemImage: "bell") {
                remindTarget = RemindTarget(summary: summary, model: model)
            }
        }
        Button("Hide", systemImage: "eye.slash") { model.setState(.hidden, for: summary.id) }
        Button("Block", systemImage: "nosign", role: .destructive) { model.setState(.blocked, for: summary.id) }
    }

    @ViewBuilder
    private func emptyState(_ sections: FriendSections) -> some View {
        if model.hasNoFriends {
            EmptyStateView(
                title: "No Friends Yet",
                systemImage: "person.2",
                description: "Add friends to split bills and see who owes what.",
                actionTitle: "Add Friend",
                action: { router.present(.newFriend) }
            )
        } else if sections.isEmpty, !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if sections.isEmpty {
            EmptyStateView(
                title: "Everyone Is Hidden",
                systemImage: "eye.slash",
                description: "Your friends are hidden or blocked. Bring them back from the list below."
            )
        }
    }
}

/// What the remind sheet needs about one friend.
private struct RemindTarget: Identifiable {
    let person: Person
    let owed: [Money]
    let groupNames: [String]

    var id: PersonID { person.id }

    @MainActor
    init(summary: FriendSummary, model: FriendsViewModel) {
        person = summary.person
        owed = summary.balance.filter(\.isPositive)
        groupNames = model.settleRequest(for: summary)?.legs
            .filter { !$0.youOwe }.map(\.groupName).uniqued() ?? []
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#if DEBUG
#Preview("Friends") {
    FriendsView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}

#Preview("Empty") {
    FriendsView()
        .environment(Router())
        .environment(\.dataServices, try? DataServices.inMemory())
}

#Preview("Large text") {
    FriendsView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
        .dynamicTypeSize(.accessibility3)
}
#endif
