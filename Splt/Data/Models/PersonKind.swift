enum PersonKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// The owner of this device. It never syncs: other devices see the same person as a friend.
    case me
    /// Someone who uses, or can use, the app.
    case friend
    /// A name in a group for someone without the app. It can be claimed later.
    case placeholder
}
