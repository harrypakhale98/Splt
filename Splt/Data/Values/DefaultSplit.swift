import Foundation
import SpltCore

/// How a new expense in a group is split unless it is changed. Stored as JSON on the group;
/// a group without one splits equally between everyone, as before.
struct DefaultSplit: Codable, Hashable, Sendable {
    enum Method: String, Codable, CaseIterable, Sendable {
        case equal
        case percentages
        case shares

        /// The weight of someone the split does not mention yet, such as a member who joined later.
        /// They are in an equal split and get one share, but no percentage, so the others still add up.
        var newcomerWeight: Int64 {
            switch self {
            case .equal: 1
            case .percentages: 0
            case .shares: 100
            }
        }
    }

    var method: Method
    /// Per person. Equal: 1 for in and 0 for left out. Percentages: hundredths of a percent, so
    /// 10_000 is everything. Shares: hundredths of a share, so 150 is one and a half.
    var weights: [PersonID: Int64]

    init(method: Method, weights: [PersonID: Int64] = [:]) {
        self.method = method
        self.weights = weights
    }

    /// What a new expense starts with, for the group's members today.
    struct Resolved: Equatable, Sendable {
        var method: Method
        /// The members in the split, in the order given.
        var participants: [PersonID]
        /// The weight of each participant, in the units of `DefaultSplit.weights`.
        var weights: [PersonID: Int64]
    }

    /// The split for these members. People who left are dropped and people it does not know get the
    /// method's `newcomerWeight`. Nil when nothing usable is left: nobody in it, or percentages that
    /// no longer add up to 100, as when someone with a share has left. The expense is then split equally.
    func resolved(for members: [PersonID]) -> Resolved? {
        var kept: [PersonID: Int64] = [:]
        var participants: [PersonID] = []
        for member in members where kept[member] == nil {
            let weight = weights[member] ?? method.newcomerWeight
            guard weight > 0 else { continue }
            kept[member] = weight
            participants.append(member)
        }
        guard !participants.isEmpty else { return nil }
        if method == .percentages, kept.values.reduce(0, +) != 10_000 { return nil }
        return Resolved(method: method, participants: participants, weights: kept)
    }

    /// True when it splits equally between all these members, which is what a group without one does.
    func isPlainEqual(for members: [PersonID]) -> Bool {
        guard let resolved = resolved(for: members) else { return false }
        return resolved.method == .equal && resolved.participants.count == Set(members).count
    }
}
