import Foundation

/// A stored field value in the shapes CloudKit accepts, so the sync layer can copy it without knowing the model.
enum SyncValue: Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case data(Data)
}
