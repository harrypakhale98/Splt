import Foundation
import SpltCore
import SwiftUI

/// Moves everything that mentions a placeholder over to another person, then removes the placeholder.
@MainActor
protocol PlaceholderMerging {
    /// Returns how many records changed. Throws `MergeError.sharedRecord` when both people
    /// appear in one expense or payment, because their shares cannot be added together automatically.
    @discardableResult
    func merge(_ placeholder: PersonID, into target: PersonID) throws -> Int
}

enum MergeError: Error, Equatable {
    case notAPlaceholder
    case unknownPerson
    case sharedRecord(Int)

    var message: String {
        switch self {
        case .notAPlaceholder: String(localized: "Only people who haven't joined Splt can be merged.")
        case .unknownPerson: String(localized: "That person is no longer available.")
        case .sharedRecord: String(localized: "They appear in the same expense or payment, so Splt can't combine them automatically. Edit or delete that item first.")
        }
    }
}

extension EnvironmentValues {
    /// Set by the app when merging is available. Nil hides the merge option.
    @Entry var placeholderMerger: (any PlaceholderMerging)?
}
