import LocalAuthentication

/// What the phone can use to prove it is its owner, named the way the phone names it.
enum BiometricKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// No biometrics enrolled, so the passcode is what unlocks.
    case passcode

    var name: String {
        switch self {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        case .passcode: String(localized: "Passcode")
        }
    }

    var symbol: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode: "lock"
        }
    }
}

/// Asks the phone to confirm its owner. A seam, so the lock can be tested without a face.
protocol OwnerAuthenticating: Sendable {
    /// Whether the phone can confirm its owner at all. False when it has no passcode.
    func isAvailable() -> Bool
    /// True when the phone has no passcode at all, so nothing can confirm its owner and a lock
    /// that was on could never be opened.
    func isPasscodeMissing() -> Bool
    func kind() -> BiometricKind
    func authenticate(reason: String) async -> Bool
}

struct BiometricAuth: OwnerAuthenticating {
    func isAvailable() -> Bool {
        // the passcode policy, so a phone with a passcode but no face enrolled still works
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func isPasscodeMissing() -> Bool {
        var error: NSError?
        _ = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return error?.code == LAError.passcodeNotSet.rawValue
    }

    func kind() -> BiometricKind {
        let context = LAContext()
        // biometryType is only filled in after the policy has been checked
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    /// Face ID first, with the passcode as the way out, so a face that won't read never locks anyone out.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
