import Foundation
import SwiftData

enum ModelContainerFactory {
    /// The container the app runs on.
    ///
    /// Pass `inMemory` for tests and previews, or `url` to keep the store somewhere specific.
    /// SwiftData's own CloudKit mirroring is switched off: sync is done by the sync engine
    /// through the change tracker, not by SwiftData.
    static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SpltSchemaV2.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: SpltMigrationPlan.self, configurations: [configuration])
    }
}
