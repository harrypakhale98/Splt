enum PersonKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// The owner of this device.
    case me
    /// Someone who uses, or can use, the app.
    case friend
    /// A name in a group for someone without the app. It can be claimed later.
    case placeholder
}
