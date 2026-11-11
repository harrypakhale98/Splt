import CloudKit
import Foundation
import Observation
import SpltCore

/// The one place the app talks to sync. The app creates it at launch with the data services, and
/// the app and scene delegates reach it for push notifications and share invitations.
@MainActor
@Observable
final class SyncRuntime {
    static let shared = SyncRuntime()

    /// The engine to hand to Settings and the sharing UI. A no-op engine until `configure` runs.
    private(set) var engine: any SyncEngine = NoOpSyncEngine()
    /// Called after an invitation was accepted, with the group that arrived.
    @ObservationIgnored var onGroupJoined: (@MainActor (GroupID) -> Void)?
    /// Called when accepting an invitation failed, with text fit for an alert.
    @ObservationIgnored var onInvitationFailed: (@MainActor (String) -> Void)?
    @ObservationIgnored private let notifier = RemoteChangeNotifier()
    @ObservationIgnored private var waiting: [ShareInvitation] = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let liveServices: @MainActor () -> DataServices?
    @ObservationIgnored private let leftGroups: LeftGroupsStore
    @ObservationIgnored private let invitationRetry: Duration
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private let invitationRetryLimit: Int
    @ObservationIgnored private var retriesLeft = 0
    /// Groups joined on this device that have not arrived yet, and when each was joined. One that
    /// arrives soon is opened. Later the person is doing something else and would be pulled out of it.
    @ObservationIgnored private var awaitingArrival: [GroupID: ContinuousClock.Instant] = [:]
    @ObservationIgnored private let arrivalWindow: Duration
    @ObservationIgnored private let makeEngine: (@MainActor (DataServices) -> any SyncEngine)?

    /// `makeEngine` replaces the engine that `start` builds, for tests.
    init(
        liveServices: @escaping @MainActor () -> DataServices? = { IntentServices.shared.live() },
        leftGroups: LeftGroupsStore = LeftGroupsStore(),
        invitationRetry: Duration = .seconds(2),
        invitationRetryLimit: Int = 30,
        arrivalWindow: Duration = .seconds(60),
        makeEngine: (@MainActor (DataServices) -> any SyncEngine)? = nil
    ) {
        self.liveServices = liveServices
        self.leftGroups = leftGroups
        self.invitationRetry = invitationRetry
        self.invitationRetryLimit = invitationRetryLimit
        self.arrivalWindow = arrivalWindow
        self.makeEngine = makeEngine
    }

    var status: SyncStatus { engine.status }

    /// True while sync is on and has not yet fetched what iCloud holds. A backup restored now can add
    /// copies of groups that are still on their way.
    var isFetchingForTheFirstTime: Bool {
        switch engine.status {
        case .unavailable(.starting): true
        case .idle, .syncing, .offline, .error: !engine.hasFetchedOnce
        case .noAccount, .restricted, .unavailable: false
        }
    }

    /// Builds the engine for these services and starts it. Safe to call once per launch.
    func start(services: DataServices) async {
        guard !isRunning else { return }
        isRunning = true
        let started = makeEngine?(services) ?? automaticEngine(services: services)
        engine = started
        await started.start()
        retriesLeft = invitationRetryLimit
        await answerWaiting()
    }

    private func automaticEngine(services: DataServices) -> any SyncEngine {
        let notifier = notifier
        return AutomaticSyncEngine(probe: CloudKitAccountProbe()) { [weak self] identifier in
            let engine = CloudKitSyncEngine(containerIdentifier: identifier, services: services, notifier: notifier)
            engine.onMembership = { self?.groupArrived($0) }
            return engine
        }
    }

    /// Replaces the engine, for previews and tests.
    func use(_ engine: any SyncEngine) {
        self.engine = engine
    }

    func requestNotificationAuthorization() async -> Bool {
        await notifier.requestAuthorization()
    }

    // MARK: Invitations

    /// Called by the scene delegate. Invitations that arrive before launch finished are kept until sync starts.
    func receive(_ invitation: ShareInvitation) {
        waiting.append(invitation)
        retriesLeft = invitationRetryLimit
        guard isRunning else { return }
        Task { await answerWaiting() }
    }

    /// Answers the invitations that can be answered now. One that sync is not ready for goes back in the
    /// queue and is tried again shortly: at a cold launch the account is still being checked. After
    /// about a minute of that it is given up and the person is told.
    private func answerWaiting() async {
        let invitations = waiting
        waiting = []
        for invitation in invitations {
            await accept(invitation)
        }
        guard !waiting.isEmpty, retry == nil else { return }
        guard retriesLeft > 0 else {
            // sync never became ready, so say so instead of trying for ever
            waiting = []
            onInvitationFailed?(SyncFailure.message(for: SyncError.notReady))
            return
        }
        retriesLeft -= 1
        retry = Task { [weak self, invitationRetry] in
            try? await Task.sleep(for: invitationRetry)
            self?.retry = nil
            await self?.answerWaiting()
        }
    }

    private func accept(_ invitation: ShareInvitation) async {
        do {
            try await engine.accept(invitation)
            if let zone = invitation.metadata?.share.recordID.zoneID.zoneName, let id = UUID(uuidString: zone) {
                groupJoined(GroupID(rawValue: id))
            }
        } catch SyncError.notReady {
            waiting.append(invitation)
        } catch {
            onInvitationFailed?(SyncFailure.message(for: error))
        }
    }

    /// A group you left and were invited back to belongs in your list again. It is opened once it is
    /// on this device, which after a slow fetch is a little later.
    func groupJoined(_ group: GroupID) {
        leftGroups.remove(group)
        if let services = liveServices(), (try? services.groups.group(id: group)) == nil {
            awaitingArrival[group] = .now
            return
        }
        onGroupJoined?(group)
    }

    /// Changes arrived for a shared group you are a member of, so it is not one you left. You may have
    /// joined it again on another device, or its first fetch failed after the invitation was accepted.
    func groupArrived(_ group: GroupID) {
        if leftGroups.contains(group) { leftGroups.remove(group) }
        if let joined = awaitingArrival.removeValue(forKey: group), .now - joined <= arrivalWindow {
            onGroupJoined?(group)
        }
    }

    // MARK: Push

    /// Called when a silent push arrives. Returns true if it was a CloudKit change notification.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return false }
        // a push can launch the app in the background, where no screen ever starts sync
        if !isRunning, let services = liveServices() { await start(services: services) }
        try? await engine.fetchChanges()
        return true
    }
}
