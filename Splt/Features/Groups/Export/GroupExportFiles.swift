import Foundation

/// The files a person can share from the group settings.
struct GroupExportFiles: Equatable, Sendable {
    var csv: URL
    var pdf: URL

    /// Writes both files to a fresh temporary folder named after the group.
    static func write(csv: Data, pdf: Data, groupName: String) throws -> GroupExportFiles {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpltExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = fileName(for: groupName)
        let csvURL = folder.appendingPathComponent("\(base).csv")
        let pdfURL = folder.appendingPathComponent("\(base).pdf")
        try csv.write(to: csvURL, options: .atomic)
        try pdf.write(to: pdfURL, options: .atomic)
        return GroupExportFiles(csv: csvURL, pdf: pdfURL)
    }

    /// A name that is safe on every file system.
    static func fileName(for groupName: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = groupName.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Group" : cleaned
    }
}
