import Foundation
import SwiftData

/// Gathers everything you can see into a `BackupDocument`.
///
/// That is every group that isn't deleted, archived ones too, with its expenses and payments
/// (deleted ones included, as they stay in history), comments, activity, recurring expenses and
/// item claims, and every person. What sync keeps for itself stays out: system fields, dirty
/// flags, zone names, and the iCloud user a placeholder was claimed by.
@MainActor
struct BackupWriter {
    let context: ModelContext
    var receipts: PhotoStore = .receipts
    var covers: PhotoStore = .covers

    /// A photo the backup can include, by the name its record gives it.
    struct PhotoFile: Sendable {
        var folder: BackupPhoto.Folder
        var name: String
        var url: URL
        var bytes: Int
    }

    /// What the file will hold, without the photos themselves.
    struct Contents: Sendable {
        var document: BackupDocument
        var photos: [PhotoFile]

        var photoBytes: Int { photos.reduce(0) { $0 + $1.bytes } }
    }

    func contents(now: Date, appVersion: String) throws -> Contents {
        let groups = try context.fetch(FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
        ))
        var backupGroups: [BackupGroup] = []
        var photos: [PhotoFile] = []
        for group in groups {
            let gid: UUID? = group.id
            let expenses = try context.fetch(FetchDescriptor<ExpenseRecord>(
                predicate: #Predicate { $0.groupID == gid }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            let payments = try context.fetch(FetchDescriptor<PaymentRecord>(
                predicate: #Predicate { $0.groupID == gid }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            let comments = try context.fetch(FetchDescriptor<CommentRecord>(
                predicate: #Predicate { $0.groupID == gid && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            let activity = try context.fetch(FetchDescriptor<ActivityRecord>(
                predicate: #Predicate { $0.groupID == gid && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            let recurring = try context.fetch(FetchDescriptor<RecurringExpenseRecord>(
                predicate: #Predicate { $0.groupID == gid && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            let claims = try context.fetch(FetchDescriptor<ItemClaimRecord>(
                predicate: #Predicate { $0.groupID == gid && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            backupGroups.append(BackupGroup(
                group: Self.record(group),
                expenses: expenses.map { Self.record($0, keepsDeletion: true) },
                payments: payments.map { Self.record($0, keepsDeletion: true) },
                comments: comments.map { Self.record($0) },
                activity: activity.map { Self.record($0) },
                recurringExpenses: recurring.map { Self.record($0) },
                itemClaims: claims.map { Self.record($0) }
            ))
            if let cover = group.coverFileName, let file = photoFile(cover, in: covers, folder: .covers) {
                photos.append(file)
            }
            photos += expenses.compactMap { expense in
                expense.receiptFileName.flatMap { photoFile($0, in: receipts, folder: .receipts) }
            }
        }

        let people = try context.fetch(FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
        ))
        let me = people.first { $0.kind == .me }
        var seenPhotos: Set<String> = []
        let document = BackupDocument(
            createdAt: now, appVersion: appVersion, meID: me?.id,
            people: people.map(Self.personRecord), groups: backupGroups, photos: []
        )
        return Contents(
            document: document,
            photos: photos.filter { seenPhotos.insert($0.folder.rawValue + "/" + $0.name).inserted }
        )
    }

    private func photoFile(_ name: String, in store: PhotoStore, folder: BackupPhoto.Folder) -> PhotoFile? {
        let url = store.url(for: name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return PhotoFile(folder: folder, name: name, url: url, bytes: size)
    }

    private static func record(_ record: some SyncTracked, keepsDeletion: Bool = false) -> BackupRecord {
        BackupRecord(id: UUID(uuidString: record.recordName) ?? UUID(), deletedAt: keepsDeletion ? record.deletedAt : nil, syncFields: record.syncFields)
    }

    /// A person's fields without the iCloud user who claimed them, and with the contact the
    /// pay with buttons use, which stays on the device in sync but is yours to keep in a backup.
    private static func personRecord(_ person: PersonRecord) -> BackupRecord {
        var fields = person.syncFields
        fields.set("claimedByCloudUserID", nil as String?)
        fields.set("contactHint", person.contactHint)
        return BackupRecord(id: person.id, syncFields: fields)
    }
}

/// Writes a backup file off the main actor.
struct BackupFileJob: Sendable {
    var contents: BackupWriter.Contents
    var includesPhotos: Bool
    var directory: URL

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SpltBackups", isDirectory: true)
    }

    func run() async throws -> URL {
        let job = self
        return try await Task.detached(priority: .userInitiated) { try job.write() }.value
    }

    func write() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(BackupDocument.fileName(for: contents.document.createdAt))
        let photos = includesPhotos ? contents.photos.map { (folder: $0.folder, name: $0.name, file: $0.url) } : []
        try contents.document.write(to: url, photos: photos)
        return url
    }

    /// The size of the file without photos, measured by writing it to memory.
    static func recordBytes(of document: BackupDocument) async -> Int {
        await Task.detached(priority: .utility) { (try? document.encoded().count) ?? 0 }.value
    }
}
