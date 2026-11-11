import CloudKit
import Foundation
import SpltCore

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
    /// The databases whose last send or fetch failed. One retry serves both, so a success in one must
    /// not call off the retry the other is waiting for.
    private var failingScopes: Set<DatabaseScope> = []

    /// Called with the report of every batch of remote changes, for notifications and similar.
    var onRemoteChanges: (@MainActor (ApplyReport) -> Void)?
    var onStatusChange: (@MainActor (SyncStatus) -> Void)?
    /// Called when changes arrive for a group someone else shared and this person is a member of it.
    var onMembership: (@MainActor (GroupID) -> Void)?

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
        failingScopes.removeAll()
        retry?.cancel()
    }

    /// Accepting an invitation makes this person a member, even if they were removed or left before.
    /// The group may not be on this device yet, so the invitation is remembered until it is.
    func joined(zoneName: String) throws {
        adapter.updateMetadata {
            $0.pendingLeaves?.remove(zoneName)
            $0.pendingJoins = ($0.pendingJoins ?? []).union([zoneName])
        }
        guard let user = userRecordName else { return }
        try settleMembership(of: user, inZone: zoneName)
    }

    private func settleMembership(of user: String, inZone zone: String) throws {
        let invited = adapter.metadata.pendingJoins?.contains(zone) == true
        let importer = ParticipantImporter(services: services)
        guard try importer.ensureMembership(ofMe: user, inZone: zone, afterInvitation: invited) else { return }
        adapter.updateMetadata { $0.pendingJoins?.remove(zone) }
        // a group that is being left stays hidden while its last changes go out
        guard adapter.metadata.pendingLeaves?.contains(zone) != true, let id = UUID(uuidString: zone) else { return }
        onMembership?(GroupID(rawValue: id))
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
            var part = plan.part(for: scope)
            // a group whose share record could not be deleted is left by giving up its zone instead
            let byZone = part.zonesToLeave.filter { leavingByZone.contains($0.zoneName) }
            if !byZone.isEmpty {
                part.zonesToLeave.removeAll { leavingByZone.contains($0.zoneName) }
                part.zonesToDelete += byZone
            }
            if !part.isEmpty { queues[scope]?.queue(part) }
        }
    }

    /// Shared groups for which CloudKit refused the delete of the share record. They are left the
    /// way earlier versions left, and a refusal of that too is a failure like any other.
    private var leavingByZone: Set<String> = []

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

    /// A fetch that began with no saved state, in which the server lists every zone it holds.
    private struct FetchFromNothing {
        /// The zones this device already knew were in iCloud when the fetch began. Only these can be
        /// found missing: one made here afterwards is not listed back to the device that made it.
        var known: Set<String>
        var listed: Set<String> = []
    }

    /// No entry while fetches are ordinary ones, which only list what changed.
    private var fetchesFromNothing: [DatabaseScope: FetchFromNothing] = [:]

    /// An engine is about to fetch with no saved state.
    func fetchFromNothingBegan(scope: DatabaseScope) {
        let known = adapter.metadata.zones.filter { $0.value.scope == scope }.keys
        fetchesFromNothing[scope] = FetchFromNothing(known: Set(known))
    }

    /// That fetch went through. A zone this device knew was in iCloud and that was not listed is gone
    /// from there, which no event will ever say: deleted on another device while this one could not
    /// follow, or along with all of the app's iCloud data. It must not be sent back. A group of your
    /// own stays as a local copy, so nothing is lost here. One somebody else shared is theirs to
    /// remove, as when the fetch itself says so.
    func fetchFromNothingFinished(scope: DatabaseScope) throws {
        guard let fetch = fetchesFromNothing.removeValue(forKey: scope) else { return }
        for name in fetch.known.subtracting(fetch.listed).sorted() {
            guard let info = adapter.metadata.zones[name], info.scope == scope else { continue }
            let zone = CKRecordZone.ID(zoneName: name, ownerName: info.ownerName)
            try adapter.zoneDeleted(zone, reason: scope == .privateDatabase ? .purged : .deleted)
        }
    }

    func fetchedZones(
        modified: [CKRecordZone.ID], deleted: [(id: CKRecordZone.ID, reason: ZoneDeletionReason)]
    ) throws {
        modified.forEach(adapter.registerZone)
        for zone in modified {
            fetchesFromNothing[zone.scope]?.listed.insert(zone.zoneName)
        }
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
        foldItemClaims(inZones: report.touchedZones)
        try afterRemoteChanges(report)
        onRemoteChanges?(report)
    }

    /// Picks that arrived are folded into the expenses this person added. The edit is sent with
    /// the reconcile that follows. A fold that fails is tried again with the next change or launch,
    /// so it never stops the sync.
    private func foldItemClaims(inZones zones: Set<String>) {
        let groups = Set(zones.compactMap(GroupID.init(uuidString:)))
        guard !groups.isEmpty else { return }
        _ = try? services.claims.foldClaims(inGroups: groups)
    }

    private func afterRemoteChanges(_ report: ApplyReport) throws {
        guard let user = userRecordName else { return }
        let importer = ParticipantImporter(services: services)
        for share in report.shares {
            let zone = share.recordID.zoneID
            if zone.scope == .privateDatabase { noteOwnShare(zoneName: zone.zoneName, exists: true) }
            try importer.importPeople(from: ParticipantMapper.snapshots(from: share), myUserRecordName: user)
        }
        for zone in report.touchedZones where adapter.metadata.scope(forZoneName: zone) == .sharedDatabase {
            try settleMembership(of: user, inZone: zone)
        }
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
        // A share record this device deleted is this person having left that group.
        for share in deleted where share.recordName == CKRecordNameZoneWideShare {
            try adapter.zoneDeleteConfirmed(share.zoneID)
        }
        let orphans = try adapter.didSend(saved: saved, deleted: deleted.filter { $0.recordName != CKRecordNameZoneWideShare })
        if !orphans.isEmpty { queues[scope]?.queue(OutgoingPlan(deletes: orphans)) }
        var failures: [SyncFailure] = []
        var missingZones: Set<CKRecordZone.ID> = []
        for failed in failedSaves {
            let outcome = try adapter.saveFailed(record: failed.record, error: failed.error)
            if let zone = outcome.askServerAbout { missingZones.insert(zone) }
            if outcome.requeue { queues[scope]?.queue(saves: [failed.record.recordID]) }
            if let zone = outcome.recreateZone { queues[scope]?.queue(zonesToSave: [zone]) }
            if let zone = outcome.goneZone { try fetchedZones(modified: [], deleted: [(zone, .deleted)]) }
            if let zone = outcome.purgedZone { try fetchedZones(modified: [], deleted: [(zone, .purged)]) }
            if outcome.failure != .conflict { failures.append(outcome.failure) }
        }
        for (id, error) in failedDeletes {
            guard id.recordName == CKRecordNameZoneWideShare else {
                failures.append(try adapter.deleteFailed(id: id, error: error))
                continue
            }
            let failure = SyncFailure(error)
            if failure == .itemMissing || failure == .zoneMissing {
                // the share is gone already, so there is nothing left to leave
                try adapter.zoneDeleteConfirmed(id.zoneID)
            } else if failure.isRefusal, !leavingByZone.contains(id.zoneID.zoneName) {
                // Deleting the share record is how CloudKit says a participant leaves. If it will not
                // have that, give the zone up instead, which is how earlier versions left.
                leavingByZone.insert(id.zoneID.zoneName)
                queues[scope]?.queue(OutgoingPlan(zonesToDelete: [id.zoneID]))
            } else {
                failures.append(failure)
            }
        }
        if !missingZones.isEmpty {
            // This runs inside CKSyncEngine's delegate callback. A plain Task inherits that context, and
            // CKSyncEngine traps when a call made from it calls back into the delegate, as a fetch does.
            Task.detached { [weak self] in await self?.settleMissingZones(missingZones, scope: scope) }
        }
        noteResult(failures: failures, scope: scope)
        // no permission means the zone is no longer ours, so a leave has nothing more to wait for
        let refused = failedSaves.filter { SyncFailure($0.error) == .noPermission }.map(\.record.recordID.zoneID.zoneName)
        if failures.isEmpty || !refused.isEmpty { try reconcile(givingUpOn: Set(refused)) }
    }

    /// A fetch reports a zone deleted elsewhere or lost by the server, and both are handled there. If the zone
    /// is still known afterwards nothing explains it, so it is treated as lost: the whole group is uploaded
    /// again, never only the records whose save failed. If the fetch fails, the changes stay dirty and the
    /// next attempt asks again.
    private func settleMissingZones(_ zones: Set<CKRecordZone.ID>, scope: DatabaseScope) async {
        guard let queue = queues[scope], (try? await queue.fetchChanges()) != nil else { return }
        var needsSend = false
        for zone in zones where adapter.metadata.isKnown(zoneName: zone.zoneName) {
            needsSend = (try? adapter.zoneDeleted(zone, reason: .lost)) == true || needsSend
        }
        if needsSend { try? reconcile() }
    }

    private func noteResult(failures: [SyncFailure], scope: DatabaseScope) {
        let source = SyncStatusMachine.Source(scope: scope, isSending: true)
        if let worst = failures.first(where: { $0.status != nil }) ?? failures.first {
            updateStatus { $0.failed(worst, source: source) }
            failingScopes.insert(scope)
            retry?.failed(worst)
        } else {
            updateStatus { $0.succeeded(source: source) }
            failingScopes.remove(scope)
            if failingScopes.isEmpty { retry?.succeeded() }
        }
    }

    func fetchSucceeded(scope: DatabaseScope) {
        updateStatus { $0.succeeded(source: .init(scope: scope, isSending: false)) }
    }

    func fetchFailed(_ error: any Error, scope: DatabaseScope) {
        let failure = SyncFailure(error)
        updateStatus { $0.failed(failure, source: .init(scope: scope, isSending: false)) }
        failingScopes.insert(scope)
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
