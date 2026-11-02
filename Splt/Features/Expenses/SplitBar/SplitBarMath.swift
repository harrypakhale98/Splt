import SpltCore

/// A position on the bar where a divider clicks into place.
struct SplitBarDetent: Hashable, Sendable {
    /// Strongest first: the split everyone would get equally, a whole currency amount, a round percentage.
    enum Kind: Int, Comparable, Sendable {
        case equal
        case wholeAmount
        case percent

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var position: Int64
    var kind: Kind
}

/// What a drag did to the bar.
struct SplitBarDrag: Equatable, Sendable {
    var weights: [Int64]
    /// The detent the divider is resting on, if it snapped to one.
    var snappedTo: SplitBarDetent.Kind?
    var didChange: Bool
}

/// The arithmetic behind the Split Bar, kept free of any view so it can be tested on its own.
///
/// The bar lives in a "space" of whole numbers: basis points (a scale of 10,000) for percentages,
/// the expense's minor units for exact amounts, or the sum of the shares. Segment weights add up
/// to the scale, a divider sits at the running total of the weights before it, and dragging a
/// divider only moves money between its two neighbours, so the total never changes.
enum SplitBarMath {
    static let basisPoints: Int64 = 10_000

    /// The smallest a segment may get, so every person keeps a visible, grabbable piece.
    static func minimumSegment(count: Int, scale: Int64) -> Int64 {
        guard count > 0, scale > 0 else { return 0 }
        let wanted = max(scale * 3 / 100, 1)
        let room = scale / Int64(count * 2)
        return max(min(wanted, room), min(1, scale / Int64(count)))
    }

    /// Equal parts of `scale` for `count` people. The odd units go to the first segments.
    static func equalWeights(count: Int, scale: Int64) -> [Int64] {
        guard count > 0 else { return [] }
        let base = scale / Int64(count)
        let extra = Int(scale - base * Int64(count))
        return (0..<count).map { base + ($0 < extra ? 1 : 0) }
    }

    /// Resizes weights to a new scale in proportion, adding up exactly. Zero weights give an equal split.
    static func scaled(_ weights: [Int64], to scale: Int64) -> [Int64] {
        guard !weights.isEmpty else { return [] }
        let positive = weights.map { max($0, 0) }
        guard positive.reduce(0, +) > 0 else { return equalWeights(count: weights.count, scale: scale) }
        let keyed = Dictionary(uniqueKeysWithValues: positive.enumerated().map { (Index($0.offset), $0.element) })
        guard let parts = try? LargestRemainderAllocator.allocate(total: scale, weights: keyed) else {
            return equalWeights(count: weights.count, scale: scale)
        }
        return (0..<weights.count).map { parts[Index($0)] ?? 0 }
    }

    /// Where each divider would sit in a perfectly equal split.
    static func equalBoundaries(count: Int, scale: Int64) -> [Int64] {
        var running: Int64 = 0
        return equalWeights(count: count, scale: scale).dropLast().map { running += $0; return running }
    }

    /// Detents for one divider. `prefix` is where the segment left of the divider starts.
    ///
    /// - Parameters:
    ///   - totalMinor: the expense total in minor units, only to place whole amount detents; nil skips them.
    ///   - unitMinor: minor units in one major unit, such as 100 for dollars.
    ///   - spaceIsMinorUnits: whole amount detents are only exact when the scale is the total itself.
    static func detents(
        divider: Int, count: Int, scale: Int64, prefix: Int64,
        totalMinor: Int64? = nil, unitMinor: Int64 = 100, spaceIsMinorUnits: Bool = false,
        percentStep: Int64 = 5, threshold: Int64
    ) -> [SplitBarDetent] {
        var found: [SplitBarDetent] = []
        let equal = equalBoundaries(count: count, scale: scale)
        if equal.indices.contains(divider) { found.append(SplitBarDetent(position: equal[divider], kind: .equal)) }

        if spaceIsMinorUnits, let totalMinor, totalMinor == scale, unitMinor > 0, unitMinor * 3 <= totalMinor {
            // only when whole amounts are far enough apart to be separate stops
            if unitMinor >= threshold {
                var position = prefix + unitMinor
                while position < scale {
                    found.append(SplitBarDetent(position: position, kind: .wholeAmount))
                    position += unitMinor
                }
            }
        }

        let step = scale * percentStep / 100
        if step >= 1 {
            var position = step
            while position < scale {
                found.append(SplitBarDetent(position: position, kind: .percent))
                position += step
            }
        }
        return found
    }

