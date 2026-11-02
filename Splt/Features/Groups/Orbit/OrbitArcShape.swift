import SpltCore
import SwiftUI

/// One transfer drawn as a ribbon that narrows toward the person who is owed. `progress` slides it
/// between two shapes, which is how arcs merge when the group simplifies its debts.
struct OrbitArcShape: Shape {
    var from: ArcGeometry
    var to: ArcGeometry
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let geometry = ArcGeometry.lerp(from, to, CGFloat(progress))
        guard geometry.width > 0.05 else { return Path() }
        let edges = geometry.ribbon()
        var path = Path()
        path.move(to: edges.left[0])
        for point in edges.left.dropFirst() { path.addLine(to: point) }
        for point in edges.right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// The colors people have on the ring: each member's palette hue, never two alike.
struct OrbitColors {
    private let assignments: [PersonID: Int]

    init(members: [PersonID]) {
        assignments = PersonPalette.assignments(for: members)
    }

    /// The text color to put on a person's circle, black or white, whichever reads better on that fill.
    func ink(for person: PersonID) -> Color {
        PersonPalette.onColor(at: assignments[person] ?? PersonPalette.index(for: person))
    }

    func color(for person: PersonID) -> Color {
        assignments[person].map { PersonPalette.color(at: $0) } ?? PersonPalette.color(for: person)
    }

    /// A flow from the person who owes to the person who is owed.
    func gradient(for transfer: OrbitTransfer, from start: CGPoint, to end: CGPoint, in size: CGSize) -> LinearGradient {
        let width = max(size.width, 1), height = max(size.height, 1)
        return LinearGradient(
            colors: [color(for: transfer.debtor), color(for: transfer.creditor)],
            startPoint: UnitPoint(x: start.x / width, y: start.y / height),
            endPoint: UnitPoint(x: end.x / width, y: end.y / height)
        )
    }
}
