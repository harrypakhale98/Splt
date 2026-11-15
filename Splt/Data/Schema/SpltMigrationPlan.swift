import SwiftData

/// Lists every schema version in order and the steps between them.
enum SpltMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpltSchemaV1.self, SpltSchemaV2.self, SpltSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        // version 2 only adds optional fields and a new kind of record
        [
            .lightweight(fromVersion: SpltSchemaV1.self, toVersion: SpltSchemaV2.self),
            // version 3 only adds indexes
            .lightweight(fromVersion: SpltSchemaV2.self, toVersion: SpltSchemaV3.self)
        ]
    }
}
