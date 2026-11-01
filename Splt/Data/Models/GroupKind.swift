enum GroupKind: String, Hashable, Sendable, Codable, CaseIterable {
    case standard
    case trip
    case couple
    /// The hidden two person group behind a friend that has no shared group.
    case friend
}
