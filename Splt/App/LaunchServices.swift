import Foundation
import SwiftUI

enum LaunchServices {
    /// The data the app runs on. Debug builds accept `-uitesting` to start on an empty in-memory store for
    /// UI tests, `-sampledata` to start on the sample trip, and `-nostore` to act as if the store failed to open.
    @MainActor
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DataServices? {
        #if DEBUG
        if arguments.contains("-sampledata") {
            return SampleData.previewServices()
        }
        if arguments.contains("-nostore") {
            return nil
        }
        if arguments.contains("-uitesting") {
            return try? DataServices.inMemory()
        }
        #endif
        let services = IntentServices.shared.live()
        if let services { removeLeftovers(services) }
        return services
    }

    /// Files that outlived what they belong to: photos of deleted groups, and exports already sent.
    @MainActor
    private static func removeLeftovers(_ services: DataServices) {
        try? ReceiptStore.standard.removeUnreferenced(in: services.environment.context)
        try? FileManager.default.removeItem(at: GroupExportFile.defaultDirectory)
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
