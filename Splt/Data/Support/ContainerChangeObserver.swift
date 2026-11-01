import Foundation
import SwiftData

/// Calls a handler on the main actor after anything saves to the container, from any context.
/// Stores use it to refresh when sync or another part of the app changes the data.
@MainActor
final class ContainerChangeObserver {
    nonisolated(unsafe) private var token: (any NSObjectProtocol)?

    init(container: ModelContainer, handler: @escaping @MainActor () -> Void) {
        let identity = ObjectIdentifier(container)
        token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { note in
            let context = note.object as? ModelContext
            guard context.map({ ObjectIdentifier($0.container) == identity }) ?? true else { return }
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
