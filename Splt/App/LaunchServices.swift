import Foundation

enum LaunchServices {
    /// The data the app runs on. UI tests pass `-uitesting` to start on an empty in-memory store.
    @MainActor
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> DataServices? {
        if arguments.contains("-uitesting") {
            return try? DataServices.inMemory()
        }
        return try? DataServices.live()
    }
}