    /// Moves the divider after segment `divider` to `raw` (a running total in the bar's space).
    ///
    /// The position is kept inside the minimum segment sizes, snapped to the strongest detent within
    /// `threshold`, and otherwise rounded to `freeStep` so values stay tidy.
    static func drag(
        divider: Int, to raw: Int64, weights: [Int64], detents: [SplitBarDetent],
        freeStep: Int64, minimum: Int64, threshold: Int64
    ) -> SplitBarDrag {
        guard weights.indices.contains(divider), weights.indices.contains(divider + 1) else {
            return SplitBarDrag(weights: weights, snappedTo: nil, didChange: false)
        }
        let prefix = weights[..<divider].reduce(0, +)
        let pair = weights[divider] + weights[divider + 1]
        let low = prefix + minimum
        let high = prefix + pair - minimum
        guard low <= high else { return SplitBarDrag(weights: weights, snappedTo: nil, didChange: false) }

        let clamped = min(max(raw, low), high)
        let near = detents
            .filter { $0.position >= low && $0.position <= high && abs($0.position - clamped) <= threshold }
            .min { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                return abs(lhs.position - clamped) < abs(rhs.position - clamped)
            }

        let position: Int64
        if let near {
            position = near.position
        } else {
            let step = max(freeStep, 1)
            let rounded = ((clamped + step / 2) / step) * step
            position = min(max(rounded, low), high)
        }

        var next = weights
        next[divider] = position - prefix
        next[divider + 1] = pair - next[divider]
        return SplitBarDrag(weights: next, snappedTo: near?.kind, didChange: next != weights)
    }

    /// Drags a divider in a bar of whole shares. When neighbours are too coarse to move smoothly,
    /// every weight is multiplied first, and the result is reduced again afterwards.
    static func dragShares(divider: Int, toFraction fraction: Double, weights: [Int64]) -> SplitBarDrag {
        guard weights.indices.contains(divider + 1), weights.allSatisfy({ $0 > 0 }) else {
            return SplitBarDrag(weights: weights, snappedTo: nil, didChange: false)
        }
        let pair = weights[divider] + weights[divider + 1]
        let multiplier = max(Int64(1), (Int64(8) + pair - 1) / pair)
        let scaledWeights = weights.map { $0 * multiplier }
        let scale = scaledWeights.reduce(0, +)
        let raw = Int64((min(max(fraction, 0), 1) * Double(scale)).rounded())
        let equal = equalBoundaries(count: weights.count, scale: scale)
        let detents = equal.indices.contains(divider) ? [SplitBarDetent(position: equal[divider], kind: .equal)] : []
        var result = drag(
            divider: divider, to: raw, weights: scaledWeights, detents: detents,
            freeStep: 1, minimum: 1, threshold: max(scale / 40, 1)
        )
        let divisor = result.weights.reduce(0) { gcd($0, $1) }
        if divisor > 1 { result.weights = result.weights.map { $0 / divisor } }
        result.didChange = result.weights != weights
        return result
    }

    /// Moves `step` units from one segment to its neighbour, for VoiceOver and the steppers.
    static func nudge(
        index: Int, by step: Int64, weights: [Int64], minimum: Int64
    ) -> [Int64] {
        guard weights.indices.contains(index), weights.count > 1 else { return weights }
        // the divider that moves is the one on the right, or on the left for the last segment
        let divider = index == weights.count - 1 ? index - 1 : index
        let direction: Int64 = index == weights.count - 1 ? -1 : 1
        let pair = weights[divider] + weights[divider + 1]
        let newLeft = min(max(weights[divider] + direction * step, minimum), pair - minimum)
        guard newLeft >= minimum, pair - newLeft >= minimum else { return weights }
        var next = weights
        next[divider] = newLeft
        next[divider + 1] = pair - newLeft
        return next
    }

    /// Amounts for weights, adding up to `total` exactly with the SpltCore allocator.
    static func amounts(for weights: [Int64], total: Money) -> [Money] {
        let parts = scaled(weights, to: total.minorUnits)
        return parts.map { Money(minorUnits: $0, currencyCode: total.currencyCode) }
    }

    /// Own plus-or-minus amounts that make an equal split land on `shares`.
    /// `equal` is the equal split the calculator will use, so spare cents cancel out exactly.
    static func adjustments(for shares: [Int64], equal: [Int64]? = nil) -> [Int64] {
        let total = shares.reduce(0, +)
        let base = equal ?? equalWeights(count: shares.count, scale: total)
        return zip(shares, base).map { $0 - $1 }
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    /// Dictionary keys for the allocator, ordered by position.
    private struct Index: Hashable, Comparable {
        let value: Int
        init(_ value: Int) { self.value = value }
        static func < (lhs: Index, rhs: Index) -> Bool { lhs.value < rhs.value }
    }
}
