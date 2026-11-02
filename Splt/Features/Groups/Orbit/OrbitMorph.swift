import CoreGraphics
import Foundation

/// How the arcs on the ring change when the group switches between direct debts and the fewest
/// payments. Arcs that stay move and resize, arcs that go slide into one that stays, and new arcs
/// grow out of one that went.
struct MorphPair: Identifiable, Equatable {
    enum Kind: Equatable {
        case stay
        /// An old arc folds into a new one and disappears.
        case merge
        /// A new arc grows out of an old one.
        case split
        case appear
        case vanish
    }

    var kind: Kind
    var start: OrbitTransfer?
    var end: OrbitTransfer?

    var id: String {
        switch kind {
        case .stay: "stay:\(end?.id ?? "")"
        case .merge: "merge:\(start?.id ?? "")"
        case .split: "split:\(end?.id ?? "")"
        case .appear: "appear:\(end?.id ?? "")"
        case .vanish: "vanish:\(start?.id ?? "")"
        }
    }
}

enum OrbitMorph {
    /// Every old arc is the start of exactly one pair and every new arc is the end of exactly one.
    static func pairs(from old: [OrbitTransfer], to new: [OrbitTransfer]) -> [MorphPair] {
        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var pairs: [MorphPair] = []
        for transfer in old where newIDs.contains(transfer.id) {
            pairs.append(MorphPair(kind: .stay, start: transfer, end: newByID[transfer.id]))
        }
        let leaving = old.filter { !newIDs.contains($0.id) }
        let arriving = new.filter { !oldIDs.contains($0.id) }

        if arriving.isEmpty {
            pairs += leaving.map { MorphPair(kind: .vanish, start: $0, end: nil) }
        } else if leaving.isEmpty {
            pairs += arriving.map { MorphPair(kind: .appear, start: nil, end: $0) }
        } else {
            pairs += leaving.compactMap { arc in
                best(for: arc, in: arriving).map { MorphPair(kind: .merge, start: arc, end: $0) }
            }
            pairs += arriving.compactMap { arc in
                best(for: arc, in: leaving).map { MorphPair(kind: .split, start: $0, end: arc) }
            }
        }
        return pairs
    }

    /// The candidate that shares the most people with `arc`, then the biggest, then the first by id.
    private static func best(for arc: OrbitTransfer, in candidates: [OrbitTransfer]) -> OrbitTransfer? {
        candidates.max { lhs, rhs in
            let left = shared(arc, lhs), right = shared(arc, rhs)
            if left != right { return left < right }
            if lhs.amount.minorUnits != rhs.amount.minorUnits { return lhs.amount.minorUnits < rhs.amount.minorUnits }
            return lhs.id > rhs.id
        }
    }

    private static func shared(_ a: OrbitTransfer, _ b: OrbitTransfer) -> Int {
        Set([a.debtor, a.creditor]).intersection([b.debtor, b.creditor]).count
    }

    /// The two shapes a pair slides between, with the widths its kind calls for: arcs that are going
    /// shrink to nothing and arcs that are arriving grow from nothing.
    static func geometry(for pair: MorphPair, in scene: OrbitScene, target: OrbitScene) -> (from: ArcGeometry, to: ArcGeometry)? {
        let first = pair.start.flatMap { scene.arc(for: $0) }
        let last = pair.end.flatMap { target.arc(for: $0) }
        switch pair.kind {
        case .stay:
            guard let first, let last else { return nil }
            return (first, last)
        case .merge:
            guard let first, var last else { return nil }
            last.width = 0
            return (first, last)
        case .split:
            guard var first, let last else { return nil }
            first.width = 0
            return (first, last)
        case .appear:
            guard let last else { return nil }
            var start = last
            start.width = 0
            return (start, last)
        case .vanish:
            guard let first else { return nil }
            var end = first
            end.width = 0
            return (first, end)
        }
    }
}
