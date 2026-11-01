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

    var status: SyncStatus { engine.status }

    /// Builds the engine for these services and starts it. Safe to call once per launch.
    func start(services: DataServices) async {
        guard !isRunning else { return }
        isRunning = true
        let notifier = notifier
        let automatic = AutomaticSyncEngine(probe: CloudKitAccountProbe()) { identifier in
            CloudKitSyncEngine(containerIdentifier: identifier, services: services, notifier: notifier)
        }
        engine = automatic
        await automatic.start()
        let invitations = waiting
        waiting = []
        for invitation in invitations {
            await accept(invitation)
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
        guard isRunning else {
            waiting.append(invitation)
            return
        }
        Task { await accept(invitation) }
    }

    private func accept(_ invitation: ShareInvitation) async {
        do {
            try await engine.accept(invitation)
            if let zone = invitation.metadata?.share.recordID.zoneID.zoneName, let id = UUID(uuidString: zone) {
                onGroupJoined?(GroupID(rawValue: id))
            }
        } catch {
            onInvitationFailed?(error.localizedDescription)
        }
    }

    // MARK: Push

    /// Called when a silent push arrives. Returns true if it was a CloudKit change notification.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return false }
        try? await engine.fetchChanges()
        return true
    }
}
