import CoreGraphics

/// How the bar is drawn: the same weights as the data, but no segment is narrower than `minimum`
/// points, so a person who owes almost nothing can still be seen and touched. Dividers sit at the
/// drawn boundaries, and `fraction(forX:)` turns a touch position back into the real position.
struct SplitBarLayout: Equatable {
    let widths: [CGFloat]
    /// Drawn boundaries, from 0 to the full width: one more than there are segments.
    let visual: [CGFloat]
    /// The real boundaries as fractions of the whole, from 0 to 1.
    let truth: [Double]

    static func make(weights: [Int64], scale: Int64, width: CGFloat, minimum: CGFloat = 28) -> SplitBarLayout {
        let count = weights.count
        let usable = width.isFinite ? max(width, 0) : 0
        guard count > 0 else { return SplitBarLayout(widths: [], visual: [0], truth: [0]) }

        let total = Double(max(scale, 1))
        let natural = weights.map { usable * CGFloat(max(Double($0), 0) / total) }
        var widths = natural
        if CGFloat(count) * minimum >= usable {
            widths = Array(repeating: usable / CGFloat(count), count: count)
        } else {
            var pinned = Set<Int>()
            while true {
                let free = widths.indices.filter { !pinned.contains($0) }
                let remaining = usable - CGFloat(pinned.count) * minimum
                let freeNatural = free.reduce(CGFloat(0)) { $0 + natural[$1] }
                guard freeNatural > 0 else { break }
                var changed = false
                for index in free {
                    let proposed = natural[index] / freeNatural * remaining
                    if proposed < minimum {
                        pinned.insert(index)
                        changed = true
                    }
                }
                if !changed {
                    for index in free { widths[index] = natural[index] / freeNatural * remaining }
                    break
                }
            }
            for index in pinned { widths[index] = minimum }
        }

        var visual: [CGFloat] = [0]
        var truth: [Double] = [0]
        var runningWeight: Int64 = 0
        for (index, width) in widths.enumerated() {
            visual.append(visual[index] + width)
            runningWeight += weights[index]
            truth.append(min(Double(runningWeight) / total, 1))
        }
        return SplitBarLayout(widths: widths, visual: visual, truth: truth)
    }

    /// The real position, from 0 to 1, that a touch at drawn position `x` stands for.
    func fraction(forX x: CGFloat) -> Double {
        guard visual.count > 1, let last = visual.last, last > 0 else { return 0 }
        let clamped = min(max(x, 0), last)
        for index in 1..<visual.count where clamped <= visual[index] {
            let span = visual[index] - visual[index - 1]
            guard span > 0 else { return truth[index] }
            let progress = Double((clamped - visual[index - 1]) / span)
            return truth[index - 1] + progress * (truth[index] - truth[index - 1])
        }
        return truth.last ?? 1
    }
}
