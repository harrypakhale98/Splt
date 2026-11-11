import CloudKit
import Foundation

/// Everything the CloudKit engine needs from a `CKContainer`. The live version wraps the container;
/// tests use a fake, because a container cannot be created in a build without the entitlement.
@MainActor
protocol CloudKitBackend: AnyObject {
    var containerIdentifier: String { get }
    func userRecordName() async throws -> String
    func engineFactory(for scope: DatabaseScope) -> DatabaseSyncer.EngineFactory
    var shareService: ShareService { get }
    func groupShare(_ share: CKShare, groupName: String) throws -> GroupShare
    func accept(_ metadata: CKShare.Metadata) async throws
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata
}

extension CloudKitBackend {
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        throw SyncError.invalidInvitation
    }
}

@MainActor
final class LiveCloudKitBackend: CloudKitBackend {
    private let container: CKContainer

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    var containerIdentifier: String { container.containerIdentifier ?? "" }

    func userRecordName() async throws -> String {
        try await container.userRecordID().recordName
    }

    func engineFactory(for scope: DatabaseScope) -> DatabaseSyncer.EngineFactory {
        DatabaseSyncer.cloudKitEngine(
            database: scope == .privateDatabase ? container.privateCloudDatabase : container.sharedCloudDatabase
        )
    }

    var shareService: ShareService {
        ShareService(
            privateDatabase: CloudKitShareDatabase(database: container.privateCloudDatabase),
            sharedDatabase: CloudKitShareDatabase(database: container.sharedCloudDatabase)
        )
    }

    func groupShare(_ share: CKShare, groupName: String) -> GroupShare {
        GroupShare(share: share, container: container, groupName: groupName)
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
    }

    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        guard let result = try await container.shareMetadatas(for: [url])[url] else { throw SyncError.invalidInvitation }
        return try result.get()
    }
}
