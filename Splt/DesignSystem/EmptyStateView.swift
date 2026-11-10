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
                // ContentUnavailableView shrinks its actions to fit, so the button can't rely on
                // filling the screen for its width.
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(minWidth: 240)
                    .padding(.horizontal, Depth.pageMargin)
            }
        }
        // this view doesn't scroll, so larger text would push the button under the tab bar
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension EmptyStateView {
    /// A search that found nothing.
    static func search(query: String) -> EmptyStateView {
        EmptyStateView(
            title: "No Results for “\(query)”",
            systemImage: "magnifyingglass",
            description: "Check the spelling or try a different search."
        )
    }

    /// The store couldn't be opened, so there is nothing to show. Use on any screen that needs it.
    static var dataUnavailable: EmptyStateView {
        EmptyStateView(
            title: "Can't Open Your Data",
            systemImage: "exclamationmark.triangle",
            description: "Restart the app and try again."
        )
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
