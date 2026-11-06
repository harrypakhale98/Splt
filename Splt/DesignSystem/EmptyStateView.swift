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
                    .padding(.horizontal, 16)
            }
        }
        // this view doesn't scroll, so larger text would push the button under the tab bar
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
