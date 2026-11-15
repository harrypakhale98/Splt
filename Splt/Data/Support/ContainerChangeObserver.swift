import Foundation
import SwiftData

/// Calls a handler on the main actor after anything saves to the container, from any context.
/// Stores use it to refresh when sync or another part of the app changes the data.
///
/// Pass `watching` to hear only about saves that insert, change or delete those kinds of record, so a screen
/// that shows expenses does not rebuild because an activity row was marked read. When a save does not say
/// what it touched, the handler is called anyway.
@MainActor
final class ContainerChangeObserver {
    nonisolated(unsafe) private var token: (any NSObjectProtocol)?

    init(
        container: ModelContainer, watching types: [any PersistentModel.Type]? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
        let identity = ObjectIdentifier(container)
        let names = types.map { Set($0.map { Schema.entityName(for: $0) }) }
        token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { note in
            let context = note.object as? ModelContext
            guard context.map({ ObjectIdentifier($0.container) == identity }) ?? true else { return }
            if let names, !Self.touches(note.userInfo, names) { return }
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// True when the save touched one of the named entities, or does not say what it touched.
    nonisolated static func touches(_ userInfo: [AnyHashable: Any]?, _ names: Set<String>) -> Bool {
        guard let userInfo else { return true }
        if userInfo[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] != nil { return true }
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        var said = false
        for key in keys {
            guard let ids = userInfo[key.rawValue] as? [PersistentIdentifier] else { continue }
            said = true
            if ids.contains(where: { names.contains($0.entityName) }) { return true }
        }
        return !said
    }
}

/// The records behind balances: who paid what, who settled, who is in which group.
enum WatchedRecords {
    static let balances: [any PersistentModel.Type] = [ExpenseRecord.self, PaymentRecord.self, PersonRecord.self, GroupRecord.self]
}
