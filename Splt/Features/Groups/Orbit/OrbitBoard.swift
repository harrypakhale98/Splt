import Foundation
import SpltCore

struct OrbitNode: Identifiable, Equatable {
    var id: PersonID
    var name: String
    var isMe: Bool

    /// "Maya Chen" becomes "Maya".
    var firstName: String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
}

/// What the middle of the ring says.
struct OrbitCenter: Equatable {
    enum Kind: Equatable {
        case owed
        case owes
        case settled
        /// No profile to measure against, so it shows what is left to pay.
        case toSettle
    }

    var kind: Kind
    /// Who the amount is about: "You", or a name.
    var subject: String
    var subjectIsMe: Bool
    /// Always positive.
    var amount: Money
}

/// The people and payments of one currency, ready for the ring and for the list beside it.
struct OrbitBoard: Equatable {
    /// You first, so you sit at the top of the ring, then everyone else in group order.
    let nodes: [OrbitNode]
    let transfers: [OrbitTransfer]
    let currencyCode: String
    private let nets: [PersonID: Money]
    private let me: PersonID?

    /// `nets` is each person's balance in `currencyCode`, positive when they are owed.
    init(
        members: [Person],
        me: PersonID?,
        nets: [PersonID: Money],
        debts: [Debt],
        currencyCode: String,
        extraPeople: [PersonID: Person] = [:]
    ) {
        var ordered = members
        if let me, let index = ordered.firstIndex(where: { $0.id == me }), index != 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        let transfers = debts.filter { $0.amount.currencyCode == currencyCode }.map(OrbitTransfer.init)
        var known = Set(ordered.map(\.id))
        for id in transfers.flatMap({ [$0.debtor, $0.creditor] }) where known.insert(id).inserted {
            ordered.append(extraPeople[id] ?? Person(id: id, name: String(localized: "Someone")))
        }
        nodes = ordered.map { OrbitNode(id: $0.id, name: $0.name, isMe: $0.id == me) }
        self.transfers = transfers
        self.currencyCode = currencyCode.uppercased()
        self.nets = nets
        self.me = me
    }

    var people: [PersonID] { nodes.map(\.id) }
    var isSettled: Bool { transfers.isEmpty }

    func node(_ id: PersonID) -> OrbitNode? {
        nodes.first { $0.id == id }
    }

    func name(of id: PersonID) -> String {
        guard let node = node(id) else { return String(localized: "Someone") }
        return node.isMe ? String(localized: "You") : node.name
    }

    func net(of id: PersonID) -> Money {
        nets[id] ?? .zero(currencyCode: currencyCode)
    }

    private func shortName(of id: PersonID) -> String {
        guard let node = node(id) else { return String(localized: "Someone") }
        return node.isMe ? String(localized: "You") : node.firstName
    }

    func center(for focus: OrbitFocus) -> OrbitCenter {
        let zero = Money.zero(currencyCode: currencyCode)
        let subjectID = focus.person ?? me
        guard let subjectID else {
            let total = transfers.reduce(zero) { Money(minorUnits: $0.minorUnits + $1.amount.minorUnits, currencyCode: currencyCode) }
            return OrbitCenter(
                kind: total.isZero ? .settled : .toSettle, subject: "", subjectIsMe: false, amount: total
            )
        }
        let net = net(of: subjectID)
        let kind: OrbitCenter.Kind = net.minorUnits > 0 ? .owed : (net.minorUnits < 0 ? .owes : .settled)
        return OrbitCenter(
            kind: kind,
            subject: shortName(of: subjectID),
            subjectIsMe: subjectID == me,
            amount: Money(minorUnits: abs(net.minorUnits), currencyCode: currencyCode)
        )
    }

    /// "Sam owes you", "You owe Priya", "Sam owes Priya".
    func sentence(for transfer: OrbitTransfer) -> String {
        let debtor = name(of: transfer.debtor)
        let creditor = name(of: transfer.creditor)
        if transfer.debtor == me { return String(localized: "You owe \(creditor)") }
        if transfer.creditor == me { return String(localized: "\(debtor) owes you") }
        return String(localized: "\(debtor) owes \(creditor)")
    }

    /// The sentence with its amount, for VoiceOver.
    func spoken(_ transfer: OrbitTransfer, locale: Locale = .current) -> String {
        let amount = MoneyFormatting.magnitudeString(transfer.amount, locale: locale)
        return "\(sentence(for: transfer)) \(amount)"
    }

    /// One description of the whole ring for VoiceOver.
    func summary(locale: Locale = .current) -> String {
        if transfers.isEmpty { return String(localized: "Everyone is settled up") }
        let count = transfers.count
        return String(AttributedString(localized: "^[\(count) payment](inflect: true) would settle this group.").characters)
    }
}
