import Foundation
import SpltCore

/// Friends sorted into the sections of the Friends tab.
struct FriendSections: Equatable, Sendable {
    var owesYou: [FriendSummary] = []
    var youOwe: [FriendSummary] = []
    /// Owes you in one currency and is owed in another.
    var mixed: [FriendSummary] = []
    var settled: [FriendSummary] = []

    init(summaries: [FriendSummary], leftOut: Set<PersonID> = [], query: String = "") {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        for summary in summaries where !leftOut.contains(summary.id) {
            guard words.allSatisfy({ Self.matches(summary.person.name, $0) }) else { continue }
            switch Self.direction(of: summary.balance) {
            case .owed: owesYou.append(summary)
            case .owes: youOwe.append(summary)
            case .mixed: mixed.append(summary)
            case .settled: settled.append(summary)
            }
        }
    }

    var isEmpty: Bool { owesYou.isEmpty && youOwe.isEmpty && mixed.isEmpty && settled.isEmpty }
    var count: Int { owesYou.count + youOwe.count + mixed.count + settled.count }

    enum Direction: Equatable, Sendable {
        case owed
        case owes
        case mixed
        case settled
    }

    static func direction(of balance: [Money]) -> Direction {
        let owed = balance.contains { $0.isPositive }
        let owes = balance.contains { $0.isNegative }
        switch (owed, owes) {
        case (true, true): return .mixed
        case (true, false): return .owed
        case (false, true): return .owes
        case (false, false): return .settled
        }
    }

    private static func matches(_ name: String, _ word: String) -> Bool {
        name.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
