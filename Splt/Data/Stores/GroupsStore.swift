import Foundation
import Observation
import SpltCore
import SwiftData

/// Groups with your balance in each, for the Groups tab.
@MainActor
@Observable
final class GroupsStore {
    private(set) var summaries: [GroupSummary] = []
    private(set) var totals = BalanceTotals.zero
    private(set) var didFailToLoad = false

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let activity: any ActivityRepository
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var refreshScheduled = false

    init(
        groups: any GroupRepository,
        people: any PersonRepository,
        activity: any ActivityRepository,
        container: ModelContainer? = nil
    ) {
        self.groups = groups
        self.people = people
        self.activity = activity
        if let container {
            observer = ContainerChangeObserver(container: container) { [weak self] in self?.scheduleRefresh() }
        }
        refresh()
    }


    func refresh() {
        do {
            let me = try people.me()?.id
            summaries = try groups.groups(includeArchived: true).map { group in
                let mine = try me.map { try groups.balances(for: group.id).net(for: $0) } ?? []
                return GroupSummary(
                    group: group,
                    memberCount: group.memberIDs.count,
                    myBalance: mine,
                    lastActivity: try activity.entries(in: group.id, limit: 1).first?.createdAt
                )
            }
            totals = BalanceTotals(amounts: summaries.flatMap(\.myBalance))
            didFailToLoad = false
        } catch {
            didFailToLoad = true
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }
}
