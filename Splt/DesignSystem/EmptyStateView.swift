import SwiftUI

/// An empty state with an optional primary action. The main tabs show the orbit motif.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    var showsOrbit = false

    var body: some View {
        if showsOrbit {
            ScrollView {
                VStack(spacing: 24) {
                    OrbitMotif(size: 180) {
                        Image(systemName: systemImage)
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
            }
            .scrollBounceBehavior(.basedOnSize)
            .containerRelativeFrame(.vertical, alignment: .center)
        } else {
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
}

#Preview {
    EmptyStateView(
        title: "No Groups Yet",
        systemImage: "person.3",
        description: "Create a group for a trip, a home or a night out.",
        actionTitle: "Create Group",
        action: {},
        showsOrbit: true
    )
}

#Preview("Plain") {
    EmptyStateView(title: "Nothing Here", systemImage: "tray", description: "Check back later.")
}
