import SwiftUI

/// A stock empty state with an optional primary action.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        title: "No Groups Yet",
        systemImage: "person.3",
        description: "Create a group for a trip, a home or a night out.",
        actionTitle: "Create Group",
        action: {}
    )
}

#Preview("No action") {
    EmptyStateView(title: "Nothing Here", systemImage: "tray", description: "Check back later.")
}
