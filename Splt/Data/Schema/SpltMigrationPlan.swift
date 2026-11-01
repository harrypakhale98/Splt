import SwiftData

/// Lists every schema version in order and the steps between them.
/// Version 1 is the first release, so there is nothing to migrate yet.
enum SpltMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpltSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
