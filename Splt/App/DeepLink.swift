import Foundation

/// A parsed `splt://` address.
///
/// Supported forms: `splt://group/<uuid>`, `splt://friend/<uuid>`, `splt://settle/<friend uuid>`,
/// `splt://add-expense`, `splt://invite?name=<name>&id=<uuid>`,
/// `splt://join?share=<iCloud invite link>&as=<person uuid>` and `splt://reply?d=<balance reply>`.
enum DeepLink: Hashable, Sendable {
    static let scheme = "splt"

    case group(UUID)
    case friend(UUID)
    /// Opens a friend with the settle up sheet ready.
    case settle(UUID)
    case addExpense
    /// Opens the Activity tab.
    case activity
    /// Opens a payment from To Split in the expense form, from a notification or Siri.
    case payment(UUID)
    case invite(FriendInvite)
    /// Joins a group as the person the invite was made for.
    case join(JoinInvite)
    /// An expense or a payment a friend sent back from a balance link, still packed. It is read in the
    /// review sheet, so a broken one says so there instead of doing nothing.
    case reply(String)

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
        case ("settle", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .settle(id)
        case ("activity", 1):
            self = .activity
        case ("payment", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .payment(id)
        case ("invite", 1):
            guard let invite = FriendInvite(url: url) else { return nil }
            self = .invite(invite)
        case ("join", 1):
            guard let invite = JoinInvite(url: url) else { return nil }
            self = .join(invite)
        case ("reply", 1):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let packed = items.first(where: { $0.name == "d" })?.value, !packed.isEmpty,
                  packed.count <= BalanceReply.maxFragmentLength
            else { return nil }
            self = .reply(packed)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .group(let id): URL(string: "\(Self.scheme)://group/\(id.uuidString)")!
        case .friend(let id): URL(string: "\(Self.scheme)://friend/\(id.uuidString)")!
        case .settle(let id): URL(string: "\(Self.scheme)://settle/\(id.uuidString)")!
        case .addExpense: URL(string: "\(Self.scheme)://add-expense")!
        case .activity: URL(string: "\(Self.scheme)://activity")!
        case .payment(let id): URL(string: "\(Self.scheme)://payment/\(id.uuidString)")!
        case .invite(let invite): invite.url
        case .join(let invite): invite.url
        case .reply(let packed): URL(string: "\(Self.scheme)://reply?d=\(packed)")!
        }
    }
}
