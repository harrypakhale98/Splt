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

    @ObservationIgnored private let container: CKContainer
    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let store: any SyncStateStore
    @ObservationIgnored private let broadcaster = StatusBroadcaster(initial: .idle)
    @ObservationIgnored private let notifier: RemoteChangeNotifier?
    @ObservationIgnored private let adapter: SyncStoreAdapter
    @ObservationIgnored private let coordinator: SyncCoordinator
    @ObservationIgnored private var syncers: [DatabaseSyncer] = []
    @ObservationIgnored private var observer: ContainerChangeObserver?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    init(
        containerIdentifier: String, services: DataServices,
        store: any SyncStateStore = FileSyncStateStore(), notifier: RemoteChangeNotifier? = nil
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.services = services
        self.store = store
        self.notifier = notifier
        self.adapter = SyncStoreAdapter(tracker: services.makeChangeTracker(), store: store)
        self.coordinator = SyncCoordinator(services: services, adapter: adapter)
        coordinator.setRetry(RetryScheduler { [weak self] in await self?.retryNow() })
        coordinator.onStatusChange = { [weak self] in self?.publish($0) }
        coordinator.onRemoteChanges = { [weak self] report in self?.notifier?.notify(for: report, services: self?.services) }
    }

    var statusUpdates: AsyncStream<SyncStatus> { broadcaster.updates() }

    // MARK: Lifecycle

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            let user = try await container.userRecordID()
            try coordinator.begin(user: user.recordName)
        } catch {
            isStarted = false
            publish(SyncFailure(error).status ?? .error(SyncFailure.genericMessage))
            return
        }

        let privateSyncer = DatabaseSyncer(
            scope: .privateDatabase, database: container.privateCloudDatabase, coordinator: coordinator, store: store
        )
        let sharedSyncer = DatabaseSyncer(
            scope: .sharedDatabase, database: container.sharedCloudDatabase, coordinator: coordinator, store: store
        )
        syncers = [privateSyncer, sharedSyncer]
        coordinator.attach(privateSyncer, for: .privateDatabase)
        coordinator.attach(sharedSyncer, for: .sharedDatabase)
        let hadState = privateSyncer.hasSavedState
        syncers.forEach { $0.start() }

        observer = ContainerChangeObserver(container: services.container) { [weak self] in
            self?.scheduleReconcile()
        }
        tasks.append(Task { [weak self] in await self?.watchConnectivity() })
        tasks.append(Task { [weak self] in await self?.firstSync(alreadySynced: hadState) })
        try? adapter.purgeOldTombstones()
    }

    func stop() async {
        isStarted = false
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

    private func watchConnectivity() async {
        for await online in ConnectivityMonitor().updates() {
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
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.reconcileTask = nil
            try? self.coordinator.reconcile()
        }
    }

    private func retryNow() async {
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

    func share(group: GroupID) async throws -> GroupShare {
        guard let value = try services.groups.group(id: group) else { throw SyncError.groupNotFound }
        let zoneID = adapter.metadata.zoneID(forZoneName: group.description)
        let service = ShareService(container: container)
        if zoneID.scope == .sharedDatabase {
            guard let existing = try await service.share(zoneID: zoneID) else { throw SyncError.notShared }
            return GroupShare(share: existing, container: container, groupName: value.name)
        }
        guard let privateSyncer = syncers.first(where: { $0.scope == .privateDatabase }) else { throw SyncError.notReady }
        try coordinator.reconcile()
        try await privateSyncer.sendChanges()
        let share = try await service.prepare(zoneID: zoneID, title: value.name)
        return GroupShare(share: share, container: container, groupName: value.name)
    }

    func accept(_ invitation: ShareInvitation) async throws {
        guard let metadata = invitation.metadata else { throw SyncError.invalidInvitation }
        guard metadata.containerIdentifier == container.containerIdentifier else { throw SyncError.invalidInvitation }
        guard isStarted else { throw SyncError.notReady }
        _ = try await container.accept(metadata)
        try await fetchChanges()
    }

    func leave(group: GroupID) async throws {
        guard try services.groups.group(id: group) != nil else { throw SyncError.groupNotFound }
        let zoneID = adapter.metadata.zoneID(forZoneName: group.description)
        if zoneID.scope == .privateDatabase {
            try await ShareService(container: container).stopSharing(zoneID: zoneID)
            return
        }
        guard let sharedSyncer = syncers.first(where: { $0.scope == .sharedDatabase }) else { throw SyncError.notReady }
        try adapter.tracker.retireLocally(zone: zoneID.zoneName)
        sharedSyncer.queue(zonesToDelete: [zoneID])
        try await sharedSyncer.sendChanges()
    }
}
