enum ExportFormat: String, Hashable, Sendable, CaseIterable {
    case csv
    case json

    var fileExtension: String { rawValue }
}
