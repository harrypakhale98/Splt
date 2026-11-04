import Foundation
import SwiftUI

enum LaunchServices {
    /// The data the app runs on. UI tests pass `-uitesting` to start on an empty in-memory store.
    /// Debug builds also accept `-sampledata` to start on the sample trip, and `-nostore` to act as if the store failed to open.
    @MainActor
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DataServices? {
        #if DEBUG
        if arguments.contains("-sampledata") {
            return SampleData.previewServices()
        }
        if arguments.contains("-nostore") {
            return nil
        }
        #endif
        if arguments.contains("-uitesting") {
            return try? DataServices.inMemory()
        }
        return IntentServices.shared.live()
    }

    /// Debug builds accept `-tab friends` (or groups, activity, account, search) to start on that tab.
    @MainActor
    static func startTab(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppTab {
        #if DEBUG
        if let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1),
           let tab = AppTab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return .groups
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
