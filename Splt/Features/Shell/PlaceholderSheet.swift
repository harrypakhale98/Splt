import SwiftUI

/// Stands in for the real flow until its feature lands.
struct PlaceholderSheet: View {
    let sheet: AppSheet

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", role: .close) { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private var content: some View {
        EmptyStateView(
            title: "Coming Soon",
            systemImage: symbol,
            description: "This part of Splt is on its way."
        )
    }

    private var title: LocalizedStringKey {
        switch sheet {
        case .addExpense: "New Expense"
        case .newGroup: "New Group"
        case .newFriend: "New Friend"
        }
    }

    private var symbol: String {
        switch sheet {
        case .addExpense: "plus.circle"
        case .newGroup: "person.3"
        case .newFriend: "person.badge.plus"
        }
    }
}

#Preview("Expense") {
    PlaceholderSheet(sheet: .addExpense)
}

#Preview("Group") {
    PlaceholderSheet(sheet: .newGroup)
}
