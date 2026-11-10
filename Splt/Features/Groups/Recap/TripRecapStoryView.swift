import Charts
import SpltCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    /// Share pictures drawn ahead of time, one per way of showing amounts, so the share sheet opens at once.
    @State private var shareImages: [RecapShareImage.Key: Data] = [:]

    private var shareKey: RecapShareImage.Key {
        RecapShareImage.Key(hidesAmounts: hidesAmounts, summary: summary)
    }

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
            Ink.paper.ignoresSafeArea()
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
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                RecapBackdrop.strip(for: pages[min(page, pages.count - 1)], members: members, stats: stats)
                    .motion(.smooth, value: page)
                header(count: pages.count)
            }
        }
        .overlay(alignment: .bottom) { footer }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: Chrome

    private func header(count: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Rectangle()
                        .fill(index <= page ? Ink.text : Ink.hairline)
                        .frame(height: 2)
                }
            }
            .motion(.smooth, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(count)")
            HStack {
                Text("Recap")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
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
            HStack(spacing: 12) { hideToggle; shareButton }
            VStack(spacing: 12) { hideToggle; shareButton }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var hideToggle: some View {
        Toggle("Hide Amounts", isOn: $hidesAmounts)
            .font(.subheadline)
    }

    /// The card is drawn once, a moment after the button appears, and kept for each way of showing
    /// amounts. If someone shares before that, it is drawn when the share sheet asks for it.
    private var shareButton: some View {
        ShareLink(
            item: RecapShareImage(
                group: group, stats: stats, summary: summary, hidesAmounts: hidesAmounts, cached: shareImages[shareKey]
            ),
            preview: SharePreview(group.name)
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .task(id: shareKey) {
            let key = shareKey
            guard shareImages[key] == nil else { return }
            // let the cover finish opening and the first page settle before drawing
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, shareImages[key] == nil else { return }
            shareImages[key] = RecapShareImage.png(
                group: group, stats: stats, summary: key.summary, hidesAmounts: key.hidesAmounts
            )
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
}

/// The share card as a picture: the copy drawn ahead of time when there is one, otherwise drawn
/// when the share sheet asks for it.
struct RecapShareImage: Transferable, Sendable {
    /// What changes the picture while the recap is open.
    struct Key: Hashable, Sendable {
        var hidesAmounts: Bool
        var summary: String?
    }

    let group: SplitGroup
    let stats: RecapStats
    let summary: String?
    let hidesAmounts: Bool
    var cached: Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            if let cached = item.cached { return cached }
            return try await item.pngData()
        }
    }

    @MainActor
    private func pngData() throws -> Data {
        guard let data = Self.png(group: group, stats: stats, summary: summary, hidesAmounts: hidesAmounts) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// Draws the card at three times its size. ImageRenderer has to run on the main actor.
    @MainActor
    static func png(group: SplitGroup, stats: RecapStats, summary: String?, hidesAmounts: Bool) -> Data? {
        let card = RecapShareCard(group: group, stats: stats, summary: summary, hidesAmounts: hidesAmounts)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage?.pngData()
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

/// Amounts as text, or dots when the person chose to hide them. A refund keeps its minus sign.
func recapAmount(_ money: Money, hidden: Bool, locale: Locale = .current) -> String {
    hidden ? "\u{2022}\u{2022}\u{2022}\u{2022}" : MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
}

/// What VoiceOver says for an amount: the amount with its sign, or that it is hidden.
func recapSpokenAmount(_ money: Money, hidden: Bool, locale: Locale = .current) -> String {
    hidden ? String(localized: "Amount hidden") : MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
}
