import SwiftUI

/// People you hid or blocked on this device, with a way back.
struct HiddenFriendsView: View {
    let model: FriendsViewModel

    var body: some View {
        List {
            Section {
                ForEach(model.hiddenSummaries) { summary in
                    HStack(spacing: 12) {
                        AvatarView(person: summary.person, size: 28)
                        VStack(alignment: .leading) {
                            Text(summary.person.name)
                            Text(model.state(of: summary.id) == .blocked ? "Blocked" : "Hidden")
                                .font(.caption)
                                .foregroundStyle(Ink.secondary)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            Button("Show in Friends", systemImage: "eye") { model.setState(nil, for: summary.id) }
                            if model.state(of: summary.id) == .blocked {
                                Button("Unblock", systemImage: "hand.raised.slash") { model.setState(.hidden, for: summary.id) }
                            } else {
                                Button("Block", systemImage: "nosign", role: .destructive) { model.setState(.blocked, for: summary.id) }
                            }
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }
            } footer: {
                Text("Hidden people stay out of the list. Blocked people also stay out of search and reminders. This only changes what you see on this device.")
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .overlay {
            if model.hiddenSummaries.isEmpty {
                EmptyStateView(
                    title: "Nobody Hidden",
                    systemImage: "eye",
                    description: "People you hide or block show up here."
                )
            }
        }
        .navigationTitle("Hidden and Blocked")
        .navigationBarTitleDisplayMode(.inline)
    }
}
