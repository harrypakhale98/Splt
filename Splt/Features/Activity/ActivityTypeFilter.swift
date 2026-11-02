import Foundation

/// Which kinds of events the feed shows.
enum ActivityTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case expenses
    case payments
    case comments
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All Activity")
        case .expenses: String(localized: "Expenses")
        case .payments: String(localized: "Payments")
        case .comments: String(localized: "Comments")
        case .groups: String(localized: "Groups and Members")
        }
    }

    var shortTitle: String {
        switch self {
        case .all: String(localized: "All")
        case .expenses: String(localized: "Expenses")
        case .payments: String(localized: "Payments")
        case .comments: String(localized: "Comments")
        case .groups: String(localized: "Groups")
        }
    }

    var symbol: String {
        switch self {
        case .all: "list.bullet"
        case .expenses: "receipt"
        case .payments: "checkmark.circle"
        case .comments: "bubble.left"
        case .groups: "person.3"
        }
    }

    func includes(_ kind: ActivityKind) -> Bool {
        switch self {
        case .all: true
        case .expenses: [.expenseAdded, .expenseEdited, .expenseDeleted, .expenseRestored, .expensesImported].contains(kind)
        case .payments: [.paymentRecorded, .paymentUndone].contains(kind)
        case .comments: kind == .commentAdded
        case .groups: [.groupCreated, .groupRenamed, .groupArchived, .groupRestored, .memberAdded, .memberRemoved].contains(kind)
        }
    }
}

extension ActivityKind {
    var symbol: String {
        switch self {
        case .groupCreated, .groupRenamed, .groupArchived, .groupRestored: "person.3"
        case .memberAdded: "person.badge.plus"
        case .memberRemoved: "person.badge.minus"
        case .expenseAdded: "plus.circle"
        case .expenseEdited: "pencil.circle"
        case .expenseDeleted: "trash.circle"
        case .expenseRestored: "arrow.uturn.backward.circle"
        case .paymentRecorded: "checkmark.circle"
        case .paymentUndone: "arrow.uturn.backward.circle"
        case .commentAdded: "bubble.left"
        case .expensesImported: "square.and.arrow.down"
        }
    }
}
