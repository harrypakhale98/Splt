import SpltCore
import SwiftUI

/// The top of a group, straight on paper: its name, beside a small cover photo if it has one, its dates
/// and people, your balance in big numerals, a strip of its members and the Settle Up button when there is something to settle.
struct GroupHeroSection: View {
    let group: SplitGroup
    let members: [Person]
    let totals: BalanceTotals
    let canSettle: Bool
    /// What each person paid in the group's main currency, which sizes the strip.
    var paid: [GroupTotals.PersonAmount] = []
    let onSettleUp: () -> Void

    @Environment(\.locale) private var locale
    @State private var showsCover = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                identity
                balance
                if !members.isEmpty {
                    let strip = PaidStrip(members: members.map(\.id), paid: paid)
                    ShareStrip(people: strip.people, members: members.map(\.id), weights: strip.weights, isGrooved: true)
                        .accessibilityHidden(true)
                        // the strip is only a few points tall, so VoiceOver gets a full-height stand-in
                        .overlay {
                            Color.clear
                                .frame(height: 44)
                                .accessibilityElement()
                                .accessibilityLabel(strip.spoken(names: names))
                        }
                }
                if canSettle {
                    Button(action: onSettleUp) {
                        Text("Settle Up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var identity: some View {
        let cover = shownCover
        return VStack(alignment: .leading, spacing: 4) {
            if let cover {
                HStack(spacing: 10) {
                    Button { showsCover = true } label: {
                        CoverThumbnail(fileName: cover, store: .covers, side: 32) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    // VoiceOver reaches the photo through the header's action instead
                    .accessibilityHidden(true)
                    title
                }
            } else {
                title
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if cover != nil {
                Button("View Cover Photo") { showsCover = true }
            }
        }
        .fullScreenCover(isPresented: $showsCover) {
            if let cover { CoverPhotoViewer(fileName: cover) }
        }
    }

    private var title: some View {
        Text(group.name)
            .font(Typeface.title)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
    }

    /// The cover, once its photo is on this device. Until then the header is the one without a photo.
    private var shownCover: String? {
        group.shownCoverFileName.flatMap { PhotoStore.covers.exists($0) ? $0 : nil }
    }

    private var subtitle: String {
        let count = members.count
        let people = String(AttributedString(localized: "^[\(count) person](inflect: true)").characters)
        if let start = group.tripStart, let end = group.tripEnd {
            let range = (start..<max(end, start.addingTimeInterval(1))).formatted(.interval.day().month(.abbreviated).locale(locale))
            return "\(range) · \(people)"
        }
        return "\(group.currencyCode) · \(people)"
    }

    @ViewBuilder
    private var balance: some View {
        if totals.isSettled {
            Text("All settled up")
                .font(Typeface.heading)
        } else {
            let lines = balanceLines
            let main = lines.first { $0.money.currencyCode == group.currencyCode } ?? lines[0]
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(main.caption)
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                    HeroAmount(main.money, showsSign: false)
                }
                .accessibilityElement(children: .combine)
                // one big figure per screen: other currencies sit under it as quiet lines
                ForEach(lines.filter { $0.id != main.id }) { line in
                    HStack(spacing: 6) {
                        Text(line.caption)
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                        Text(MoneyFormatting.string(line.money, locale: locale))
                            .font(Typeface.figure)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Every currency you are owed or owe, owed first. Not empty unless you are settled.
    private var balanceLines: [HeroLine] {
        totals.owedToYou.map { HeroLine(isOwed: true, money: $0) } + totals.youOwe.map { HeroLine(isOwed: false, money: $0) }
    }
}

private struct HeroLine: Identifiable {
    var isOwed: Bool
    var money: Money

    var id: String { "\(isOwed)-\(money.currencyCode)" }
    var caption: LocalizedStringKey { isOwed ? "You're owed" : "You owe" }
}

#if DEBUG
#Preview("Owed") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    let members = trip.flatMap { try? services.people.people(ids: $0.memberIDs) } ?? []
    List {
        if let trip {
            GroupHeroSection(
                group: trip, members: members,
                totals: BalanceTotals(owedToYou: [Money(minorUnits: 21_460, currencyCode: "EUR")], youOwe: []),
                canSettle: true, onSettleUp: {}
            )
        }
    }
    .paperBackground()
}
#endif

private extension GroupHeroSection {
    var names: [PersonID: String] {
        Dictionary(members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The group's strip as a small chart: each person's slice is what they paid, largest first.
/// Someone who paid nothing keeps a thin sliver, so the strip still shows everyone in the group.
/// With no spending yet, everyone gets an equal slice.
struct PaidStrip: Equatable {
    let people: [PersonID]
    let weights: [Double]?
    private let shares: [PersonID: Double]

    /// The sliver's size, as a share of what everyone paid.
    static let sliver = 0.02

    init(members: [PersonID], paid: [GroupTotals.PersonAmount]) {
        var amounts: [PersonID: Double] = [:]
        for entry in paid where members.contains(entry.personID) {
            amounts[entry.personID, default: 0] += Double(max(entry.paid.minorUnits, 0))
        }
        let total = amounts.values.reduce(0, +)
        guard total > 0 else {
            people = members
            weights = nil
            shares = [:]
            return
        }
        let order = Dictionary(members.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        people = members.sorted {
            let left = amounts[$0] ?? 0, right = amounts[$1] ?? 0
            return left != right ? left > right : (order[$0] ?? 0) < (order[$1] ?? 0)
        }
        weights = people.map { max(amounts[$0] ?? 0, total * Self.sliver) }
        shares = amounts.mapValues { $0 / total }
    }

    /// "Paid: Maya Chen 55%, You 16%, …", or nil-safe plain list when nothing is spent yet.
    func spoken(names: [PersonID: String]) -> String {
        guard weights != nil else {
            return ListFormatter.localizedString(byJoining: people.map { names[$0] ?? "" })
        }
        let parts = people.map { person -> String in
            let percent = Int(((shares[person] ?? 0) * 100).rounded())
            return String(localized: "\(names[person] ?? "") \(percent)%")
        }
        return String(localized: "Paid: \(parts.joined(separator: ", "))")
    }
}
