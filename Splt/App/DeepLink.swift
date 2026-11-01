import Foundation

/// A parsed `splt://` address.
///
/// Supported forms: `splt://group/<uuid>`, `splt://friend/<uuid>`, `splt://add-expense`.
enum DeepLink: Hashable, Sendable {
    static let scheme = "splt"

    case group(UUID)
    case friend(UUID)
    case addExpense

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        var parts = [url.host(percentEncoded: false)].compactMap { $0 }.filter { !$0.isEmpty }
        parts += url.pathComponents.filter { $0 != "/" }
        guard let head = parts.first?.lowercased() else { return nil }
        switch (head, parts.count) {
        case ("add-expense", 1):
            self = .addExpense
        case ("group", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .group(id)
        case ("friend", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .friend(id)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .group(let id): URL(string: "\(Self.scheme)://group/\(id.uuidString)")!
        case .friend(let id): URL(string: "\(Self.scheme)://friend/\(id.uuidString)")!
        case .addExpense: URL(string: "\(Self.scheme)://add-expense")!
        }
    }
}
