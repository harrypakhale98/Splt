import CloudKit
import Foundation
import Observation
import SpltCore

/// Asks iCloud whether the account can be used. Only call it once the entitlement is known to be present.
protocol AccountProbe: Sendable {
    func availability(containerIdentifier: String) async -> AccountAvailability
}

/// The engine the app holds. It picks the CloudKit engine when the build is signed for iCloud and
/// someone is signed in, otherwise the no-op engine, and switches when the account changes.
@MainActor
@Observable
final class AutomaticSyncEngine: SyncEngine {
    private(set) var status: SyncStatus
    private(set) var choice: SyncEngineChoice?

    @ObservationIgnored private let environment: @Sendable () -> SyncEnvironment
    @ObservationIgnored private let probe: any AccountProbe
    @ObservationIgnored private let makeCloudKitEngine: @MainActor (String) -> any SyncEngine
    @ObservationIgnored private let accountChanges: @Sendable () -> AsyncStream<Void>
    @ObservationIgnored private let broadcaster: StatusBroadcaster
    @ObservationIgnored private var current: any SyncEngine = NoOpSyncEngine()
    @ObservationIgnored private var forwarding: Task<Void, Never>?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var rechecking: Task<Void, Never>?
    @ObservationIgnored private let recheckInterval: Duration
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let stateStore: any SyncStateStore
    @ObservationIgnored private var isEvaluating = false
    @ObservationIgnored private var evaluateAgain = false

    init(
        environment: @escaping @Sendable () -> SyncEnvironment = { .current },
        probe: any AccountProbe,
        accountChanges: @escaping @Sendable () -> AsyncStream<Void> = { AutomaticSyncEngine.systemAccountChanges() },
        recheckInterval: Duration = .seconds(30),
        stateStore: any SyncStateStore = FileSyncStateStore(),
        makeCloudKitEngine: @escaping @MainActor (String) -> any SyncEngine
    ) {
        self.environment = environment
        self.probe = probe
        self.accountChanges = accountChanges
        self.recheckInterval = recheckInterval
        self.stateStore = stateStore
        self.makeCloudKitEngine = makeCloudKitEngine
        self.status = .unavailable(.starting)
        self.broadcaster = StatusBroadcaster(initial: .unavailable(.starting))
    }

    var statusUpdates: AsyncStream<SyncStatus> { broadcaster.updates() }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        await reevaluate()
        watching = Task { [weak self, accountChanges] in
            for await _ in accountChanges() {
                await self?.reevaluate()
            }
        }
    }

    func stop() async {
        isRunning = false
        watching?.cancel()
        watching = nil
        rechecking?.cancel()
        rechecking = nil
        forwarding?.cancel()
        forwarding = nil
        await current.stop()
        choice = nil
    }

    func sendChanges() async throws {
        try await current.sendChanges()
    }

    func fetchChanges() async throws {
        try await current.fetchChanges()
    }

    func share(group: GroupID, anyoneWithLink: Bool) async throws -> GroupShare {
        try await current.share(group: group, anyoneWithLink: anyoneWithLink)
    }

    func accept(_ invitation: ShareInvitation) async throws {
        switch choice {
        case nil, .noOp(.accountUnavailable)?:
            // the account is still being checked, so the answer can be different in a moment
            throw SyncError.notReady
        case .noOp(.noAccount)?:
            throw SyncError.noAccount
        case .noOp(.restricted)?:
            throw SyncError.restricted
        case .cloudKit?, .noOp?:
            try await current.accept(invitation)
        }
    }

    func leave(group: GroupID) async throws {
        if case .noOp(let reason)? = choice, reason.isAboutTheAccount {
            // iCloud is only out of reach for now: the CloudKit engine finishes this when it starts
            var metadata = stateStore.loadMetadata()
            metadata.pendingLeaves = (metadata.pendingLeaves ?? []).union([group.description])
            stateStore.saveMetadata(metadata)
            return
        }
        try await current.leave(group: group)
    }

    func isSharedByMe(group: GroupID) async -> Bool {
        if case .noOp(let reason)? = choice, reason.isAboutTheAccount {
            return stateStore.loadMetadata().ownedShares?.contains(group.description) == true
        }
        return await current.isSharedByMe(group: group)
    }

    /// Looks at the environment and account again and swaps the engine if the answer changed.
    /// One look at a time: a change that arrives during a swap is looked at right after it.
    func reevaluate() async {
        guard !isEvaluating else {
            evaluateAgain = true
            return
        }
        isEvaluating = true
        defer { isEvaluating = false }
        repeat {
            evaluateAgain = false
            await evaluate()
        } while evaluateAgain && isRunning
    }

    private func evaluate() async {
        let snapshot = environment()
        let account: AccountAvailability
        if let container = snapshot.entitlements.cloudKitContainers.first, SyncEngineSelector.preflight(snapshot) == nil {
            account = await probe.availability(containerIdentifier: container)
        } else {
            account = .unknown
        }
        guard isRunning else { return }
        let next = SyncEngineSelector.decide(snapshot, account: account)
        guard next != choice else {
            scheduleRecheckIfNeeded()
            return
        }
        await switchEngine(to: next)
    }

    private func switchEngine(to next: SyncEngineChoice) async {
        forwarding?.cancel()
        await current.stop()
        choice = next
        switch next {
        case .cloudKit(let identifier):
            current = makeCloudKitEngine(identifier)
        case .noOp(let reason):
            current = NoOpSyncEngine(reason: reason)
        }
        publish(current.status)
        let updates = current.statusUpdates
        forwarding = Task { [weak self] in
            for await value in updates {
                self?.publish(value)
            }
        }
        await current.start()
        scheduleRecheckIfNeeded()
    }

    /// iCloud can be briefly unreachable at launch and send no notification when it comes back, so ask again.
    private func scheduleRecheckIfNeeded() {
        rechecking?.cancel()
        rechecking = nil
        guard case .noOp(.accountUnavailable)? = choice else { return }
        rechecking = Task { [weak self, recheckInterval] in
            try? await Task.sleep(for: recheckInterval)
            guard !Task.isCancelled else { return }
            await self?.reevaluate()
        }
    }

    private func publish(_ value: SyncStatus) {
        status = value
        broadcaster.send(value)
    }

    nonisolated static func systemAccountChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let tokens = ObserverTokens()
            for name in [Notification.Name.NSUbiquityIdentityDidChange, .CKAccountChanged] {
                tokens.add(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                    continuation.yield()
                })
            }
            continuation.onTermination = { _ in tokens.removeAll() }
        }
    }
}

/// Holds notification observers so a stream can remove them when it ends.
private final class ObserverTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [any NSObjectProtocol] = []

    func add(_ token: any NSObjectProtocol) {
        lock.withLock { tokens.append(token) }
    }

    func removeAll() {
        let taken = lock.withLock { () -> [any NSObjectProtocol] in
            defer { tokens = [] }
            return tokens
        }
        taken.forEach(NotificationCenter.default.removeObserver)
    }
}
