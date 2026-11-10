import CloudKit
import Foundation

/// What the coordinator needs from one CKSyncEngine, so the logic can be tested with a fake.
@MainActor
protocol EngineQueue: AnyObject {
    func queue(_ plan: OutgoingPlan)
    func queue(saves: [CKRecord.ID])
    func queue(zonesToSave: [CKRecordZone.ID])
    func sendChanges() async throws
    func fetchChanges() async throws
}

enum SyncAccountChange: Equatable, Sendable {
    case signedIn(user: String)
    case signedOut
    case switched(to: String)
}

/// Everything that happens between CloudKit events and the data store: what to queue, how to
/// apply what arrived, how to react to failures. The CKSyncEngine glue only translates events.
@MainActor
final class SyncCoordinator {
    let adapter: SyncStoreAdapter
    let services: DataServices
    private(set) var userRecordName: String?
    private(set) var machine = SyncStatusMachine()
    private(set) var isReady = false
    private var queues: [DatabaseScope: any EngineQueue] = [:]
    private var retry: RetryScheduler?

    /// Called with the report of every batch of remote changes, for notifications and similar.
    var onRemoteChanges: (@MainActor (ApplyReport) -> Void)?
    var onSuggestions: (@MainActor ([ClaimSuggestion]) -> Void)?
    var onStatusChange: (@MainActor (SyncStatus) -> Void)?

    init(services: DataServices, adapter: SyncStoreAdapter, retry: RetryScheduler? = nil) {
        self.services = services
        self.adapter = adapter
        self.retry = retry
    }

    func setRetry(_ scheduler: RetryScheduler) {
        retry = scheduler
    }

    /// Plans another attempt to start after `begin` failed.
    func startFailed(_ error: any Error) {
        retry?.failed(SyncFailure(error))
    }

    func cancelRetry() {
        retry?.cancel()
    }

    /// Accepting an invitation makes this person a member, even if they were removed or left before.
    func joined(zoneName: String) throws {
        adapter.updateMetadata { $0.pendingLeaves?.remove(zoneName) }
        guard let user = userRecordName else { return }
        try ParticipantImporter(services: services).ensureMembership(ofMe: user, inZone: zoneName, afterInvitation: true)
    }

    func attach(_ queue: any EngineQueue, for scope: DatabaseScope) {
        queues[scope] = queue
    }

    var status: SyncStatus { machine.status }

    // MARK: Lifecycle

    func begin(user: String) throws {
        userRecordName = user
        try adoptIdentity()
        if let known = adapter.metadata.userRecordName, known != user {
            try adapter.resetForNewAccount(userRecordName: user)
        } else {
            adapter.updateMetadata { $0.userRecordName = user }
        }
    }

    /// Local changes are only queued once the first fetch has told us which zones are shared.
    func markReady() {
        isReady = true
    }

    func adoptIdentity() throws {
        guard let user = userRecordName else { return }
        try IdentityAdopter(tracker: adapter.tracker).adopt(userRecordName: user)
    }

    // MARK: Queueing

    /// Queues everything the data store has waiting.
    func reconcile(givingUpOn refused: Set<String> = []) throws {
        guard isReady else { return }
        try adoptIdentity()
        try finishLeaves(givingUpOn: refused)
        let plan = try adapter.collectOutgoing()
        guard !plan.isEmpty else { return }
        for scope in DatabaseScope.allCases {
            let part = plan.part(for: scope)
            if !part.isEmpty { queues[scope]?.queue(part) }
        }
    }

    /// Remembers that this person is leaving a shared group. The zone is given up once what they
    /// still have to send, such as leaving the member list, has gone out: after that they cannot write to it.
    func requestLeave(zoneName: String) {
        adapter.updateMetadata { $0.pendingLeaves = ($0.pendingLeaves ?? []).union([zoneName]) }
    }

    private func finishLeaves(givingUpOn refused: Set<String>) throws {
        for zone in (adapter.metadata.pendingLeaves ?? []).sorted() {
            if adapter.metadata.scope(forZoneName: zone) == .sharedDatabase {
                if !refused.contains(zone), try adapter.tracker.hasUnsentChanges(inZone: zone) { continue }
                try adapter.tracker.retireForLeaving(zone: zone)
            }
            adapter.updateMetadata { $0.pendingLeaves?.remove(zone) }
        }
    }

    /// Remembers whether a group in your own iCloud is shared, for when the server cannot be asked.
    func noteOwnShare(zoneName: String, exists: Bool) {
        adapter.updateMetadata { metadata in
            var owned = metadata.ownedShares ?? []
            if exists { owned.insert(zoneName) } else { owned.remove(zoneName) }
            metadata.ownedShares = owned
        }
    }

    func updateStatus(_ change: (inout SyncStatusMachine) -> Void) {
        let before = machine.status
        change(&machine)
        if machine.status != before { onStatusChange?(machine.status) }
    }

    // MARK: Fetched

    func fetchedZones(
        modified: [CKRecordZone.ID], deleted: [(id: CKRecordZone.ID, reason: ZoneDeletionReason)]
    ) throws {
        modified.forEach(adapter.registerZone)
        var needsSend = false
        for zone in deleted {
            needsSend = try adapter.zoneDeleted(zone.id, reason: zone.reason) || needsSend
        }
        if needsSend { try reconcile() }
    }

    func fetchedRecords(modifications: [CKRecord], deletions: [(id: CKRecord.ID, recordType: String)]) throws {
        let report = try adapter.applyFetched(modifications: modifications, deletions: deletions)
        for id in report.requeue {
            queues[id.zoneID.scope]?.queue(saves: [id])
        }
        try afterRemoteChanges(report)
        onRemoteChanges?(report)
    }

