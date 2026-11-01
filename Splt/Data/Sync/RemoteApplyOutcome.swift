/// What happened to a record when a remote version was applied.
enum RemoteApplyOutcome: Hashable, Sendable {
    /// There was no local copy, so one was created.
    case inserted
    /// The remote version replaced a clean local copy.
    case updated
    /// The remote version won over local changes that had not been uploaded; those are discarded
    /// and the engine should drop the pending upload.
    case replacedLocalChanges
    /// The local version won. It stays dirty and uploads again with the fresh system fields.
    case keptLocal
}
