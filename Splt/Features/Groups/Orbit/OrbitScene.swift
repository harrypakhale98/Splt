import CoreGraphics
import Foundation
import SpltCore

/// One payment on the ring, from the person who owes to the person who is owed.
struct OrbitTransfer: Hashable, Identifiable, Sendable {
    var debtor: PersonID
    var creditor: PersonID
    var amount: Money

    init(debtor: PersonID, creditor: PersonID, amount: Money) {
        self.debtor = debtor
        self.creditor = creditor
        self.amount = amount
    }

    init(_ debt: Debt) {
        self.init(debtor: debt.debtor, creditor: debt.creditor, amount: debt.amount)
    }

    var id: String { "\(debtor)>\(creditor)" }
    var debt: Debt { Debt(debtor: debtor, creditor: creditor, amount: amount) }

    func involves(_ person: PersonID) -> Bool {
        debtor == person || creditor == person
    }
}

/// Who is in the spotlight. Tapping a person fades everything that does not touch them.
enum OrbitFocus: Equatable, Sendable {
    case none
    case person(PersonID)

    var person: PersonID? {
        if case .person(let id) = self { return id }
        return nil
    }

    /// Focuses the person, or clears the focus if they already had it.
    mutating func toggle(_ id: PersonID) {
        self = self == .person(id) ? .none : .person(id)
    }
}

enum OrbitEmphasis: Equatable, Sendable {
    case normal
    case highlighted
    case dimmed

    var opacity: Double {
        switch self {
        case .normal: 0.9
        case .highlighted: 1
        case .dimmed: 0.14
        }
    }
}

/// What a tap landed on.
enum OrbitTarget: Equatable {
    case person(PersonID)
    case transfer(String)
    case nothing
}

/// A ring of people with the transfers between them, sized for one canvas.
struct OrbitScene {
    let layout: OrbitLayout
    let people: [PersonID]
    let transfers: [OrbitTransfer]
    /// The biggest amount, which gets the widest arc.
    let largest: Int64

    init(size: CGSize, people: [PersonID], transfers: [OrbitTransfer]) {
        layout = OrbitLayout(size: size, count: people.count)
        self.people = people
        self.transfers = transfers
        largest = transfers.map(\.amount.minorUnits).max() ?? 0
    }

    func index(of person: PersonID) -> Int? {
        people.firstIndex(of: person)
    }

    func position(of person: PersonID) -> CGPoint? {
        index(of: person).map { layout.positions[$0] }
    }

    func width(of transfer: OrbitTransfer) -> CGFloat {
        layout.arcWidth(amount: transfer.amount.minorUnits, largest: largest)
    }

    func arc(for transfer: OrbitTransfer) -> ArcGeometry? {
        guard let from = index(of: transfer.debtor), let to = index(of: transfer.creditor) else { return nil }
        return layout.arc(from: from, to: to, width: width(of: transfer))
    }

    /// Arcs ready to draw, widest first so thin ones stay visible on top.
    var arcs: [(transfer: OrbitTransfer, geometry: ArcGeometry)] {
        transfers.compactMap { transfer in arc(for: transfer).map { (transfer, $0) } }
            .sorted { $0.geometry.width > $1.geometry.width }
    }

    /// Where the amount pill of an arc goes: beside the arc, clear of the people and of the middle.
    /// It tries the middle of the arc first, then points either side of it, and when every spot is
    /// crowded it takes the one that sits farthest from the people.
    func pillPoint(for geometry: ArcGeometry) -> CGPoint {
        let clearOfPeople = layout.nodeRadius + 38
        var best: (point: CGPoint, room: CGFloat)?
        for t in [0.5, 0.42, 0.58, 0.34, 0.66, 0.27, 0.73] as [CGFloat] {
            let point = geometry.point(at: t)
            let dx = point.x - layout.center.x, dy = point.y - layout.center.y
            let length = max(hypot(dx, dy), 0.0001)
            for extra in [0, 16] as [CGFloat] {
                let offset = geometry.width / 2 + 14 + extra
                let candidate = CGPoint(x: point.x + dx / length * offset, y: point.y + dy / length * offset)
                let awayFromMiddle = hypot(candidate.x - layout.center.x, candidate.y - layout.center.y) >= layout.centerRadius + 14
                guard awayFromMiddle else { continue }
                let roomToPeople = layout.positions.map { hypot($0.x - candidate.x, $0.y - candidate.y) }.min() ?? .greatestFiniteMagnitude
                let labels = layout.labelStyle == .hidden ? [] : (0..<layout.count).map { layout.labelPosition($0) }
                let roomToLabels = labels.map { hypot($0.x - candidate.x, $0.y - candidate.y) + clearOfPeople - 30 }.min() ?? .greatestFiniteMagnitude
                let room = min(roomToPeople, roomToLabels)
                if room >= clearOfPeople { return candidate }
                if room > (best?.room ?? -1) { best = (candidate, room) }
            }
        }
        return best?.point ?? geometry.pillPoint(awayFrom: layout.center)
    }

    // MARK: Focus

    func emphasis(of transfer: OrbitTransfer, focus: OrbitFocus) -> OrbitEmphasis {
        guard let person = focus.person else { return .normal }
        return transfer.involves(person) ? .highlighted : .dimmed
    }

    func emphasis(of person: PersonID, focus: OrbitFocus) -> OrbitEmphasis {
        guard let focused = focus.person else { return .normal }
        if person == focused { return .highlighted }
        let connected = transfers.contains { $0.involves(focused) && $0.involves(person) }
        return connected ? .normal : .dimmed
    }

    // MARK: Taps

    /// People win over arcs, and every target is at least 44 points wide.
    func hit(at point: CGPoint) -> OrbitTarget {
        let reach = max(layout.nodeRadius, 22)
        var nearest: (id: PersonID, distance: CGFloat)?
        for (index, person) in people.enumerated() {
            let center = layout.positions[index]
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance <= reach, distance < (nearest?.distance ?? .greatestFiniteMagnitude) {
                nearest = (person, distance)
            }
        }
        if let nearest { return .person(nearest.id) }

        var best: (id: String, distance: CGFloat)?
        for (transfer, geometry) in arcs {
            let distance = geometry.distance(to: point)
            let slop = max(geometry.width / 2 + 6, 16)
            if distance <= slop, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (transfer.id, distance)
            }
        }
        return best.map { .transfer($0.id) } ?? .nothing
    }
}
