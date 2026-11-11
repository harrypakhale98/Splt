import Foundation
import UniformTypeIdentifiers

/// A whole backup: everything you can see in Splt, as one JSON file with the photos inside it.
///
/// Each record is kept as the domain fields sync already uploads, so the file holds exactly the
/// data a group carries and nothing about how it syncs: no system fields, dirty flags, zones or
/// iCloud user names. Blobs such as splits and edit history stay in their stored JSON, base64
/// encoded, so they come back byte for byte. Dates are kept as stored, to the sub-millisecond.
///
/// The file is read with the same suspicion as a record from a shared group: see `validate()`.
struct BackupDocument: Codable, Sendable {
    /// Names the file as a Splt backup, so another JSON file is not mistaken for one.
    static let formatName = "splt.backup"
    /// Raise when the file changes in a way an older version can't read. Older files must keep restoring.
    static let currentVersion = 1
    static let fileExtension = "spltbackup"

    var format: String
    var formatVersion: Int
    var createdAt: Date
    /// The version of Splt that made the file, for support.
    var appVersion: String
    /// The person who was "me" on the device that made the backup.
    var meID: UUID?
    /// Everyone you could see: group members, people in old expenses and friends without a group.
    var people: [BackupRecord]
    var groups: [BackupGroup]
    /// Receipt and cover photos, when the backup includes them. Kept last in the file so it can be written one photo at a time.
    var photos: [BackupPhoto]

    init(createdAt: Date, appVersion: String, meID: UUID?, people: [BackupRecord], groups: [BackupGroup], photos: [BackupPhoto]) {
        self.format = Self.formatName
        self.formatVersion = Self.currentVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.meID = meID
        self.people = people
        self.groups = groups
        self.photos = photos
    }
}

/// One group and everything in it.
struct BackupGroup: Codable, Sendable {
    var group: BackupRecord
    var expenses: [BackupRecord]
    var payments: [BackupRecord]
    var comments: [BackupRecord]
    var activity: [BackupRecord]
    var recurringExpenses: [BackupRecord]
    var itemClaims: [BackupRecord]

    /// The records of one kind, for code that treats them alike.
    func records(of type: SyncRecordType) -> [BackupRecord] {
        switch type {
        case .group: [group]
        case .expense: expenses
        case .payment: payments
        case .comment: comments
        case .activity: activity
        case .recurringExpense: recurringExpenses
        case .itemClaim: itemClaims
        case .person: []
        }
    }

    /// The kinds of record a group holds, in the order a restore adds them.
    static let recordTypes: [SyncRecordType] = [.group, .recurringExpense, .expense, .payment, .comment, .activity, .itemClaim]

    var recordCount: Int {
        Self.recordTypes.reduce(0) { $0 + records(of: $1).count }
    }
}

/// One record: its id, its soft delete for expenses and payments, and its domain fields.
struct BackupRecord: Codable, Hashable, Sendable {
    var id: UUID
    /// Set on a deleted expense or payment, which stays in history and can be restored.
    var deletedAt: Date?
    var fields: [String: BackupValue]

    init(id: UUID, deletedAt: Date? = nil, fields: [String: BackupValue]) {
        self.id = id
        self.deletedAt = deletedAt
        self.fields = fields
    }

    init(id: UUID, deletedAt: Date? = nil, syncFields: SyncFields) {
        self.init(id: id, deletedAt: deletedAt, fields: syncFields.values.mapValues { BackupValue($0) })
    }

    var syncFields: SyncFields {
        SyncFields(fields.mapValues(\.syncValue))
    }
}

/// A field value, written as an object with one key that names its type, such as `{"string": "Dinner"}`.
enum BackupValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case data(Data)

    init(_ value: SyncValue) {
        switch value {
        case .string(let value): self = .string(value)
        case .int(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .date(let value): self = .date(value)
        case .data(let value): self = .data(value)
        }
    }

    var syncValue: SyncValue {
        switch self {
        case .string(let value): .string(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .date(let value): .date(value)
        case .data(let value): .data(value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case string, int, double, date, data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "One type per value"))
        }
        switch key {
        case .string: self = .string(try container.decode(String.self, forKey: key))
        case .int: self = .int(try container.decode(Int64.self, forKey: key))
        case .double: self = .double(try container.decode(Double.self, forKey: key))
        case .date: self = .date(try container.decode(Date.self, forKey: key))
        case .data: self = .data(try container.decode(Data.self, forKey: key))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value): try container.encode(value, forKey: .string)
        case .int(let value): try container.encode(value, forKey: .int)
        case .double(let value): try container.encode(value, forKey: .double)
        case .date(let value): try container.encode(value, forKey: .date)
        case .data(let value): try container.encode(value, forKey: .data)
        }
    }
}

/// A receipt or cover photo, under the name its record gave it on the device that made the backup.
/// The name is only used to find the photo again: a restore always saves it under a new name of its own.
struct BackupPhoto: Codable, Hashable, Sendable {
    enum Folder: String, Codable, Hashable, Sendable {
        case receipts
        case covers
    }

    var folder: Folder
    var name: String
    var data: Data

    var key: String { folder.rawValue + "/" + name }
}

/// Why a file can't be restored. Nothing has changed when one is thrown.
enum BackupError: Error, Equatable, Sendable {
    /// Not a Splt backup, or cut short or damaged.
    case unreadable
    /// Made by a newer version of Splt.
    case newerVersion
    /// Larger than a backup can be.
    case tooLarge
    /// Read, but something in it is outside what Splt can hold, so the file was made or changed elsewhere.
    case invalid(String)
    /// The restore could not be saved.
    case saveFailed

