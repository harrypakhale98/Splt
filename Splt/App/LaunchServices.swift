import Foundation

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
        return try? DataServices.live()
    }
}
