import Observation
import SwiftUI
import UIKit

/// Keeps Splt behind Face ID once the user has turned that on in Account.
///
/// The app starts locked and locks again after being away longer than `gracePeriod`, so a quick trip
/// to Venmo or a banking app to settle up doesn't ask for a face on the way back. Whenever the app
/// isn't the one in front, a cover hides the screen from the app switcher.
@MainActor
@Observable
final class AppLock {
    /// How long Splt can be out of sight before it asks again.
    static let gracePeriod: TimeInterval = 30

    private(set) var isLocked: Bool
    private(set) var isUnlocking = false

    @ObservationIgnored private let authenticator: any OwnerAuthenticating
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var leftAt: Date?
    /// Set when the app opens or comes back locked, until the Face ID prompt has been shown for it.
    @ObservationIgnored private var promptPending: Bool

    init(
        authenticator: any OwnerAuthenticating = BiometricAuth(),
        store: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.authenticator = authenticator
        self.store = store
        self.now = now
        let enabled = store.bool(forKey: Preferences.Key.biometricLockEnabled)
        isLocked = enabled
        promptPending = enabled
    }

    var isEnabled: Bool {
        store.bool(forKey: Preferences.Key.biometricLockEnabled)
    }

    var kind: BiometricKind { authenticator.kind() }

    /// Whether the phone can confirm its owner. Without a passcode there is nothing to lock behind.
    var isAvailable: Bool { authenticator.isAvailable() }

    /// Whether the screen should be hidden: while locked, and while another app or the system has the screen.
    func isCovering(phase: ScenePhase) -> Bool {
        isEnabled && (isLocked || phase != .active)
    }

    /// The app went to the background. Remembers when, to decide on return whether to lock.
    func didLeave() {
        if leftAt == nil { leftAt = now() }
    }

    /// The app is in front again. Locks if it was away for long enough. Returns whether it had been in
    /// the background, as opposed to only paused by the Face ID prompt or Control Center.
    @discardableResult
    func didReturn() -> Bool {
        defer { leftAt = nil }
        guard let leftAt else { return false }
        if isEnabled, !isLocked, now().timeIntervalSince(leftAt) >= Self.gracePeriod { isLocked = true }
        if isLocked { promptPending = true }
        return true
    }

    /// Whether to bring up Face ID now. True once per opening or return, so cancelling the prompt
    /// leaves the Unlock button instead of asking again straight away.
    func takePendingPrompt() -> Bool {
        defer { promptPending = false }
        return isLocked && promptPending
    }

    /// Asks for Face ID and opens the app on success. A cancelled or failed attempt leaves it locked.
    func unlock() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        if await authenticator.authenticate(reason: String(localized: "Unlock Splt")) {
            isLocked = false
        }
    }

    /// Confirms the owner before the setting is turned on, so it is never on with a lock that can't be opened.
    func confirmEnabling() async -> Bool {
        guard authenticator.isAvailable() else { return false }
        return await authenticator.authenticate(reason: String(localized: "Turn on the lock for Splt"))
    }
}

// MARK: - Screen

private struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: lock.kind.symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
            Text("Splt is Locked")
                .font(Typeface.heading)
                .foregroundStyle(Ink.text)
            // while it is just covered, there is nothing to tap
            if lock.isLocked {
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Text("Unlock with \(lock.kind.name)")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 48)
                .accessibilityIdentifier("lock.unlock")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper.ignoresSafeArea())
        .accessibilityIdentifier("lock.screen")
    }
}

// MARK: - Cover window

/// A window above everything, sheets and alerts included. A view laid over the app would leave an open
/// sheet, such as Account, showing on top of it.
@MainActor
private final class LockWindow {
    private var window: UIWindow?
    private var priorKeyWindow: UIWindow?

    func show(lock: AppLock) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .background })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        priorKeyWindow = scene.keyWindow
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreen(lock: lock))
        host.view.accessibilityViewIsModal = true
        cover.rootViewController = host
        cover.overrideUserInterfaceStyle = priorKeyWindow?.overrideUserInterfaceStyle ?? .unspecified
        // key, so a keyboard that was up goes away instead of showing in the app switcher
        cover.makeKeyAndVisible()
        window = cover
    }

    func hide() {
        guard let cover = window else { return }
        window = nil
        let prior = priorKeyWindow
        priorKeyWindow = nil
        UIView.animate(withDuration: 0.2) {
            cover.alpha = 0
        } completion: { _ in
            cover.isHidden = true
            prior?.makeKey()
        }
    }
}

extension View {
    /// Puts Splt behind the lock when the user has turned it on in Account.
    func appLock(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

private struct AppLockModifier: ViewModifier {
    let lock: AppLock
    // read so the cover re-evaluates the moment the setting changes
    @AppStorage(Preferences.Key.biometricLockEnabled) private var enabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var cover = LockWindow()

    func body(content: Content) -> some View {
        content
            .onAppear {
                refresh()
                if scenePhase == .active { promptIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    lock.didLeave()
                case .active:
                    lock.didReturn()
                    refresh()
                    promptIfNeeded()
                    return
                default:
                    break
                }
                refresh()
            }
            .onChange(of: enabled) { refresh() }
            .onChange(of: lock.isLocked) { refresh() }
    }

    private func refresh() {
        if lock.isCovering(phase: scenePhase) {
            cover.show(lock: lock)
        } else {
            cover.hide()
        }
    }

    /// Asks straight away, so opening the app lands on the Face ID prompt rather than a button.
    private func promptIfNeeded() {
        if lock.takePendingPrompt() { Task { await lock.unlock() } }
    }
}
