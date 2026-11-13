import CoreSpotlight
import SpltCore
import SwiftUI

extension View {
    /// Keeps groups in Spotlight and opens one when its result is tapped.
    func groupSpotlight(services: DataServices?, router: Router) -> some View {
        modifier(GroupSpotlightModifier(services: services, router: router))
    }
}

private struct GroupSpotlightModifier: ViewModifier {
    let services: DataServices?
    let router: Router
    // with the lock on, group names and members stay out of Spotlight, where a locked phone could show them
    @AppStorage(Preferences.Key.biometricLockEnabled) private var lockOn = false

    /// What the index shows. Used as the task id so the index updates only when it would change.
    private struct Entry: Hashable {
        var id: GroupID
        var name: String
        var symbol: String
        var cover: String?
        var members: [PersonID]
        /// The members' names are search keywords, so renaming someone must re-index.
        var memberNames: [String]
        var isIndexed: Bool
    }

    private struct IndexState: Hashable {
        var entries: [Entry]
        var lockOn: Bool
    }

    private var entries: [Entry] {
        let summaries = services?.groupsStore.summaries ?? []
        guard let services, !summaries.isEmpty else { return [] }
        let names = Dictionary(
            ((try? services.people.allPeople()) ?? []).map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let left = LeftGroupsStore()
        return summaries.map {
            Entry(
                id: $0.group.id, name: $0.group.name, symbol: $0.group.symbol, cover: $0.group.shownCoverFileName,
                members: $0.group.memberIDs, memberNames: $0.group.memberIDs.map { names[$0] ?? "" },
                isIndexed: GroupSpotlight.isIndexed($0.group, left: left)
            )
        }
    }

    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = GroupSpotlight.groupID(from: activity) {
                    router.open(.group(id.rawValue))
                }
            }
            .task(id: IndexState(entries: entries, lockOn: lockOn)) {
                guard let services else { return }
                if lockOn {
                    await GroupIndexer().update(groups: [], people: [:])
                    return
                }
                let left = LeftGroupsStore()
                let groups = services.groupsStore.summaries.map(\.group).filter { !left.contains($0.id) }
                let people = Dictionary(
                    ((try? services.people.allPeople()) ?? []).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                await GroupIndexer().update(groups: groups, people: people)
            }
    }
}
