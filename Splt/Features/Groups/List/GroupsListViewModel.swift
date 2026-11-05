import Foundation
import Observation
import SpltCore

/// Shapes the groups store for the Groups tab: search, sections and the quick actions.
@MainActor
@Observable
final class GroupsListViewModel {
    var query = ""
    var errorMessage: String?

    /// Friends who owe you something, and friends you owe, for the hero at the top.
    private(set) var owedBy: [Person] = []
    private(set) var owedTo: [Person] = []

    @ObservationIgnored private let store: GroupsStore
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let leftGroups: LeftGroupsStore

    init(services: DataServices, leftGroups: LeftGroupsStore = LeftGroupsStore()) {
        store = services.groupsStore
        people = services.people
        groups = services.groups
        self.leftGroups = leftGroups
        refresh()
    }

    func refresh() {
        store.refresh()
        refreshPeople()
    }

    /// Looks people up once per refresh so rows do not query while they scroll.
    private func refreshPeople() {
        let everyone = (try? people.allPeople()) ?? []
        let byID = Dictionary(everyone.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let balances = (try? people.friendBalances()) ?? []
        owedBy = balances.filter { $0.total.contains(where: \.isPositive) }.compactMap { byID[$0.friendID] }
        owedTo = balances.filter { !$0.total.contains(where: \.isPositive) && !$0.total.isEmpty }.compactMap { byID[$0.friendID] }
    }

    /// Groups people made and you have not left. The hidden two person groups behind friends are not among them.
    private var listed: [GroupSummary] {
        store.summaries.filter { $0.group.kind != .friend && !leftGroups.contains($0.group.id) }
    }

    var hasGroups: Bool { !listed.isEmpty }
    var isSearching: Bool { !trimmedQuery.isEmpty }
    var active: [GroupSummary] { matching(listed.filter { !$0.group.isArchived }) }
    var archived: [GroupSummary] { matching(listed.filter(\.group.isArchived)) }
    var hasResults: Bool { !active.isEmpty || !archived.isEmpty }

    /// What you owe and are owed across the groups that are not archived, whatever the search says.
    var totals: BalanceTotals {
        BalanceTotals(amounts: listed.filter { !$0.group.isArchived }.flatMap(\.myBalance))
    }

    func archive(_ id: GroupID) {
        perform { try groups.setArchived(true, id: id) }
    }

    func restore(_ id: GroupID) {
        perform { try groups.setArchived(false, id: id) }
    }

    func delete(_ id: GroupID) {
        perform { try groups.delete(id: id) }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matching(_ summaries: [GroupSummary]) -> [GroupSummary] {
        guard isSearching else { return summaries }
        return summaries.filter { $0.group.name.localizedStandardContains(trimmedQuery) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
        refresh()
    }
}
