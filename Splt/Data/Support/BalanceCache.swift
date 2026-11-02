import Foundation
import SpltCore
import Synchronization

/// Remembers each group's ledger so a save only recomputes the group it touched.
///
/// Every write that can change a group's balances calls `invalidate` for that group; the change
/// tracker does this for local edits, soft deletes, undo and remote changes, so nothing else
/// needs to remember. A ledger computed while a write lands is not stored, so a slow reader
/// can never put a stale answer back.
final class BalanceCache: Sendable {
    private struct State {
        var ledgers: [GroupID: Ledger] = [:]
        var generations: [GroupID: Int] = [:]
        var epoch = 0
    }

    private let state = Mutex(State())

    private enum Lookup {
        case hit(Ledger)
        case miss(generation: Int, epoch: Int)
    }

    /// The cached ledger, or the result of `compute`, which is then cached.
    func ledger(for group: GroupID, compute: () throws -> Ledger) rethrows -> Ledger {
        let lookup = state.withLock { state -> Lookup in
            if let ledger = state.ledgers[group] { return .hit(ledger) }
            return .miss(generation: state.generations[group, default: 0], epoch: state.epoch)
        }
        guard case .miss(let generation, let epoch) = lookup else {
            if case .hit(let ledger) = lookup { return ledger }
            return try compute()
        }
        let ledger = try compute()
        state.withLock { state in
            if state.generations[group, default: 0] == generation, state.epoch == epoch {
                state.ledgers[group] = ledger
            }
        }
        return ledger
    }

    func invalidate(_ group: GroupID) {
        state.withLock { state in
            state.ledgers[group] = nil
            state.generations[group, default: 0] += 1
        }
    }

    func invalidateAll() {
        state.withLock { state in
            state.ledgers = [:]
            state.epoch += 1
        }
    }

    var cachedGroupCount: Int {
        state.withLock { $0.ledgers.count }
    }
}
