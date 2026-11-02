import SpltCore
import SwiftUI

/// A person's avatar and name with an input beside it. At accessibility text sizes the input
/// drops below the name so nothing truncates.
struct PersonFieldRow<Field: View>: View {
    let person: Person
    let name: String
    var members: [PersonID] = []
    var fieldWidth: CGFloat = 140
    @ViewBuilder var field: () -> Field

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                label
                field()
            }
        } else {
            HStack {
                label
                Spacer(minLength: 8)
                field().frame(maxWidth: fieldWidth)
            }
        }
    }

    private var label: some View {
        HStack {
            AvatarView(person: person, members: members, size: 28)
            Text(name)
        }
    }
}
