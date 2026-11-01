import Testing
@testable import SpltCore

@Suite("Largest remainder allocator")
struct LargestRemainderAllocatorTests {
    @Test func splitsEvenlyWhenPossible() throws {
        #expect(try LargestRemainderAllocator.allocate(total: 900, weights: [1, 1, 1]) == [300, 300, 300])
    }

    @Test func spareUnitsGoToTheFirstPositions() throws {
        #expect(try LargestRemainderAllocator.allocate(total: 100, weights: [1, 1, 1]) == [34, 33, 33])
        #expect(try LargestRemainderAllocator.allocate(total: 101, weights: [1, 1, 1]) == [34, 34, 33])
        #expect(try LargestRemainderAllocator.allocate(total: 2, weights: [1, 1, 1, 1, 1]) == [1, 1, 0, 0, 0])
    }

    @Test func largerRemaindersWin() throws {
        // 10 split 1:2:2 gives 2, 4, 4 exactly. 10 split 3:3:4 gives 3, 3, 4. 7 split 2:2:3 is 2, 2, 3
        #expect(try LargestRemainderAllocator.allocate(total: 10, weights: [1, 2, 2]) == [2, 4, 4])
        // 5 split 1:1:1 leaves remainders tied, but 5 split 3:1 gives 3.75 and 1.25 so the first rounds up
        #expect(try LargestRemainderAllocator.allocate(total: 5, weights: [3, 1]) == [4, 1])
        // 7 split 1:1:5 gives 1.0, 1.0, 5.0; 8 split 1:1:5 gives 1.14, 1.14, 5.71 so the last takes the spare
        #expect(try LargestRemainderAllocator.allocate(total: 8, weights: [1, 1, 5]) == [1, 1, 6])
    }

    @Test func zeroWeightsGetNothing() throws {
        #expect(try LargestRemainderAllocator.allocate(total: 100, weights: [0, 1, 0, 2]) == [0, 33, 0, 67])
        #expect(try LargestRemainderAllocator.allocate(total: 1, weights: [0, 0, 1, 0]) == [0, 0, 1, 0])
    }

    @Test func negativeTotalsMirrorPositiveOnes() throws {
        let positive = try LargestRemainderAllocator.allocate(total: 101, weights: [1, 2, 3, 5])
        let negative = try LargestRemainderAllocator.allocate(total: -101, weights: [1, 2, 3, 5])
        #expect(negative == positive.map { -$0 })
        #expect(negative.reduce(0, +) == -101)
    }

    @Test func zeroTotalIsAllZero() throws {
        #expect(try LargestRemainderAllocator.allocate(total: 0, weights: [1, 2]) == [0, 0])
        #expect(try LargestRemainderAllocator.allocate(total: 0, weights: [0, 0]) == [0, 0])
    }

    @Test func rejectsBadWeights() {
        #expect(throws: AllocationError.noWeights) { try LargestRemainderAllocator.allocate(total: 1, weights: []) }
        #expect(throws: AllocationError.negativeWeight) { try LargestRemainderAllocator.allocate(total: 1, weights: [1, -1]) }
        #expect(throws: AllocationError.zeroTotalWeight) { try LargestRemainderAllocator.allocate(total: 1, weights: [0, 0]) }
    }

    @Test func tieBreakOffsetRotatesWhoGetsTheSpareUnit() throws {
        #expect(try LargestRemainderAllocator.allocate(total: 1, weights: [1, 1, 1], tieBreakOffset: 0) == [1, 0, 0])
        #expect(try LargestRemainderAllocator.allocate(total: 1, weights: [1, 1, 1], tieBreakOffset: 1) == [0, 1, 0])
        #expect(try LargestRemainderAllocator.allocate(total: 1, weights: [1, 1, 1], tieBreakOffset: 5) == [0, 0, 1])
        #expect(try LargestRemainderAllocator.allocate(total: 1, weights: [1, 1, 1], tieBreakOffset: -1) == [0, 0, 1])
    }

    @Test func handlesExtremeValuesWithoutOverflow() throws {
        let parts = try LargestRemainderAllocator.allocate(total: Int64.max, weights: [Int64.max, Int64.max, Int64.max])
        #expect(parts.reduce(0, +) == Int64.max)
        let negative = try LargestRemainderAllocator.allocate(total: Int64.min, weights: [1])
        #expect(negative == [Int64.min])
    }

    @Test func keyedVariantUsesSortedKeys() throws {
        let result = try LargestRemainderAllocator.allocate(total: 100, weights: ["b": 1, "a": 1, "c": 1])
        #expect(result == ["a": 34, "b": 33, "c": 33])
    }

    @Test func alwaysSumsToTheTotal() throws {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<2_000 {
            let count = Int.random(in: 1...12, using: &generator)
            let weights = (0..<count).map { _ in Int64.random(in: 0...1_000, using: &generator) }
            guard weights.contains(where: { $0 > 0 }) else { continue }
            let total = Int64.random(in: -1_000_000...1_000_000, using: &generator)
            let parts = try LargestRemainderAllocator.allocate(total: total, weights: weights)
            #expect(parts.reduce(0, +) == total)
            let weightSum = weights.reduce(0, +)
            for (part, weight) in zip(parts, weights) {
                let exact = Double(total) * Double(weight) / Double(weightSum)
                #expect(abs(Double(part) - exact) < 1.0 + 1e-9)
            }
        }
    }
}
