/// Why a split definition cannot be turned into shares.
public enum SplitError: Error, Equatable, Sendable {
    /// Nobody takes part in the split.
    case noParticipants
    /// An amount uses a different currency than the total.
    case currencyMismatch(expected: String, found: String)
    /// Exact amounts do not add up to the total.
    case exactAmountsDoNotMatchTotal(expected: Money, actual: Money)
    /// Percentages, in basis points, do not add up to 10000.
    case percentagesDoNotSumToHundred(actualBasisPoints: Int64)
    case negativePercentage(PersonID)
    case negativeWeight(PersonID)
    /// Every share weight is zero.
    case zeroTotalWeight
    /// An adjustment names someone who is not in the split.
    case adjustmentForNonParticipant(PersonID)
    /// A person would owe a negative amount on a positive expense, or the reverse on a refund.
    case negativeShare(PersonID)
    /// An item was not assigned to anyone.
    case itemWithoutAssignees(itemIndex: Int)
    /// An itemized split contains a negative amount. Refunds cannot be itemized.
    case negativeAmount
    /// The discount is larger than the items it applies to.
    case discountExceedsSubtotal
    /// Items plus tax and tip minus discount do not equal the total.
    case itemizedTotalMismatch(expected: Money, actual: Money)
    /// A calculation does not fit in 64 bits.
    case overflow
    /// The allocator rejected its input in a way the checks above did not anticipate.
    case allocationFailed(AllocationError)
}
