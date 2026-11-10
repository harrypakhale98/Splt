import SpltCore
import SwiftUI

/// Chooses people you already split with.
struct FriendPickerView: View {
    let friends: [Person]
    let isSelected: (Person) -> Bool
    let toggle: (Person) -> Void

    @State private var changeCount = 0

    var body: some View {
        List {
            RaisedRows {
                ForEach(friends) { friend in
                    Button {
                        toggle(friend)
                        changeCount += 1
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(person: friend, size: 28)
                            Text(friend.name)
                                .foregroundStyle(Ink.text)
                            Spacer()
                            if isSelected(friend) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Ink.text)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(isSelected(friend) ? .isSelected : [])
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .overlay {
            if friends.isEmpty {
                EmptyStateView(
                    title: "No Friends Yet",
                    systemImage: "person.2",
                    description: "People you add to a group show up here next time."
                )
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: changeCount)
    }
}
