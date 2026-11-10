import SpltCore
import SwiftUI

/// One transfer drawn as a ribbon that ends in a small arrowhead at the person who is owed.
/// `progress` slides it between two shapes, which is how arcs merge when the group simplifies its debts.
struct OrbitArcShape: Shape {
    var from: ArcGeometry
    var to: ArcGeometry
    var progress: Double
    /// Above 1 for a bolder arrowhead under Increase Contrast.
    var headScale: CGFloat = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let geometry = ArcGeometry.lerp(from, to, CGFloat(progress))
        guard geometry.width > 0.05 else { return Path() }
        let outline = geometry.arrowOutline(headScale: headScale)
        guard let first = outline.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for point in outline.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// An arc on its way between direct debts and the fewest payments. Its color blends from the old
/// debtor's to the new one's and its emphasis from the old focus state to the new, in step with the
/// shape, so nothing snaps while the arcs merge.
struct OrbitMorphArc: View, @MainActor Animatable {
    var from: ArcGeometry
    var to: ArcGeometry
    var fromColor: Color
    var toColor: Color
    var fromOpacity: Double
    var toOpacity: Double
    var headScale: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        OrbitArcShape(from: from, to: to, progress: progress, headScale: headScale)
            .fill(fromColor.mix(with: toColor, by: progress))
            .opacity(fromOpacity + (toOpacity - fromOpacity) * progress)
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

    /// A ribbon takes the color of the person who owes.
    func ribbon(for transfer: OrbitTransfer) -> Color {
        color(for: transfer.debtor)
    }
}
