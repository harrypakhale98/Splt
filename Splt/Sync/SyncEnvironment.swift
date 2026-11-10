import Foundation

/// How signed in the user is to iCloud, in terms the engine choice needs.
enum AccountAvailability: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    /// Could not be determined, for example the network or iCloud is momentarily unavailable.
    case unknown
}

/// Why the app is running without sync.
enum NoOpReason: Equatable, Sendable {
    case simulator
    case preview
    case testing
    case missingEntitlement
    case noAccount
    case restricted
    case accountUnavailable

    /// True when this build can sync and only the account stands in the way.
    var isAboutTheAccount: Bool {
        switch self {
        case .noAccount, .restricted, .accountUnavailable: true
        case .simulator, .preview, .testing, .missingEntitlement: false
        }
    }

    var status: SyncStatus {
        switch self {
        case .simulator: .unavailable(.simulator)
        case .preview, .testing: .unavailable(.developerBuild)
        case .missingEntitlement: .unavailable(.notSetUp)
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .accountUnavailable: .offline
        }
    }
}

enum SyncEngineChoice: Equatable, Sendable {
    case cloudKit(containerIdentifier: String)
    case noOp(NoOpReason)
}

/// The facts that decide whether the CloudKit engine may run.
struct SyncEnvironment: Equatable, Sendable {
    var isSimulator: Bool
    var isPreview: Bool
    var isTesting: Bool
    var entitlements: Entitlements
    /// `FileManager.ubiquityIdentityToken` is not nil: someone is signed in to iCloud.
    var hasIdentityToken: Bool

    static var current: SyncEnvironment {
        let variables = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return SyncEnvironment(
            isSimulator: simulator,
            isPreview: variables["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
            isTesting: variables["XCTestConfigurationFilePath"] != nil
                || variables["XCTestBundlePath"] != nil
                || NSClassFromString("XCTestCase") != nil,
            entitlements: EntitlementReader.current(),
            hasIdentityToken: FileManager.default.ubiquityIdentityToken != nil
        )
    }
}

/// Picks the engine. Account status is only asked for once the cheap checks pass, because
/// asking needs a `CKContainer` and that traps in a build without the iCloud entitlement.
enum SyncEngineSelector {
    /// A reason to skip CloudKit that needs no container, or nil when the account should be checked.
    static func preflight(_ environment: SyncEnvironment) -> NoOpReason? {
        if environment.isTesting { return .testing }
        if environment.isPreview { return .preview }
        if environment.isSimulator { return .simulator }
        if environment.entitlements.cloudKitContainers.isEmpty { return .missingEntitlement }
        if !environment.hasIdentityToken { return .noAccount }
        return nil
    }

    static func decide(_ environment: SyncEnvironment, account: AccountAvailability) -> SyncEngineChoice {
        if let reason = preflight(environment) { return .noOp(reason) }
        guard let container = environment.entitlements.cloudKitContainers.first else {
            return .noOp(.missingEntitlement)
        }
        switch account {
        case .available: return .cloudKit(containerIdentifier: container)
        case .noAccount: return .noOp(.noAccount)
        case .restricted: return .noOp(.restricted)
        case .unknown: return .noOp(.accountUnavailable)
        }
    }
}
