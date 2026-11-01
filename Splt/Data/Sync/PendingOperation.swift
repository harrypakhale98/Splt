/// What the sync engine still has to do for a record.
enum PendingOperation: String, Hashable, Sendable {
    /// Upload the record, including a soft delete, which is just a save with a tombstone.
    case save
    /// Delete the record on the server.
    case delete
}
