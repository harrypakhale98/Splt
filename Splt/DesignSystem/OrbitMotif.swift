import SwiftUI

/// The Splt motif: a ring with people placed evenly around it. On appear the people travel out
/// from the middle and settle on the ring. With Reduce Motion they are simply there.
struct OrbitMotif<Center: View>: View {
    var names: [String]
    var size: CGFloat
    /// Lets the ring assemble when it appears. Turn off for a still picture, such as an icon preview.
    var animates = true
    @ViewBuilder var center: Center

    @State private var assembled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var scale: CGFloat = 1

    init(
        names: [String] = ["Sam", "Priya", "Alex", "Jo", "Mia"], size: CGFloat = 160, animates: Bool = true,
        @ViewBuilder center: () -> Center
    ) {
        self.names = names
        self.size = size
        self.animates = animates
        self.center = center()
    }

    private var side: CGFloat { size * min(scale, 1.4) }
    private var dot: CGFloat { side * 0.24 }
    private var radius: CGFloat { (side - dot) / 2 }
    private var isOut: Bool { assembled || reduceMotion || !animates }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ringGradient, lineWidth: max(side * 0.02, 2))
                .padding(dot / 2)
                .opacity(isOut ? 1 : 0)
                .scaleEffect(isOut ? 1 : 0.6)
            center
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                person(name, index: index)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .onAppear {
            guard animates, !reduceMotion else { return }
            assembled = true
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: assembled)
    }

    private func person(_ name: String, index: Int) -> some View {
        let angle = Angle.degrees(-90 + 360 * Double(index) / Double(max(names.count, 1)))
        let hue = index * PersonPalette.count / max(names.count, 1) + 1
        return Circle()
            .fill(PersonPalette.color(at: hue))
            .frame(width: dot, height: dot)
            .overlay {
                Text(AvatarStyle.initials(for: name))
                    .font(.system(size: dot * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(PersonPalette.onColor)
            }
            .offset(
                x: isOut ? radius * cos(angle.radians) : 0,
                y: isOut ? radius * sin(angle.radians) : 0
            )
            .scaleEffect(isOut ? 1 : 0.3)
            .opacity(isOut ? 1 : 0)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.8).delay(0.08 * Double(index)),
                value: assembled
            )
    }

    private var ringGradient: AngularGradient {
        let count = max(names.count, 1)
        let colors = (0..<count).map { PersonPalette.color(at: $0 * PersonPalette.count / count + 1).opacity(0.55) }
        return AngularGradient(colors: colors + [colors[0]], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }
}

extension OrbitMotif where Center == EmptyView {
    init(names: [String] = ["Sam", "Priya", "Alex", "Jo", "Mia"], size: CGFloat = 160, animates: Bool = true) {
        self.init(names: names, size: size, animates: animates) { EmptyView() }
    }
}

#Preview {
    OrbitMotif(size: 200) {
        Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(.tertiary)
    }
}
