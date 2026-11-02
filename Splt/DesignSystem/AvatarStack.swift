import SpltCore
import SwiftUI

/// Who is in a row, as overlapping avatars with a "+3" when there are more than fit.
struct AvatarStack: View {
    struct Item: Identifiable, Hashable {
        var id: PersonID
        var name: String
    }

    let items: [Item]
    /// The people whose colors must not collide, usually the whole group.
    let members: [PersonID]
    var limit = 4
    /// The color of the ring that separates neighbors. Match the surface the stack sits on.
    var ring = Color(.systemBackground)

    @ScaledMetric private var scaledDiameter: CGFloat
    private let baseDiameter: CGFloat

    init(
        _ people: [Person], members: [PersonID]? = nil, size: CGFloat = 32, limit: Int = 4,
        ring: Color = Color(.systemBackground)
    ) {
        items = people.map { Item(id: $0.id, name: $0.name) }
        self.members = members ?? people.map(\.id)
        self.limit = limit
        self.ring = ring
        baseDiameter = size
        _scaledDiameter = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var diameter: CGFloat { AvatarView.diameter(scaled: scaledDiameter, base: baseDiameter) }
    private var shown: [Item] { Array(items.prefix(limit)) }
    private var overflow: Int { max(items.count - limit, 0) }

    var body: some View {
        HStack(spacing: -diameter * 0.3) {
            ForEach(shown) { item in
                AvatarView(name: item.name, id: item.id, members: members, size: baseDiameter, showsInitials: baseDiameter >= 34)
                    .overlay { Circle().strokeBorder(ring, lineWidth: 2) }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: diameter, height: diameter)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .overlay { Circle().strokeBorder(ring, lineWidth: 2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenNames)
    }

    private var spokenNames: String {
        let names = items.map(\.name)
        return ListFormatter.localizedString(byJoining: names)
    }
}

#Preview {
    let people = ["Sam Rivera", "Priya Nair", "Alex Chen", "Jo Park", "Maria Gonzalez", "Lee Wong"].map { Person(name: $0) }
    VStack(alignment: .leading, spacing: 16) {
        AvatarStack(people)
        AvatarStack(Array(people.prefix(2)), size: 44)
    }
    .padding()
}
