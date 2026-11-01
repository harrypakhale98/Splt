/// Divides a whole number of minor units in proportion to weights so the parts add up exactly.
///
/// Each part is rounded down, then the units left over go one by one to the parts with the
/// largest fractional remainder. Ties go to the lowest position, counted from
/// `tieBreakOffset`, so results never depend on hashing or timing. Negative totals are
/// allocated by magnitude and negated, so refunds mirror purchases.
public enum LargestRemainderAllocator {
    /// Allocates `total` across `weights`, returning one part per weight in the same order.
    ///
    /// - Parameter tieBreakOffset: moves the first position in the tie-break order, so callers
    ///   can rotate who receives spare units across many allocations.
    public static func allocate(total: Int64, weights: [Int64], tieBreakOffset: Int = 0) throws -> [Int64] {
        guard !weights.isEmpty else { throw AllocationError.noWeights }
        var weightSum: Int128 = 0
        for weight in weights {
            guard weight >= 0 else { throw AllocationError.negativeWeight }
            weightSum += Int128(weight)
        }
        guard weightSum > 0 else {
            guard total == 0 else { throw AllocationError.zeroTotalWeight }
            return Array(repeating: 0, count: weights.count)
        }

        let sign: Int128 = total < 0 ? -1 : 1
        let magnitude = Int128(total) * sign
        var parts: [Int128] = []
        var remainders: [Int128] = []
        parts.reserveCapacity(weights.count)
        remainders.reserveCapacity(weights.count)
        var allocated: Int128 = 0
        for weight in weights {
            let product = magnitude * Int128(weight)
            parts.append(product / weightSum)
            remainders.append(product % weightSum)
            allocated += parts[parts.count - 1]
        }

        let count = weights.count
        let offset = ((tieBreakOffset % count) + count) % count
        let order = parts.indices.sorted { lhs, rhs in
            if remainders[lhs] != remainders[rhs] { return remainders[lhs] > remainders[rhs] }
            return (lhs - offset + count) % count < (rhs - offset + count) % count
        }
        for index in order.prefix(Int(magnitude - allocated)) {
            parts[index] += 1
        }

        return try parts.map { part in
            guard let value = Int64(exactly: part * sign) else { throw AllocationError.overflow }
            return value
        }
    }

    /// Allocates `total` across keyed weights. Keys are visited in sorted order for the tie-break.
    public static func allocate<Key: Hashable & Comparable>(
        total: Int64,
        weights: [Key: Int64],
        tieBreakOffset: Int = 0
    ) throws -> [Key: Int64] {
        let keys = weights.keys.sorted()
        let parts = try allocate(total: total, weights: keys.map { weights[$0] ?? 0 }, tieBreakOffset: tieBreakOffset)
        return Dictionary(uniqueKeysWithValues: zip(keys, parts))
    }
}
