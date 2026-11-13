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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    init(board: OrbitBoard, members: [PersonID], initialFocus: OrbitFocus = .none, onSettle: @escaping (Debt) -> Void) {
        self.board = board
        self.members = members
        self.onSettle = onSettle
        _focus = State(initialValue: initialFocus)
    }

    var body: some View {
        let _ = PersonColorRevision.shared.value
        let colors = OrbitColors(members: members)
        GeometryReader { proxy in
            let scene = OrbitScene(size: proxy.size, people: board.people, transfers: board.transfers)
            ZStack {
                ring(scene)
                arcLayer(scene: scene, colors: colors)
                nodeLayer(scene: scene, colors: colors)
                amountLabels(scene: scene)
                OrbitCenterView(
                    center: board.center(for: focus), diameter: scene.layout.centerRadius * 2,
                    moreCount: pairs.isEmpty ? pillArcs(scene).hidden : 0
                )
                .position(scene.layout.center)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                // a gesture's x runs from the left even where the ring is mirrored
                let x = layoutDirection == .rightToLeft ? proxy.size.width - value.location.x : value.location.x
                handle(scene.hit(at: CGPoint(x: x, y: value.location.y)))
            })
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .motion(Motion.snappy, value: focus)
        .onChange(of: board.transfers) { old, new in startMorph(from: old, to: new) }
        .onChange(of: board.nodes) { focus = .none }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(board.summary(locale: locale))
        .accessibilityChildren { accessibleChildren }
    }

    // MARK: Layers

    private func ring(_ scene: OrbitScene) -> some View {
        Circle()
            .strokeBorder(Ink.hairline, lineWidth: 1)
            .frame(width: scene.layout.ringRadius * 2, height: scene.layout.ringRadius * 2)
            .position(scene.layout.center)
    }

    @ViewBuilder
    private func arcLayer(scene: OrbitScene, colors: OrbitColors) -> some View {
        if pairs.isEmpty {
            ForEach(scene.arcs, id: \.transfer.id) { transfer, geometry in
                OrbitArcShape(from: geometry, to: geometry, progress: 1, headScale: headScale)
                    .fill(colors.ribbon(for: transfer))
                    .opacity(arcOpacity(scene.emphasis(of: transfer, focus: focus)))
                    .motionTransition(.opacity)
            }
        } else {
            let old = OrbitScene(size: scene.layout.size, people: board.people, transfers: previous)
            ForEach(pairs) { pair in
                if let shapes = OrbitMorph.geometry(for: pair, in: old, target: scene) {
                    // an arc that merges blends from the old debtor's color to the new one's and keeps
                    // the focus dimming of each end, so nothing snaps while it moves
                    let first = pair.start ?? pair.end
                    let last = pair.end ?? pair.start
                    let fromOpacity = pair.start.map { arcOpacity(old.emphasis(of: $0, focus: focus)) }
                    let toOpacity = pair.end.map { arcOpacity(scene.emphasis(of: $0, focus: focus)) }
                    OrbitMorphArc(
                        from: shapes.from, to: shapes.to,
                        fromColor: first.map { colors.ribbon(for: $0) } ?? Ink.tertiary,
                        toColor: last.map { colors.ribbon(for: $0) } ?? Ink.tertiary,
                        fromOpacity: fromOpacity ?? toOpacity ?? 0.75,
                        toOpacity: toOpacity ?? fromOpacity ?? 0.75,
                        headScale: headScale,
                        progress: progress
                    )
                }
            }
        }
    }

    private var headScale: CGFloat { contrast == .increased ? 1.3 : 1 }

    private func arcOpacity(_ emphasis: OrbitEmphasis) -> Double {
        emphasis.opacity(increasedContrast: contrast == .increased)
    }

    /// The arcs that get an amount pill: the only one when nobody is focused, or the focused
    /// person's, largest first and at most `OrbitPills.limit`. `hidden` counts the rest.
    private func pillArcs(_ scene: OrbitScene) -> (shown: [(transfer: OrbitTransfer, geometry: ArcGeometry)], hidden: Int) {
        let visible = scene.arcs.filter { arc in
            let emphasis = scene.emphasis(of: arc.transfer, focus: focus)
            return board.transfers.count == 1 && focus == .none || emphasis == .highlighted
        }
        let shown = Array(visible.prefix(OrbitPills.limit))
        return (shown, visible.count - shown.count)
    }

    @ViewBuilder
    private func amountLabels(scene: OrbitScene) -> some View {
        let visible = pillArcs(scene).shown
        if pairs.isEmpty, !visible.isEmpty {
            let metrics = OrbitTextMetrics(dynamicTypeSize: typeSize)
            let requests = visible.map { arc -> OrbitPills.Request in
                let full = MoneyFormatting.string(arc.transfer.amount, locale: locale)
                let compact = OrbitPills.compactText(arc.transfer.amount, locale: locale)
                return OrbitPills.Request(
                    id: arc.transfer.id, geometry: arc.geometry, full: full, compact: compact,
                    fullSize: OrbitPills.pill(around: metrics.size(of: full, style: .caption1, monospacedDigits: true)),
                    compactSize: OrbitPills.pill(
                        around: metrics.size(of: compact, style: .caption2, monospacedDigits: true), compact: true
                    )
                )
            }
            let placements = OrbitPills.place(requests, in: scene.layout, labelSizes: labelSizes(scene.layout, metrics: metrics))
            ForEach(requests, id: \.id) { request in
                if let placement = placements[request.id] {
                    Text(placement.isCompact ? request.compact : request.full)
                        .font((placement.isCompact ? Font.caption2 : Font.caption).monospacedDigit())
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: placement.rect.width, height: placement.rect.height)
                        .background(Ink.paper, in: .capsule)
                        .overlay(Capsule().strokeBorder(Ink.hairline))
                        .position(placement.center)
                        .motionTransition(.opacity)
                        .allowsHitTesting(false)
                }
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
                    .solidDisc(diameter: layout.nodeRadius * 2)
                Text(AvatarStyle.initials(for: node.name))
                    .font(.system(size: layout.nodeRadius * 0.8, weight: .medium))
                    .foregroundStyle(colors.ink(for: node.id))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if focus.person == node.id {
                    Circle()
                        .strokeBorder(Ink.paper, lineWidth: 2)
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
                    .truncationMode(.tail)
                    .foregroundStyle(emphasis == .dimmed ? Ink.tertiary : Ink.secondary)
                    .frame(maxWidth: layout.labelMaxWidth(index))
                    .position(layout.labelPosition(index))
            }
        }
    }

    /// The size each name label takes on screen, capped as it is drawn, or zero where no label
    /// shows, so pills keep clear of long names.
    private func labelSizes(_ layout: OrbitLayout, metrics: OrbitTextMetrics) -> [CGSize] {
        board.nodes.enumerated().map { index, node in
            guard showsLabel(for: node, layout: layout) else { return .zero }
            let measured = layout.labelStyle == .name
                ? metrics.size(of: label(for: node, layout: layout), style: .caption1, weight: .medium)
                : metrics.size(of: label(for: node, layout: layout), style: .caption2)
            return CGSize(width: min(measured.width, layout.labelMaxWidth(index)), height: measured.height)
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
        // the guard above already skips the morph when motion is reduced; the completion clears it
        withAnimation(Motion.reveal) {
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

/// The big number in the middle: your balance, or the balance of whoever is focused. The figure is
/// sized from the width of the disc so it never ends in an ellipsis, and falls back to whole units
/// when even that would be too small to read.
struct OrbitCenterView: View {
    let center: OrbitCenter
    let diameter: CGFloat
    /// Transfers of the focused person that have no pill on the ring.
    var moreCount = 0

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = HeroAmount.baseSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 2) {
            switch center.kind {
            case .settled:
                Group {
                    if center.subjectIsMe || center.subject.isEmpty {
                        Text("All settled up")
                    } else {
                        Text("\(center.subject) is settled up")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            default:
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                figure
                if moreCount > 0 {
                    Text("+\(moreCount) more")
                        .font(.caption2)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(width: diameter * 0.84)
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(Ink.hairline))
        .motion(Motion.smooth, value: center)
        .accessibilityHidden(true)
    }

    /// The amount without a sign: the caption above it says which way the money goes.
    private var figure: some View {
        let width = diameter * 0.84
        let preferred = min(heroSize, HeroAmount.maxSize, diameter * 0.42)
        let magnitude = Money(minorUnits: Int64(clamping: center.amount.minorUnits.magnitude), currencyCode: center.amount.currencyCode)
        let full = MoneyFormatting.magnitudeString(magnitude, locale: locale)
        let compact = OrbitPills.compactText(magnitude, locale: locale)
        let fullSize = Self.fittedSize(for: full, width: width, preferred: preferred)
        let useCompact = fullSize < Self.smallestFigure && compact != full
        return Text(useCompact ? compact : full)
            .font(Typeface.hero(size: useCompact ? Self.fittedSize(for: compact, width: width, preferred: preferred) : fullSize))
            .monospacedDigit()
            .foregroundStyle(Ink.text)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .contentTransition(.numericText(value: Double(signed.minorUnits)))
            .letterpress()
    }

    /// Below this the full amount gives way to whole units.
    static let smallestFigure: CGFloat = 16

    /// The largest serif size, up to `preferred`, at which `text` fits in `width`. Digits are about
    /// six tenths of the size wide, separators half that, and anything else a little wider.
    static func fittedSize(for text: String, width: CGFloat, preferred: CGFloat) -> CGFloat {
        let ems = text.reduce(CGFloat(0)) { sum, character in
            if character.isNumber { return sum + 0.6 }
            if character == "." || character == "," || character.isWhitespace || character == "'" { return sum + 0.3 }
            return sum + 0.7
        }
        guard ems > 0, width > 0 else { return preferred }
        return min(preferred, width / ems)
    }

    private var signed: Money {
        center.kind == .owes && center.subjectIsMe
            ? Money(minorUnits: -center.amount.minorUnits, currencyCode: center.amount.currencyCode)
            : center.amount
    }

    private var caption: String {
        let name = center.subject
        switch (center.kind, center.subjectIsMe) {
        case (.owed, true): return String(localized: "You're owed")
        case (.owes, true): return String(localized: "You owe")
        case (.owed, false): return String(localized: "\(name) is owed")
        case (.owes, false): return String(localized: "\(name) owes")
        default: return String(localized: "To settle")
        }
    }
}

/// Measures text the way the ring draws it, capped at the ring's largest text size, so pills and
/// labels are laid out from their real widths instead of a guess.
@MainActor
struct OrbitTextMetrics {
    private let traits: UITraitCollection

    init(dynamicTypeSize: DynamicTypeSize) {
        traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(dynamicTypeSize, .xLarge)))
    }

    func size(
        of text: String, style: UIFont.TextStyle, weight: UIFont.Weight = .regular, monospacedDigits: Bool = false
    ) -> CGSize {
        let pointSize = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
        let font = monospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weight)
            : UIFont.systemFont(ofSize: pointSize, weight: weight)
        let bounds = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(bounds.width), height: ceil(font.lineHeight))
    }
}
