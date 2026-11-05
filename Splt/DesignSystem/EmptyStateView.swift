import SwiftUI

/// An empty state: one sentence on paper, with an optional primary action.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title).font(Typeface.heading)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(Ink.tertiary)
            }
        } description: {
            Text(description).foregroundStyle(Ink.secondary)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)
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
    .background(Ink.paper)
}
