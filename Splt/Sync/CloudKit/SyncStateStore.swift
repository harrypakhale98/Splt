import Foundation

/// Where sync keeps its own bookkeeping: the CKSyncEngine state for each database and the metadata.
protocol SyncStateStore: Sendable {
    func loadMetadata() -> SyncMetadata
    func saveMetadata(_ metadata: SyncMetadata)
    func loadEngineState(_ scope: DatabaseScope) -> Data?
    func saveEngineState(_ data: Data?, scope: DatabaseScope)
    /// Forgets everything, for example after the iCloud account changed.
    func reset()
}

/// Keeps the state in Application Support so it survives launches.
final class FileSyncStateStore: SyncStateStore {
    private let directory: URL

    init(directory: URL = FileSyncStateStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)
    }

    func loadMetadata() -> SyncMetadata {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(SyncMetadata.self, from: data) else {
            return SyncMetadata()
        }
        return metadata
    }

    func saveMetadata(_ metadata: SyncMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        write(data, to: metadataURL)
    }

    func loadEngineState(_ scope: DatabaseScope) -> Data? {
        try? Data(contentsOf: stateURL(scope))
    }

    func saveEngineState(_ data: Data?, scope: DatabaseScope) {
        guard let data else {
            try? FileManager.default.removeItem(at: stateURL(scope))
            return
        }
        write(data, to: stateURL(scope))
    }

    func reset() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var metadataURL: URL { directory.appending(path: "metadata.json") }

    private func stateURL(_ scope: DatabaseScope) -> URL {
        directory.appending(path: "engine-\(scope.rawValue).json")
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
