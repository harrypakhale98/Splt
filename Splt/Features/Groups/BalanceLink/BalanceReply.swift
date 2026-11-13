import CryptoKit
import Foundation
import SpltCore

/// What a friend without the app sends back from a balance link: one expense or one payment for the
/// person who shared the link to check and add.
///
/// The web page at `docs/b/` writes it into a link the same way the app writes a balance link: compact
/// JSON, raw deflate, base64url, after `#r.` on the page or after `d=` in `splt://reply`. People are the
/// link's own member numbers, which only mean something next to the reply code the sharing phone
/// remembers in `BalanceReplyStore`. Anyone can write one, so nothing is added without a review.
///
/// The JSON keys:
/// - `v` version, `r` the reply code from the balance link, `g` the group's name as the link showed it
/// - `a` the member who sent it, `t` when, in seconds since 1970
/// - `u` names for the members it mentions, `[[member, name]]`, so the page can show it without the
///   balance link. The app goes by the numbers and shows its own names.
/// - `c` currency `[code, minor unit digits]`, `m` the amount in minor units, always positive
/// - `k` `"e"` for an expense: `n` title, `d` day as `yyyy-MM-dd`, `p` who paid, `w` who shares it equally
/// - `k` `"p"` for a payment: `f` who paid, `o` who was paid
struct BalanceReply: Equatable, Sendable {
    static let version = 1
    /// The longest reply the app reads, in characters after the `#` or `d=`.
    static let maxFragmentLength = 4_000
    static let titleLimit = 60
    /// A trillion in the currency's main unit, the same ceiling the app's amount fields use.
    static let maxAmountMajor: Int64 = 1_000_000_000_000

    enum Kind: Equatable, Sendable {
        case expense(title: String, day: String, payer: Int, participants: [Int])
        case payment(from: Int, to: Int)
    }

    enum FormatError: Error, Equatable {
        case tooLong
        case unreadable
        case unsupportedVersion(Int)
        case invalid(String)
    }

    var token: String
    var groupName: String
    var author: Int
    var names: [Int: String]
    var currencyCode: String
    var digits: Int
    var amount: Int64
    var kind: Kind
    /// Whole seconds, so a decoded reply equals the one encoded.
    var createdAt: Date

    /// Every member number the reply uses.
    var people: Set<Int> {
        switch kind {
        case .expense(_, _, let payer, let participants): Set([author, payer] + participants)
        case .payment(let from, let to): [author, from, to]
        }
    }

    var money: Money { Money(minorUnits: amount, currencyCode: currencyCode) }
}

// MARK: Links

extension BalanceReply {
    /// Reads the text after `#r.` or `d=`.
    init(fragment: String) throws {
        guard fragment.count <= Self.maxFragmentLength else { throw FormatError.tooLong }
        guard let packed = BalanceLink.data(base64URL: fragment),
              let json = try? BalanceLink.inflate(packed)
        else { throw FormatError.unreadable }
        do {
            self = try JSONDecoder().decode(BalanceReply.self, from: json)
        } catch let error as FormatError {
            throw error
        } catch {
            throw FormatError.unreadable
        }
    }