    var message: String {
        switch self {
        case .unreadable:
            String(localized: "This file isn't a Splt backup, or it is damaged. Nothing was changed.")
        case .newerVersion:
            String(localized: "This backup was made by a newer version of Splt. Update Splt, then try again. Nothing was changed.")
        case .tooLarge:
            String(localized: "This file is too large to be a Splt backup. Nothing was changed.")
        case .invalid:
            String(localized: "Something in this backup can't be restored, so nothing was changed.")
        case .saveFailed:
            String(localized: "Splt couldn't save the restored data. Nothing was changed. Try again.")
        }
    }
}

extension UTType {
    /// A Splt backup file, declared in the app's Info.plist.
    static let spltBackup = UTType(exportedAs: "com.harrypakhale.splt.backup", conformingTo: .data)
}

// MARK: Reading and writing

extension BackupDocument {
    /// Larger files are refused before they are read, because the whole file is read into memory.
    static let maximumFileBytes = 500_000_000
    static let maximumGroups = 5_000
    static let maximumPeople = 50_000
    /// Records of every kind in all groups together.
    static let maximumRecords = 1_000_000
    static let maximumPhotos = 50_000
    /// Text in one field. The app keeps far less, see `RecordLimits`.
    static let maximumTextBytes = RecordLimits.text * 4
    /// One blob, such as a split. A CloudKit record holds about a megabyte, so a larger one could never sync.
    static let maximumBlobBytes = 1_000_000

    private struct Header: Decodable {
        var format: String
        var formatVersion: Int
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // sorted keys put `photos` last, which lets `write` add the photos one at a time
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    /// Reads and checks a backup. Throws a `BackupError` for anything that can't be restored.
    static func decode(_ data: Data) throws -> BackupDocument {
        guard data.count <= maximumFileBytes else { throw BackupError.tooLarge }
        let decoder = makeDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName,
              header.formatVersion >= 1 else { throw BackupError.unreadable }
        guard header.formatVersion <= currentVersion else { throw BackupError.newerVersion }
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else { throw BackupError.unreadable }
        try document.validate()
        return document
    }

    /// Reads the backup at `url`, which may be outside the app's own folders.
    static func read(_ url: URL) throws -> BackupDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileBytes {
            throw BackupError.tooLarge
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw BackupError.unreadable }
        return try decode(data)
    }

    /// The whole file in memory. `write(to:photos:)` keeps memory low for large backups.
    func encoded() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    /// Writes the file, reading and adding each photo only when it is its turn, so a backup with
    /// many photos never holds them all in memory. `photos` replaces the document's own photos.
    func write(to url: URL, photos: [(folder: BackupPhoto.Folder, name: String, file: URL)]) throws {
        var head = self
        head.photos = []
        let encoder = Self.makeEncoder()
        var data = try encoder.encode(head)
        let ending = Data(#""photos":[]}"#.utf8)
        guard data.count >= ending.count, data.suffix(ending.count) == ending else {
            throw BackupError.unreadable
        }
        data.removeLast(2)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        var first = true
        for photo in photos {
            guard let content = try? Data(contentsOf: photo.file) else { continue }
            let entry = try encoder.encode(BackupPhoto(folder: photo.folder, name: photo.name, data: content))
            try handle.write(contentsOf: first ? entry : Data(",".utf8) + entry)
            first = false
        }
        try handle.write(contentsOf: Data("]}".utf8))
    }

    /// A file name such as "Splt Backup 2026-11-10.spltbackup", in the device's time zone.
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "Splt Backup \(day).\(fileExtension)"
    }
}

// MARK: Checks

extension BackupDocument {
    /// The file can be made by hand, so it is held to what the app itself could have saved:
    /// counts and sizes within limits, ids unique, every record in the group it is listed under,
    /// and amounts no larger than sync accepts from a shared group.
    func validate() throws {
        guard groups.count <= Self.maximumGroups, people.count <= Self.maximumPeople,
              photos.count <= Self.maximumPhotos else { throw BackupError.invalid("too many items") }
        guard groups.reduce(0, { $0 + $1.recordCount }) <= Self.maximumRecords else {
            throw BackupError.invalid("too many records")
        }
        guard photos.allSatisfy({ $0.data.count <= PhotoStore.maximumIncomingBytes }) else {
            throw BackupError.invalid("photo too large")
        }

        var seen: [SyncRecordType: Set<UUID>] = [:]
        func unique(_ id: UUID, _ type: SyncRecordType) throws {
            guard seen[type, default: []].insert(id).inserted else { throw BackupError.invalid("\(type) \(id) twice") }
        }

        for person in people {
            try unique(person.id, .person)
            try Self.check(person, type: .person)
        }
        for group in groups {
            for type in BackupGroup.recordTypes {
                for record in group.records(of: type) {
                    try unique(record.id, type)
                    try Self.check(record, type: type)
                    if type != .group, record.fields["groupID"] != .string(group.group.id.uuidString) {
                        throw BackupError.invalid("\(type) \(record.id) outside its group")
                    }
                }
            }
        }
    }

    private static func check(_ record: BackupRecord, type: SyncRecordType) throws {
        for value in record.fields.values {
            switch value {
            case .string(let text) where text.utf8.count > maximumTextBytes:
                throw BackupError.invalid("text too long in \(type) \(record.id)")
            case .data(let data) where data.count > maximumBlobBytes:
                throw BackupError.invalid("field too large in \(type) \(record.id)")
            case .double(let number) where !number.isFinite:
                throw BackupError.invalid("not a number in \(type) \(record.id)")
            default:
                continue
            }
        }
        let payload = SyncPayload(recordType: type, recordName: record.id.uuidString, modifiedAt: .distantPast, fields: record.syncFields)
        guard payload.amountsAreEnterable else { throw BackupError.invalid("amount too large in \(type) \(record.id)") }
    }
}
