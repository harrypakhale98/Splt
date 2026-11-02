import CryptoKit
import Foundation
import SpltCore

/// Reading, naming and fingerprinting a Splitwise export before anything is imported.
enum SplitwiseFile {
    private static let maximumBytes = 20_000_000
    private static let fixedColumns = ["date", "description", "category", "cost", "currency"]

    struct Unreadable: Error {}

    /// The text of the file at `url`. Throws `Unreadable` for a file that is too big or not text.
    static func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try text(from: data)
    }

    static func text(from data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw Unreadable() }
        let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let decoded, !decoded.contains("\u{0}") else { throw Unreadable() }
        return decoded
    }

    /// Line endings and the byte order mark do not change what a file says.
    static func normalized(_ text: String) -> String {
        var result = text
        if result.hasPrefix("\u{FEFF}") { result.removeFirst() }
        return result
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same for the same content, so importing a file twice can be noticed.
    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(normalized(text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "Trip to Spain_2025-03-14_export.csv" becomes "Trip to Spain".
    static func groupName(fromFileName fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")
        if name.lowercased().hasSuffix(" export") { name = String(name.dropLast(" export".count)) }
        let parts = name.split(separator: " ", omittingEmptySubsequences: true)
        if let last = parts.last, isDate(String(last)) { name = parts.dropLast().joined(separator: " ") }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "Splitwise Import") : cleaned
    }

    private static func isDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        return parts.count == 3 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    /// The file with the member columns renamed, so the importer matches them to the chosen people.
    /// `names` maps a Splitwise member name to the name to write. Returns nil if there is no header.
    static func renamingMembers(in text: String, to names: [String: String]) -> String? {
        var rows = CSVText.rows(text)
        guard var header = rows.first else { return nil }
        let lowered = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let indices = fixedColumns.compactMap { lowered.firstIndex(of: $0) }
        guard indices.count == fixedColumns.count, let last = indices.max() else { return nil }
        for column in (last + 1)..<max(header.count, last + 1) {
            let key = CSVText.restored(header[column].trimmingCharacters(in: .whitespacesAndNewlines))
            if let replacement = names[key] { header[column] = replacement }
        }
        rows[0] = header
        return rows.map(CSVText.line).joined(separator: "\n") + "\n"
    }
}

/// Remembers which file made which group, so the same file is never imported twice.
struct SplitwiseImportHistory {
    private static let key = "splitwise.imports"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var entries: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func groupID(forFingerprint fingerprint: String) -> GroupID? {
        entries[fingerprint].flatMap { GroupID(uuidString: $0) }
    }

    func record(fingerprint: String, groupID: GroupID) {
        var all = entries
        all[fingerprint] = groupID.description
        defaults.set(all, forKey: Self.key)
    }
}
