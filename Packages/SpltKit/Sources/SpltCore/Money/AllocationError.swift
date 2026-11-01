/// Why an amount could not be allocated.
public enum AllocationError: Error, Equatable, Sendable {
    /// There was nobody to allocate to.
    case noWeights
    /// A weight was negative.
    case negativeWeight
    /// Every weight was zero, so there is nothing to divide by.
    case zeroTotalWeight
    /// A result does not fit in 64 bits.
    case overflow
}
