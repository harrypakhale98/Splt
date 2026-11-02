import Foundation

/// The files a person can share from the group settings.
enum GroupExportKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case csv
    case pdf
    case json

    var id: String { rawValue }

    /// The repository format behind it. The PDF is drawn from a report instead.
    var format: ExportFormat? {
        switch self {
        case .csv: .csv
        case .json: .json
        case .pdf: nil
        }
    }

    var fileExtension: String { format?.fileExtension ?? "pdf" }
}

/// Where one export stands.
enum GroupExportState: Equatable, Sendable {
    case idle
    case preparing
    case ready(URL)
    case failed(String)
}

/// Everything needed to write one export, gathered on the main actor so the slow part can run elsewhere.
struct GroupExportJob: Sendable {
    enum Content: Sendable {
        case data(Data)
        case pdf(GroupReport, Locale)
    }

    var content: Content
    var groupName: String
    var fileExtension: String
    var directory: URL

    /// Draws and writes the file off the main actor.
    func run() async throws -> URL {
        let job = self
        return try await Task.detached(priority: .userInitiated) { try job.write() }.value
    }

    private func write() throws -> URL {
        let data: Data
        switch content {
        case .data(let value): data = value
        case .pdf(let report, let locale): data = GroupPDFRenderer.data(for: report, locale: locale)
        }
        return try GroupExportFile.write(data, groupName: groupName, fileExtension: fileExtension, in: directory)
    }
}

enum GroupExportFile {
    /// A fresh folder under the temporary directory for each export.
    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SpltExports", isDirectory: true)
    }

    /// Writes the data to a new folder inside `directory`, named after the group.
    static func write(_ data: Data, groupName: String, fileExtension: String, in directory: URL) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(fileName(for: groupName)).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A name that is safe on every file system.
    static func fileName(for groupName: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = groupName.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Group" : cleaned
    }
}
