import SpltCore
import SwiftUI

/// The hues behind each recap page. Every page borrows the color of what it is about, so the story
/// has a sense of progress and the pages do not all look the same.
enum RecapBackdrop {
    /// Palette indexes, the strongest first.
    static func hues(for page: RecapPage, group: SplitGroup, stats: RecapStats) -> [Int] {
        let own = GroupHeroTint.hues(for: group)
        let dominant = own[0]
        switch page {
        case .total, .summary:
            return own
        case .days:
            return [(dominant + 2) % PersonPalette.count, dominant]
        case .biggest:
            guard let biggest = stats.biggest else { return own }
            return [categoryHue(biggest.category), dominant]
        case .payer:
            guard let payer = stats.topPayer else { return own }
            return [PersonPalette.index(for: payer.id, in: group.memberIDs), dominant]
        case .categories:
            guard let top = stats.categories.first else { return own }
            return [categoryHue(top.category), dominant]
        }
    }

    /// A stable hue for a category, from its name.
    static func categoryHue(_ category: ExpenseCategory) -> Int {
        PersonPalette.preferredIndex(forName: category.rawValue)
    }
}
