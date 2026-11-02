import SpltCore
import SwiftUI

/// The people of a group on a ring, with the money that has to move between them drawn as arcs.
/// Tap a person to follow their money and tap an arc to settle it.
struct BalanceOrbitView: View {
    let board: OrbitBoard
    /// Everyone in the group, so colors are assigned without collisions.
    let members: [PersonID]
    let onSettle: (Debt) -> Void

    @State private var focus: OrbitFocus
    @State private var previous: [OrbitTransfer] = []
    @State private var pairs: [MorphPair] = []
    @State private var progress = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(board: OrbitBoard, members: [PersonID], initialFocus: OrbitFocus = .none, onSettle: @escaping (Debt) -> Void) {
        self.board = board
        self.members = members
        self.onSettle = onSettle
        _focus = State(initialValue: initialFocus)
    }

    var body: some View {
        let colors = OrbitColors(members: members)
        GeometryReader { proxy in
            let scene = OrbitScene(size: proxy.size, people: board.people, transfers: board.transfers)
            ZStack {
                ring(scene)
                arcLayer(scene: scene, colors: colors)
                nodeLayer(scene: scene, colors: colors)
                amountLabels(scene: scene)
                OrbitCenterView(center: board.center(for: focus), diameter: scene.layout.centerRadius * 2)
                    .position(scene.layout.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                handle(scene.hit(at: value.location))
            })
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .motion(.snappy, value: focus)
        .onChange(of: board.transfers) { old, new in startMorph(from: old, to: new) }
        .onChange(of: board.nodes) { focus = .none }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(board.summary(locale: locale))
        .accessibilityChildren { accessibleChildren }
    }

    // MARK: Layers

    private func ring(_ scene: OrbitScene) -> some View {
        Circle()
            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
            .frame(width: scene.layout.ringRadius * 2, height: scene.layout.ringRadius * 2)
            .position(scene.layout.center)
    }

    @ViewBuilder
    private func arcLayer(scene: OrbitScene, colors: OrbitColors) -> some View {
        if pairs.isEmpty {
            ForEach(scene.arcs, id: \.transfer.id) { transfer, geometry in
                OrbitArcShape(from: geometry, to: geometry, progress: 1)
                    .fill(colors.gradient(for: transfer, from: geometry.start, to: geometry.end, in: scene.layout.size))
                    .opacity(scene.emphasis(of: transfer, focus: focus).opacity)
                    .transition(.opacity)
            }
        } else {
            let old = OrbitScene(size: scene.layout.size, people: board.people, transfers: previous)
            ForEach(pairs) { pair in
                if let shapes = OrbitMorph.geometry(for: pair, in: old, target: scene) {
                    let transfer = pair.end ?? pair.start
                    OrbitArcShape(from: shapes.from, to: shapes.to, progress: progress)
                        .fill(transfer.map { colors.gradient(for: $0, from: shapes.to.start, to: shapes.to.end, in: scene.layout.size) }
                              ?? LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom))
                        .opacity(0.9)
                }
            }
        }
    }

