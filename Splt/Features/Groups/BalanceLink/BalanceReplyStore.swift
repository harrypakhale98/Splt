import Foundation
import SpltCore

/// What each reply code in a balance link stands for, kept on the phone that shared the link.
///
/// A link numbers people instead of naming their ids, so a reply means something only next to the
/// list it was numbered from. That list stays here and never leaves the device. It lives in
/// `UserDefaults`, not the synced store, so a reply is checked on the phone that sent the link.
struct BalanceReplyStore {
    struct Entry: Codable, Equatable, Sendable {
        var token: String
        var group: UUID
        /// The people in the link's own order.
        var people: [UUID]
        var createdAt: Date
        /// Replies already added, by `BalanceReply.id(ofFragment:)`.
        var added: [String] = []
    }

    /// How long a link can still be answered.
    static let lifetime: TimeInterval = 180 * 24 * 60 * 60
    static let maxEntries = 200
    /// Replies remembered per link, enough for a long trip.
    static let maxAdded = 500
    private static let key = "balanceLink.replies"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// A new reply code.
    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return BalanceLink.base64URL(Data(bytes))
    }

    /// The code for a link to this group numbered this way. A link shared again unchanged keeps its
    /// code, so opening the share sheet over and over doesn't fill the list.
    @discardableResult
    func token(for group: GroupID, people: [PersonID]) -> String {
        var entries = live()
        let ids = people.map(\.rawValue)
        if let index = entries.firstIndex(where: { $0.group == group.rawValue && $0.people == ids }) {
            entries[index].createdAt = now()
            save(entries)
            return entries[index].token
        }
        let token = Self.makeToken()
        entries.append(Entry(token: token, group: group.rawValue, people: ids, createdAt: now()))
        save(entries)
        return token
    }

    func entry(for token: String) -> Entry? {
        live().first { $0.token == token }
    }

    func wasAdded(_ replyID: String, token: String) -> Bool {
        entry(for: token)?.added.contains(replyID) == true
    }

    func markAdded(_ replyID: String, token: String) {
        var entries = live()
        guard let index = entries.firstIndex(where: { $0.token == token }) else { return }
        guard !entries[index].added.contains(replyID) else { return }
        entries[index].added = Array((entries[index].added + [replyID]).suffix(Self.maxAdded))
        save(entries)
    }

    /// Entries still young enough to answer.
    private func live() -> [Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        let oldest = now().addingTimeInterval(-Self.lifetime)
        return entries.filter { $0.createdAt >= oldest }
    }

    private func save(_ entries: [Entry]) {
        let kept = entries.sorted { $0.createdAt < $1.createdAt }.suffix(Self.maxEntries)
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
