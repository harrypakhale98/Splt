enum ExactSettlement {
    /// Most people the exact search handles. The work grows as 2 to the power of the head count.
    static let maximumPeople = 12

    /// Settles with the fewest transfers possible, or nil if there are too many people to search.
    ///
    /// A group of k people whose balances add up to zero can always settle among themselves
    /// with k - 1 transfers, and no fewer unless it contains a smaller zero-sum group. So the
    /// fewest transfers come from cutting everyone into as many zero-sum groups as possible.
    /// A dynamic program over subsets finds the largest number of groups.
    static func transfers(for balances: [PersonID: Int64]) -> [DebtFlow]? {
        let people = balances.filter { $0.value != 0 }.keys.sorted()
        guard !people.isEmpty, people.count <= maximumPeople else { return people.isEmpty ? [] : nil }
        let values = people.map { Int128(balances[$0] ?? 0) }
        let full = (1 << people.count) - 1

        var sums = [Int128](repeating: 0, count: full + 1)
        var groups = [Int](repeating: 0, count: full + 1)
        var lastAdded = [Int](repeating: 0, count: full + 1)
        for mask in 1...full {
            let lowest = mask.trailingZeroBitCount
            sums[mask] = sums[mask & (mask - 1)] + values[lowest]
            var best = -1
            var bestIndex = 0
            for index in 0..<people.count where mask & (1 << index) != 0 {
                let previous = groups[mask ^ (1 << index)]
                if previous > best {
                    best = previous
                    bestIndex = index
                }
            }
            groups[mask] = best + (sums[mask] == 0 ? 1 : 0)
            lastAdded[mask] = bestIndex
        }

        var order: [Int] = []
        var mask = full
        while mask != 0 {
            let index = lastAdded[mask]
            order.append(index)
            mask ^= 1 << index
        }
        order.reverse()

        var result: [DebtFlow] = []
        var block: [PersonID: Int64] = [:]
        var running: Int128 = 0
        for index in order {
            block[people[index]] = balances[people[index]]
            running += values[index]
            if running == 0 {
                result += GreedySettlement.transfers(for: block)
                block = [:]
            }
        }
        return result
    }
}
