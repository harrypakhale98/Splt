import CloudKit
import Foundation
import Observation
import SpltCore
import SwiftData

/// Free, serverless sync on CloudKit. Groups live in one record zone each, in your private database
/// or, once shared, in the owner's zone through a CKShare. Create it only in a build that has the
/// iCloud entitlement, because `CKContainer` traps without it; `AutomaticSyncEngine` takes care of that.
@MainActor
@Observable
final class CloudKitSyncEngine: SyncEngine {
    private(set) var status: SyncStatus = .idle

    @ObservationIgnored private let backend: any CloudKitBackend
    @ObservationIgnored private let connectivity: @Sendable () -> AsyncStream<Bool>
    @ObservationIgnored private let reconcileDelay: Duration
    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let store: any SyncStateStore
    @ObservationIgnored private let broadcaster = StatusBroadcaster(initial: .idle)
    @ObservationIgnored private let notifier: RemoteChangeNotifier?
    @ObservationIgnored private let adapter: SyncStoreAdapter
    @ObservationIgnored private let coordinator: SyncCoordinator
    @ObservationIgnored private(set) var syncers: [DatabaseSyncer] = []
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    convenience init(
        containerIdentifier: String, services: DataServices,
        store: any SyncStateStore = FileSyncStateStore(), notifier: RemoteChangeNotifier? = nil
    ) {
        self.init(
            backend: LiveCloudKitBackend(containerIdentifier: containerIdentifier), services: services,
            store: store, notifier: notifier
        )
    }

    init(
        backend: any CloudKitBackend, services: DataServices, store: any SyncStateStore,
        notifier: RemoteChangeNotifier? = nil,
        connectivity: @escaping @Sendable () -> AsyncStream<Bool> = { ConnectivityMonitor().updates() },
        reconcileDelay: Duration = .milliseconds(400),
        retryPolicy: BackoffPolicy = BackoffPolicy()
    ) {
        self.backend = backend
        self.services = services
        self.store = store
        self.notifier = notifier
        self.connectivity = connectivity
        self.reconcileDelay = reconcileDelay
        self.adapter = SyncStoreAdapter(tracker: services.makeChangeTracker(), store: store)
        self.coordinator = SyncCoordinator(services: services, adapter: adapter)
        coordinator.setRetry(RetryScheduler(policy: retryPolicy) { [weak self] in await self?.retryNow() })
        coordinator.onStatusChange = { [weak self] in self?.publish($0) }
        coordinator.onRemoteChanges = { [weak self] report in self?.notifier?.notify(for: report, services: self?.services) }
    }

    var statusUpdates: AsyncStream<SyncStatus> { broadcaster.updates() }