    @ViewBuilder
    private func amountLabels(scene: OrbitScene) -> some View {
        let showsAll = board.transfers.count == 1 && focus == .none
        let highlighted = scene.arcs.filter { scene.emphasis(of: $0.transfer, focus: focus) == .highlighted }.count
        ForEach(scene.arcs, id: \.transfer.id) { transfer, geometry in
            let emphasis = scene.emphasis(of: transfer, focus: focus)
            if pairs.isEmpty, showsAll || (emphasis == .highlighted && highlighted <= 4) {
                Text(MoneyFormatting.string(transfer.amount, locale: locale))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: .capsule)
                    .position(scene.pillPoint(for: geometry))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private func nodeLayer(scene: OrbitScene, colors: OrbitColors) -> some View {
        ForEach(Array(board.nodes.enumerated()), id: \.element.id) { index, node in
            let layout = scene.layout
            let emphasis = scene.emphasis(of: node.id, focus: focus)
            let point = layout.positions[index]
            ZStack {
                Circle()
                    .fill(colors.color(for: node.id))
                Text(AvatarStyle.initials(for: node.name))
                    .font(.system(size: layout.nodeRadius * 0.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(PersonPalette.onColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if focus.person == node.id {
                    Circle()
                        .strokeBorder(Color(.systemBackground), lineWidth: 2)
                        .padding(-3)
                        .overlay { Circle().strokeBorder(colors.color(for: node.id), lineWidth: 2).padding(-5) }
                }
            }
            .frame(width: layout.nodeRadius * 2, height: layout.nodeRadius * 2)
            .position(point)
            .opacity(emphasis == .dimmed ? 0.55 : 1)

            if showsLabel(for: node, layout: layout) {
                Text(label(for: node, layout: layout))
                    .font(layout.labelStyle == .name ? .caption.weight(.medium) : .caption2)
                    .lineLimit(1)
                    .foregroundStyle(emphasis == .dimmed ? .tertiary : .secondary)
                    .fixedSize()
                    .position(layout.labelPosition(index))
            }
        }
    }

    private func showsLabel(for node: OrbitNode, layout: OrbitLayout) -> Bool {
        layout.labelStyle != .hidden || focus.person == node.id
    }

    private func label(for node: OrbitNode, layout: OrbitLayout) -> String {
        let name = node.isMe ? String(localized: "You") : node.firstName
        guard layout.labelStyle != .name else { return name }
        return name.count > 7 ? String(name.prefix(6)) + "." : name
    }

    // MARK: Taps

    private func handle(_ target: OrbitTarget) {
        switch target {
        case .person(let id):
            focus.toggle(id)
        case .transfer(let id):
            if let transfer = board.transfers.first(where: { $0.id == id }) { onSettle(transfer.debt) }
        case .nothing:
            focus = .none
        }
    }

    // MARK: Morph

    private func startMorph(from old: [OrbitTransfer], to new: [OrbitTransfer]) {
        guard !reduceMotion, old != new, !old.isEmpty || !new.isEmpty else {
            pairs = []
            progress = 1
            return
        }
        previous = old
        pairs = OrbitMorph.pairs(from: old, to: new)
        progress = 0
        withAnimation(.smooth(duration: 0.8)) {
            progress = 1
        } completion: {
            pairs = []
        }
    }

    // MARK: VoiceOver

    @ViewBuilder
    private var accessibleChildren: some View {
        VStack {
            ForEach(board.transfers) { transfer in
                Button(board.spoken(transfer, locale: locale)) { onSettle(transfer.debt) }
                    .accessibilityHint("Opens settle up")
            }
            ForEach(board.nodes) { node in
                Button(accessibleDescription(of: node)) { focus.toggle(node.id) }
            }
        }
    }

    private func accessibleDescription(of node: OrbitNode) -> String {
        let name = node.isMe ? String(localized: "You") : node.name
        let net = board.net(of: node.id)
        let amount = MoneyFormatting.magnitudeString(net, locale: locale)
        if net.minorUnits > 0 { return String(localized: "\(name), is owed \(amount)") }
        if net.minorUnits < 0 { return String(localized: "\(name), owes \(amount)") }
        return String(localized: "\(name), settled up")
    }
}

/// The big number in the middle: your balance, or the balance of whoever is focused.
struct OrbitCenterView: View {
    let center: OrbitCenter
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            switch center.kind {
            case .settled:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Group {
                    if center.subjectIsMe || center.subject.isEmpty {
                        Text("All settled up")
                    } else {
                        Text("\(center.subject) is settled up")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            default:
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HeroAmount(signed, showsSign: center.subjectIsMe)
            }
        }
        .frame(width: diameter * 0.84)
        .frame(width: diameter, height: diameter)
        .background(Color(.secondarySystemGroupedBackground), in: .circle)
        .overlay(Circle().strokeBorder(.separator.opacity(0.35)))
        .motion(.smooth, value: center)
        .accessibilityHidden(true)
    }

    private var signed: Money {
        center.kind == .owes && center.subjectIsMe
            ? Money(minorUnits: -center.amount.minorUnits, currencyCode: center.amount.currencyCode)
            : center.amount
    }

    private var caption: String {
        let name = center.subject
        switch (center.kind, center.subjectIsMe) {
        case (.owed, true): return String(localized: "You are owed")
        case (.owes, true): return String(localized: "You owe")
        case (.owed, false): return String(localized: "\(name) is owed")
        case (.owes, false): return String(localized: "\(name) owes")
        default: return String(localized: "To settle")
        }
    }
}
