import CloudKit
import Foundation
import SpltCore
import Synchronization
@testable import Splt

/// An engine that records what it was asked and reports a status you can set.
@MainActor
final class FakeSyncEngine: SyncEngine {
    let identifier: String
    private let broadcaster = StatusBroadcaster(initial: .idle)
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var sendCount = 0
    private(set) var fetchCount = 0
    private(set) var accepted: [ShareInvitation] = []
    private(set) var left: [GroupID] = []

    init(identifier: String = "fake") {
        self.identifier = identifier
    }

    var status: SyncStatus { broadcaster.current }
    var statusUpdates: AsyncStream<SyncStatus> { broadcaster.updates() }

    func report(_ status: SyncStatus) {
        broadcaster.send(status)
    }

    func start() async { startCount += 1 }
    var beforeStop: (@MainActor () async -> Void)?
    func stop() async {
        stopCount += 1
        await beforeStop?()
    }
    func sendChanges() async throws { sendCount += 1 }
    func fetchChanges() async throws { fetchCount += 1 }

    func share(group: GroupID) async throws -> GroupShare {
        throw SyncError.unavailable
    }

    func accept(_ invitation: ShareInvitation) async throws {
        accepted.append(invitation)
    }

    func leave(group: GroupID) async throws {
        left.append(group)
    }
}

final class FakeAccountProbe: AccountProbe {
    private let state: Mutex<AccountAvailability>
    private let asked = Mutex<[String]>([])

    init(_ availability: AccountAvailability) {
        state = Mutex(availability)
    }

    func set(_ availability: AccountAvailability) {
        state.withLock { $0 = availability }
    }

    var requests: [String] { asked.withLock { $0 } }

    func availability(containerIdentifier: String) async -> AccountAvailability {
        asked.withLock { $0.append(containerIdentifier) }
        return state.withLock { $0 }
    }
}

extension Entitlements {
    static func cloudKit(_ containers: String...) -> Entitlements {
        Entitlements(values: [
            "com.apple.developer.icloud-container-identifiers": .strings(containers),
            "com.apple.developer.icloud-services": .strings(["CloudKit"]),
        ])
    }
}

extension SyncEnvironment {
    /// A signed device build with an iCloud account, the one case that may use CloudKit.
    static func signedDevice(
        entitlements: Entitlements = .cloudKit("iCloud.com.example.app"), hasIdentityToken: Bool = true
    ) -> SyncEnvironment {
        SyncEnvironment(
            isSimulator: false, isPreview: false, isTesting: false,
            entitlements: entitlements, hasIdentityToken: hasIdentityToken
        )
    }
}

/// Waits until the condition holds, for tests of code that reacts on another task.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