    // MARK: Lifecycle

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            try coordinator.begin(user: try await backend.userRecordName())
        } catch {
            isStarted = false
            publish(SyncFailure(error).status ?? .error(SyncFailure.genericMessage))
            coordinator.startFailed(error)
            return
        }
        publish(coordinator.status)

        let privateSyncer = DatabaseSyncer(scope: .privateDatabase, coordinator: coordinator, store: store)
        let sharedSyncer = DatabaseSyncer(scope: .sharedDatabase, coordinator: coordinator, store: store)
        syncers = [privateSyncer, sharedSyncer]
        coordinator.attach(privateSyncer, for: .privateDatabase)
        coordinator.attach(sharedSyncer, for: .sharedDatabase)
        let hadState = privateSyncer.hasSavedState
        for syncer in syncers {
            syncer.start(makeEngine: backend.engineFactory(for: syncer.scope))
        }

        observer = ContainerChangeObserver(container: services.container) { [weak self] in
            self?.scheduleReconcile()
        }
        tasks.append(Task { [weak self, connectivity] in await self?.watchConnectivity(connectivity()) })
        tasks.append(Task { [weak self] in await self?.firstSync(alreadySynced: hadState) })
        try? adapter.purgeOldTombstones()
    }

    func stop() async {
        isStarted = false
        coordinator.cancelRetry()
        tasks.forEach { $0.cancel() }
        tasks = []
        reconcileTask?.cancel()
        reconcileTask = nil
        observer = nil
        for syncer in syncers {
            await syncer.stop()
        }
        syncers = []
    }

    private func firstSync(alreadySynced: Bool) async {
        if alreadySynced { markReadyAndReconcile() }
        do {
            try await fetchChanges()
        } catch {
            // the retry scheduler picks this up; local changes stay queued on disk
        }
        markReadyAndReconcile()
    }

    private func markReadyAndReconcile() {
        coordinator.markReady()
        try? coordinator.reconcile()
    }

    private func watchConnectivity(_ updates: AsyncStream<Bool>) async {
        for await online in updates {
            coordinator.updateStatus { $0.isOnline = online }
            if online { scheduleReconcile() }
        }
    }

    private func publish(_ new: SyncStatus) {
        status = new
        broadcaster.send(new)
    }

    private func scheduleReconcile() {
        guard reconcileTask == nil else { return }
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: self?.reconcileDelay ?? .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.reconcileTask = nil
            try? self.coordinator.reconcile()
        }
    }

    private func retryNow() async {
        guard isStarted else {
            await start()
            return
        }
        try? coordinator.reconcile()
        try? await sendChanges()
        try? await fetchChanges()
    }

    // MARK: SyncEngine

    func sendChanges() async throws {
        try coordinator.reconcile()
        for syncer in syncers {
            try await syncer.sendChanges()
        }
    }

    func fetchChanges() async throws {
        for syncer in syncers {
            try await syncer.fetchChanges()
        }
    }

    func share(group: GroupID, anyoneWithLink: Bool) async throws -> GroupShare {
        guard let value = try services.groups.group(id: group) else { throw SyncError.groupNotFound }
        let zoneID = adapter.metadata.zoneID(forZoneName: group.description)
        let service = backend.shareService
        if zoneID.scope == .sharedDatabase {
            // the system sheet lets a participant remove themselves without leaving the member list,
            // so only the owner is given it. Everyone else leaves with Leave Group.
            guard anyoneWithLink else { throw SyncError.ownerInvites }
            guard let existing = try await service.share(zoneID: zoneID) else { throw SyncError.notShared }
            if anyoneWithLink, existing.publicPermission == .none { throw SyncError.linkNotOpen }
            return try backend.groupShare(existing, groupName: value.name)
        }
        guard let privateSyncer = syncers.first(where: { $0.scope == .privateDatabase }) else { throw SyncError.notReady }
        try coordinator.reconcile()
        try await privateSyncer.sendChanges()
        let share = try await service.prepare(zoneID: zoneID, title: value.name, anyoneWithLink: anyoneWithLink)
        coordinator.noteOwnShare(zoneName: zoneID.zoneName, exists: true)
        return try backend.groupShare(share, groupName: value.name)
    }

    func accept(_ invitation: ShareInvitation) async throws {
        guard let metadata = invitation.metadata else { throw SyncError.invalidInvitation }
        guard metadata.containerIdentifier == backend.containerIdentifier else { throw SyncError.invalidInvitation }
        guard isStarted else { throw SyncError.notReady }
        try await backend.accept(metadata)
        try await fetchChanges()
        try coordinator.joined(zoneName: metadata.share.recordID.zoneID.zoneName)
    }

    func isSharedByMe(group: GroupID) async -> Bool {
        let zoneID = adapter.metadata.zoneID(forZoneName: group.description)
        guard zoneID.scope == .privateDatabase else { return false }
        do {
            let shared = try await backend.shareService.share(zoneID: zoneID) != nil
            coordinator.noteOwnShare(zoneName: zoneID.zoneName, exists: shared)
            return shared
        } catch {
            return adapter.metadata.ownedShares?.contains(zoneID.zoneName) == true
        }
    }

    func leave(group: GroupID) async throws {
        guard try services.groups.group(id: group) != nil else { throw SyncError.groupNotFound }
        let zoneID = adapter.metadata.zoneID(forZoneName: group.description)
        guard zoneID.scope == .sharedDatabase else { return }
        coordinator.requestLeave(zoneName: zoneID.zoneName)
        // before sync has started the request just waits: it is stored, and the first reconcile picks it up
        guard let sharedSyncer = syncers.first(where: { $0.scope == .sharedDatabase }) else { return }
        try coordinator.reconcile()
        try? await sharedSyncer.sendChanges()
        try coordinator.reconcile()
        try await sharedSyncer.sendChanges()
    }
}
