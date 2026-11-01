import CloudKit
import SwiftUI
import UIKit

/// Registers for the silent pushes CloudKit uses to say "something changed", and hands share
/// invitations to the scene delegate. Add it to the app with `@UIApplicationDelegateAdaptor`.
final class SyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if EntitlementReader.current().values["aps-environment"] != nil {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let handled = await SyncRuntime.shared.handleRemoteNotification(userInfo)
        return handled ? .newData : .noData
    }

    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SyncSceneDelegate.self
        return configuration
    }
}

/// Receives the invitation when someone taps a Splt share link.
final class SyncSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let invitation = ShareInvitation(metadata: metadata)
        Task { @MainActor in SyncRuntime.shared.receive(invitation) }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        let invitation = ShareInvitation(metadata: metadata)
        Task { @MainActor in SyncRuntime.shared.receive(invitation) }
    }
}
