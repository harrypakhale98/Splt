import Foundation
import SpltCore

/// What a segment of the bar says, which depends on the method: percentages for Percent, share
/// counts for Shares, money for Exact and Adjust, money with "equal" for Equal.
struct SplitBarLabel: Hashable {
    var primary: String
    var secondary: String?
}

enum SplitBarLabels {
    static func make(
        method: SplitMethod, segment: SplitBarSegment, scale: Int64, wide: Bool, locale: Locale = .current
    ) -> SplitBarLabel {
        let money = segment.amount.map { MoneyFormatting.magnitudeString($0, locale: locale) }
        switch method {
        case .equal:
            return SplitBarLabel(primary: money ?? percent(segment, scale: scale, locale: locale), secondary: wide ? String(localized: "equal") : nil)
        case .percentage:
            return SplitBarLabel(primary: percent(segment, scale: scale, locale: locale), secondary: money)
        case .shares:
            let count = segment.weight
            let text = wide
                ? String(localized: "\(count) shares", comment: "A person's share count on the split bar")
                : "\(count)\u{00D7}"
            return SplitBarLabel(primary: text, secondary: money)
        case .exact, .itemized:
            return SplitBarLabel(primary: money ?? percent(segment, scale: scale, locale: locale), secondary: nil)
        case .adjustment:
            return SplitBarLabel(primary: money ?? percent(segment, scale: scale, locale: locale), secondary: adjustment(segment, locale: locale))
        }
    }

    static func percent(_ segment: SplitBarSegment, scale: Int64, locale: Locale) -> String {
        guard scale > 0 else { return "" }
        let value = Double(segment.weight) / Double(scale) * 100
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...1))) + "%"
    }

    private static func adjustment(_ segment: SplitBarSegment, locale: Locale) -> String? {
        guard let adjustment = segment.adjustment else { return nil }
        if adjustment.isZero { return String(localized: "even") }
        return MoneyFormatting.string(adjustment, locale: locale, showsSign: true)
    }
}
