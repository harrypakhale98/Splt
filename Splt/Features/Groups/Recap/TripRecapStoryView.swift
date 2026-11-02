import Charts
import SpltCore
import SwiftUI

/// A full screen, swipeable look back at a group's spending: the total, day by day, the biggest
/// expense, who paid most, where it went and a sentence about it. It can be shared as a picture.
struct TripRecapStoryView: View {
    let group: SplitGroup
    let stats: RecapStats
    let members: [PersonID]
    /// A sentence from the on-device model, or the template when the model is not available.
    let summary: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var hidesAmounts = false
    @State private var sharedImage: Image?

    private var pages: [RecapPage] {
        var result: [RecapPage] = [.total, .days]
        if stats.biggest != nil { result.append(.biggest) }
        if stats.topPayer != nil { result.append(.payer) }
        if !stats.categories.isEmpty { result.append(.categories) }
        result.append(.summary)
        return result
    }

    var body: some View {
        let pages = pages
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            GroupHeroBackground(hues: RecapBackdrop.hues(for: pages[min(page, pages.count - 1)], group: group, stats: stats))
                .ignoresSafeArea()
                .motion(.smooth(duration: 0.6), value: page)
            Color(.systemBackground).opacity(0.2).ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, kind in
                    GeometryReader { proxy in
                        ScrollView {
                            content(for: kind, active: index == page)
                                .padding(.horizontal, 28)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                                .frame(maxWidth: .infinity, minHeight: max(proxy.size.height - 246, 200), alignment: .center)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .contentMargins(.top, 96, for: .scrollContent)
                        .contentMargins(.bottom, 150, for: .scrollContent)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { header(count: pages.count) }
        .overlay(alignment: .bottom) { footer }
        .task(id: hidesAmounts) { renderShareCard() }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: Chrome

    private func header(count: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? Color.primary.opacity(0.75) : Color.primary.opacity(0.15))
                        .frame(height: 3)
                }
            }
            .motion(.smooth, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(count)")
            HStack {
                Text("Recap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { hidePill; shareButton }
            VStack(spacing: 12) { hidePill; shareButton }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var hidePill: some View {
        GlassPill {
            Toggle("Hide Amounts", isOn: $hidesAmounts)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let sharedImage {
            ShareLink(item: sharedImage, preview: SharePreview(group.name, image: sharedImage)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func content(for kind: RecapPage, active: Bool) -> some View {
        switch kind {
        case .total: RecapTotalPage(group: group, stats: stats, hidesAmounts: hidesAmounts, active: active)
        case .days: RecapDaysPage(stats: stats, hidesAmounts: hidesAmounts, active: active)
        case .biggest: RecapBiggestPage(stats: stats, hidesAmounts: hidesAmounts, active: active)
        case .payer: RecapPayerPage(stats: stats, members: members, hidesAmounts: hidesAmounts, active: active)
        case .categories: RecapCategoriesPage(stats: stats, hidesAmounts: hidesAmounts, active: active)
        case .summary: RecapSummaryPage(group: group, stats: stats, summary: summary, active: active)
        }
    }

    private func renderShareCard() {
        let card = RecapShareCard(group: group, stats: stats, summary: summary, hidesAmounts: hidesAmounts)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage { sharedImage = Image(uiImage: image) }
    }
}

enum RecapPage: Hashable {
    case total
    case days
    case biggest
    case payer
    case categories
    case summary
}

/// Amounts as text, or dots when the person chose to hide them.
func recapAmount(_ money: Money, hidden: Bool, locale: Locale = .current) -> String {
    hidden ? "\u{2022}\u{2022}\u{2022}\u{2022}" : MoneyFormatting.string(money, locale: locale)
}
