import Foundation
import SwiftUI

enum LaunchServices {
    /// The data the app runs on. UI tests pass `-uitesting` to start on an empty in-memory store.
    /// Debug builds also accept `-sampledata` to start on the sample trip.
    @MainActor
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DataServices? {
        #if DEBUG
        if arguments.contains("-sampledata") {
            return SampleData.previewServices()
        }
        #endif
        if arguments.contains("-uitesting") {
            return try? DataServices.inMemory()
        }
        return IntentServices.shared.live()
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
