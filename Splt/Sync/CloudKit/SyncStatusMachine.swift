import Foundation

/// Works out the one status to show from what is running and what last went wrong.
struct SyncStatusMachine: Equatable, Sendable {
    /// Where a problem was seen. A later success from the same source clears it.
    struct Source: Hashable, Sendable {
        var scope: DatabaseScope
        var isSending: Bool
    }

    private var running = 0
    private var problems: [Source: SyncStatus] = [:]
    var isOnline = true

    mutating func began() {
        running += 1
    }

    mutating func ended() {
        running = max(0, running - 1)
    }

    mutating func failed(_ failure: SyncFailure, source: Source) {
        guard let status = failure.status else { return }
        problems[source] = status
    }

    mutating func succeeded(source: Source) {
        problems[source] = nil
    }

    mutating func clearProblems() {
        problems = [:]
    }

    var status: SyncStatus {
        let priority: [SyncStatus] = [.noAccount, .restricted]
        for wanted in priority where problems.values.contains(wanted) {
            return wanted
        }
        if let message = problems.values.first(where: { if case .error = $0 { true } else { false } }) {
            return message
        }
        if !isOnline || problems.values.contains(.offline) { return .offline }
        return running > 0 ? .syncing : .idle
    }
}
