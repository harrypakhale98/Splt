import SpltCore
import SwiftUI

/// The strip of person colors along the top of each recap page. The pages sit on flat paper, so the
/// strip is the only color: everyone in the group, and on the payer page the top payer widest.
enum RecapBackdrop {
    /// One member's share of the strip.
    struct Segment: Equatable {
        var person: PersonID
        var weight: Double
    }

    static func segments(for page: RecapPage, members: [PersonID], stats: RecapStats) -> [Segment] {
        let topPayer = page == .payer ? stats.topPayer?.id : nil
        return members.map { Segment(person: $0, weight: $0 == topPayer ? Double(max(members.count, 2)) : 1) }
    }

    static func strip(for page: RecapPage, members: [PersonID], stats: RecapStats) -> some View {
        let segments = segments(for: page, members: members, stats: stats)
        return ShareStrip(
            colors: segments.map { PersonPalette.color(for: $0.person) },
            weights: segments.map(\.weight),
            height: 6
        )
    }
}