    private func afterRemoteChanges(_ report: ApplyReport) throws {
        guard let user = userRecordName else { return }
        let importer = ParticipantImporter(services: services)
        var suggestions: [ClaimSuggestion] = []
        for share in report.shares {
            let zone = share.recordID.zoneID
            if zone.scope == .privateDatabase { noteOwnShare(zoneName: zone.zoneName, exists: true) }
            suggestions += try importer.importPeople(from: ParticipantMapper.snapshots(from: share), myUserRecordName: user)
        }
        for zone in report.touchedZones where adapter.metadata.scope(forZoneName: zone) == .sharedDatabase {
            try importer.ensureMembership(ofMe: user, inZone: zone)
        }
        if !suggestions.isEmpty { onSuggestions?(suggestions) }
        if !report.shares.isEmpty || !report.touchedZones.isEmpty { try reconcile() }
    }

    // MARK: Sent

    func sentZones(
        saved: [CKRecordZone], failedSaves: [(zone: CKRecordZone, error: CKError)],
        deleted: [CKRecordZone.ID], failedDeletes: [CKRecordZone.ID: CKError], scope: DatabaseScope
    ) throws {
        adapter.zonesSaved(saved)
        for id in deleted {
            try adapter.zoneDeleteConfirmed(id)
        }
        var failures: [SyncFailure] = failedSaves.map { SyncFailure($0.error) }
        for (id, error) in failedDeletes {
            if SyncFailure(error) == .zoneMissing {
                try adapter.zoneDeleteConfirmed(id)
            } else {
                failures.append(SyncFailure(error))
            }
        }
        noteResult(failures: failures, scope: scope)
    }

    func sentRecords(
        saved: [CKRecord], failedSaves: [(record: CKRecord, error: CKError)],
        deleted: [CKRecord.ID], failedDeletes: [CKRecord.ID: CKError], scope: DatabaseScope
    ) throws {
        let orphans = try adapter.didSend(saved: saved, deleted: deleted)
        if !orphans.isEmpty { queues[scope]?.queue(OutgoingPlan(deletes: orphans)) }
        var failures: [SyncFailure] = []
        var missingZones: [CKRecordZone.ID: [CKRecord.ID]] = [:]
        for failed in failedSaves {
            let outcome = try adapter.saveFailed(record: failed.record, error: failed.error)
            if let zone = outcome.askServerAbout { missingZones[zone, default: []].append(failed.record.recordID) }
            if outcome.requeue { queues[scope]?.queue(saves: [failed.record.recordID]) }
            if let zone = outcome.recreateZone { queues[scope]?.queue(zonesToSave: [zone]) }
            if let zone = outcome.goneZone { try fetchedZones(modified: [], deleted: [(zone, .deleted)]) }
            if outcome.failure != .conflict { failures.append(outcome.failure) }
        }
        for (id, error) in failedDeletes {
            failures.append(try adapter.deleteFailed(id: id, error: error))
        }
        if !missingZones.isEmpty {
            Task { [weak self] in await self?.settleMissingZones(missingZones, scope: scope) }
        }
        noteResult(failures: failures, scope: scope)
        // no permission means the zone is no longer ours, so a leave has nothing more to wait for
        let refused = failedSaves.filter { SyncFailure($0.error) == .noPermission }.map(\.record.recordID.zoneID.zoneName)
        if failures.isEmpty || !refused.isEmpty { try reconcile(givingUpOn: Set(refused)) }
    }

    /// A fetch reports a zone deleted elsewhere or lost by the server, and both are handled there. If the zone
    /// is still known afterwards nothing explains it, so it is made again. If the fetch fails, the changes stay
    /// dirty and the next attempt asks again.
    private func settleMissingZones(_ zones: [CKRecordZone.ID: [CKRecord.ID]], scope: DatabaseScope) async {
        guard let queue = queues[scope], (try? await queue.fetchChanges()) != nil else { return }
        for (zone, records) in zones where adapter.metadata.isKnown(zoneName: zone.zoneName) {
            adapter.updateMetadata { $0.zones[zone.zoneName] = nil }
            queue.queue(zonesToSave: [zone])
            queue.queue(saves: records)
        }
    }

    private func noteResult(failures: [SyncFailure], scope: DatabaseScope) {
        let source = SyncStatusMachine.Source(scope: scope, isSending: true)
        if let worst = failures.first(where: { $0.status != nil }) ?? failures.first {
            updateStatus { $0.failed(worst, source: source) }
            retry?.failed(worst)
        } else {
            updateStatus { $0.succeeded(source: source) }
            retry?.succeeded()
        }
    }

    func fetchSucceeded(scope: DatabaseScope) {
        updateStatus { $0.succeeded(source: .init(scope: scope, isSending: false)) }
    }

    func fetchFailed(_ error: any Error, scope: DatabaseScope) {
        let failure = SyncFailure(error)
        updateStatus { $0.failed(failure, source: .init(scope: scope, isSending: false)) }
        retry?.failed(failure)
    }

    // MARK: Account

    func accountChanged(_ change: SyncAccountChange) throws {
        switch change {
        case .signedIn(let user):
            try begin(user: user)
            updateStatus { $0.clearProblems() }
        case .signedOut:
            updateStatus { $0.failed(.noAccount, source: .init(scope: .privateDatabase, isSending: false)) }
        case .switched(let user):
            userRecordName = user
            try adoptIdentity()
            try adapter.resetForNewAccount(userRecordName: user)
            updateStatus { $0.clearProblems() }
        }
    }
}
