import Foundation
import SwiftUI

enum LaunchServices {
    /// The data the app runs on. Debug builds accept `-uitesting` to start on an empty in-memory store for
    /// UI tests, `-sampledata` to start on the sample trip, and `-nostore` to act as if the store failed to open.
    @MainActor
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DataServices? {
        #if DEBUG
        if arguments.contains("-sampledata") {
            // the widgets show the sample trip too, for screenshots
            let services = SampleData.previewServices()
            BalanceWidgetPublisher.start(services: services)
            return services
        }
        if arguments.contains("-nostore") {
            return nil
        }
        if arguments.contains("-uitesting") {
            return try? DataServices.inMemory()
        }
        #endif
        let services = IntentServices.shared.live()
        if let services {
            // housekeeping waits until the first screen is up and settled, so launch never waits on it
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                removeLeftovers(services)
            }
        }
        return services
    }

    /// Files that outlived what they belong to: photos of deleted groups, and exports and backups already sent.
    /// Then, once, photos from before 1.1 are queued for sync.
    @MainActor
    private static func removeLeftovers(_ services: DataServices) {
        try? PhotoStore.receipts.removeUnreferenced(in: services.environment.context)
        try? PhotoStore.covers.removeUnreferencedCovers(in: services.environment.context)
        let leftovers = [GroupExportFile.defaultDirectory, BackupFileJob.defaultDirectory]
        Task.detached(priority: .utility) {
            for folder in leftovers { try? FileManager.default.removeItem(at: folder) }
        }
        // after the leftovers are gone, so only photos something still shows are sent
        PhotoBackfill.runOnce(tracker: services.environment.tracker)
    }
}

enum LaunchAppearance {
    /// Debug builds accept `-darkmode` to pin the dark appearance, for screenshots on a simulator that ignores the system setting.
    static func scheme(arguments: [String] = ProcessInfo.processInfo.arguments) -> ColorScheme? {
        #if DEBUG
        return arguments.contains("-darkmode") ? .dark : nil
        #else
        return nil
        #endif
    }
}
