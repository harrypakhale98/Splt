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

    /// What the index shows. Used as the task id so the index updates only when it would change.
    private struct Entry: Hashable {
        var id: GroupID
        var name: String
        var symbol: String
        var members: [PersonID]
        var isIndexed: Bool
    }

    private var entries: [Entry] {
        (services?.groupsStore.summaries ?? []).map {
            Entry(
                id: $0.group.id, name: $0.group.name, symbol: $0.group.symbol,
                members: $0.group.memberIDs, isIndexed: GroupSpotlight.isIndexed($0.group)
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
            .task(id: entries) {
                guard let services else { return }
                let groups = services.groupsStore.summaries.map(\.group)
                let people = Dictionary(
                    ((try? services.people.allPeople()) ?? []).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                await GroupIndexer().update(groups: groups, people: people)
            }
    }
}
