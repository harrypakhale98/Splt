import Foundation

enum GroupErrorMessage {
    static func text(for error: any Error) -> String {
        guard let error = error as? DataError else {
            return String(localized: "Something went wrong. Please try again.")
        }
        switch error {
        case .memberStillHasBalance:
            return String(localized: "Settle up first. This person still owes or is owed money in the group.")
        case .notFound:
            return String(localized: "That group is no longer available.")
        default:
            return String(localized: "Something went wrong. Please try again.")
        }
    }
}