    /// The text that goes after `#r.` or `d=`.
    func fragment() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return BalanceLink.base64URL(try BalanceLink.deflate(try encoder.encode(self)))
    }

    /// Names one reply, so the same one opened twice is only added once.
    static func id(ofFragment fragment: String) -> String {
        SHA256.hash(data: Data(fragment.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The calendar day the reply names, at noon so no time zone moves it to another day.
    func date(calendar: Calendar = .current) -> Date? {
        guard case .expense(_, let day, _, _) = kind else { return nil }
        return Self.date(day, calendar: calendar)
    }

    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard day.count == 10, parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
        return date
    }
}

// MARK: JSON

extension BalanceReply: Codable {
    private enum Key: String, CodingKey {
        case v, r, g, a, t, u, c, m, k, n, d, p, w, f, o
    }

    func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: Key.self)
        try root.encode(Self.version, forKey: .v)
        try root.encode(token, forKey: .r)
        try root.encode(groupName, forKey: .g)
        try root.encode(author, forKey: .a)
        try root.encode(Int64(createdAt.timeIntervalSince1970), forKey: .t)
        var nameList = root.nestedUnkeyedContainer(forKey: .u)
        for (person, name) in names.sorted(by: { $0.key < $1.key }) {
            var pair = nameList.nestedUnkeyedContainer()
            try pair.encode(person)
            try pair.encode(name)
        }
        var currency = root.nestedUnkeyedContainer(forKey: .c)
        try currency.encode(currencyCode)
        try currency.encode(digits)
        try root.encode(amount, forKey: .m)
        switch kind {
        case .expense(let title, let day, let payer, let participants):
            try root.encode("e", forKey: .k)
            try root.encode(title, forKey: .n)
            try root.encode(day, forKey: .d)
            try root.encode(payer, forKey: .p)
            try root.encode(participants, forKey: .w)
        case .payment(let from, let to):
            try root.encode("p", forKey: .k)
            try root.encode(from, forKey: .f)
            try root.encode(to, forKey: .o)
        }
    }

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: Key.self)
        let version = try root.decode(Int.self, forKey: .v)
        guard version == Self.version else { throw FormatError.unsupportedVersion(version) }
        token = try root.decode(String.self, forKey: .r)
        groupName = Self.flat(try root.decode(String.self, forKey: .g))
        author = try root.decode(Int.self, forKey: .a)
        createdAt = Date(timeIntervalSince1970: TimeInterval(try root.decode(Int64.self, forKey: .t)))
        names = [:]
        if root.contains(.u) {
            var nameList = try root.nestedUnkeyedContainer(forKey: .u)
            while !nameList.isAtEnd {
                var pair = try nameList.nestedUnkeyedContainer()
                let person = try pair.decode(Int.self)
                names[person] = Self.flat(try pair.decode(String.self))
            }
        }
        var currency = try root.nestedUnkeyedContainer(forKey: .c)
        currencyCode = try currency.decode(String.self)
        digits = try currency.decode(Int.self)
        amount = try root.decode(Int64.self, forKey: .m)
        switch try root.decode(String.self, forKey: .k) {
        case "e":
            kind = .expense(
                title: Self.flat(try root.decode(String.self, forKey: .n)),
                day: try root.decode(String.self, forKey: .d),
                payer: try root.decode(Int.self, forKey: .p),
                participants: try root.decode([Int].self, forKey: .w)
            )
        case "p":
            kind = .payment(from: try root.decode(Int.self, forKey: .f), to: try root.decode(Int.self, forKey: .o))
        default:
            throw FormatError.invalid("kind")
        }
        try validate()
    }

    /// Checks everything that can be checked without the group, so a reader never has to guess.
    func validate() throws {
        guard BalanceSnapshot.isReplyToken(token) else { throw FormatError.invalid("token") }
        guard (1...200).contains(groupName.count) else { throw FormatError.invalid("group") }
        let members = 0..<1_000
        guard people.allSatisfy(members.contains) else { throw FormatError.invalid("person") }
        guard names.keys.allSatisfy(members.contains), names.values.allSatisfy({ (1...100).contains($0.count) })
        else { throw FormatError.invalid("names") }
        guard currencyCode.count == 3, currencyCode.allSatisfy({ $0.isASCII && $0.isUppercase }),
              Locale.Currency.isoCurrencies.contains(Locale.Currency(currencyCode)),
              digits == SpltCore.Currency.minorUnitExponent(for: currencyCode)
        else { throw FormatError.invalid("currency") }
        var ceiling = Self.maxAmountMajor
        for _ in 0..<digits { ceiling = ceiling.multipliedReportingOverflow(by: 10).partialValue }
        guard amount > 0, amount <= ceiling else { throw FormatError.invalid("amount") }
        switch kind {
        case .expense(let title, let day, _, let participants):
            guard (1...200).contains(title.count) else { throw FormatError.invalid("title") }
            guard Self.date(day, calendar: Calendar(identifier: .gregorian)) != nil else { throw FormatError.invalid("day") }
            guard !participants.isEmpty, Set(participants).count == participants.count else {
                throw FormatError.invalid("participants")
            }
        case .payment(let from, let to):
            guard from != to else { throw FormatError.invalid("payment") }
        }
    }

    /// On one line and trimmed, so a crafted name can't break a row.
    private static func flat(_ text: String) -> String {
        text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
