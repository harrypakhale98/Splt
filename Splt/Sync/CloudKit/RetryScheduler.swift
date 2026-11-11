import Foundation

/// Tries again after a failure, waiting longer each time, so a full iCloud or a bad network
/// never turns into a busy loop. Nothing is lost while waiting: the changes stay marked dirty.
@MainActor
final class RetryScheduler {
    private let policy: BackoffPolicy
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let action: @MainActor () async -> Void
    private var attempts = 0
    private var task: Task<Void, Never>?

    init(
        policy: BackoffPolicy = BackoffPolicy(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        },
        action: @escaping @MainActor () async -> Void
    ) {
        self.policy = policy
        self.sleep = sleep
        self.action = action
    }

    var isScheduled: Bool { task != nil }
    var failureCount: Int { attempts }

    /// Plans another attempt unless one is already waiting or the failure cannot be fixed by waiting.
    func failed(_ failure: SyncFailure) {
        guard failure.isRetryable, task == nil else { return }
        let delay = policy.delay(afterFailures: attempts, for: failure)
        attempts += 1
        // Detached: failures are reported from inside CKSyncEngine's delegate callbacks, and a plain
        // Task would carry that context into the send and fetch the retry starts, which CKSyncEngine traps on.
        task = Task.detached { [weak self, sleep] in
            await sleep(delay)
            await self?.fire()
        }
    }

    private func fire() async {
        guard !Task.isCancelled else { return }
        task = nil
        await action()
    }

    func succeeded() {
        attempts = 0
        task?.cancel()
        task = nil
    }

    func cancel() {
        succeeded()
    }
}
