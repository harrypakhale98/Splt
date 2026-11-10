import SwiftUI

/// Card stock under one light from above: a bright sheet, a lit top edge and a soft neutral shadow.
/// Dark mode leans on the lighter sheet and the lit edge, because shadows barely show there.
/// Increase Contrast swaps the soft shadow and lit edge for a plain outline.
struct RaisedSurface: View {
    var radius: CGFloat = Depth.cardRadius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if contrast == .increased {
            shape.fill(Ink.sheet)
                .overlay { shape.strokeBorder(Ink.tertiary, lineWidth: 1.5) }
        } else if colorScheme == .dark {
            shape.fill(Ink.sheet)
                .overlay { shape.strokeBorder(Depth.topLight(strength: 0.07), lineWidth: 1) }
                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
        } else {
            shape.fill(Ink.sheet)
                .overlay { shape.strokeBorder(Depth.topLight(strength: 1), lineWidth: 1) }
                .shadow(color: Depth.warmShadow.opacity(0.06), radius: 0.5, y: 1)
                .shadow(color: Depth.warmShadow.opacity(0.06), radius: 8, y: 6)
        }
    }
}

/// Where a row sits in the card it belongs to.
enum RaisedPosition: Equatable {
    case only, first, middle, last

    init(index: Int, count: Int) {
        switch (index == 0, index == count - 1) {
        case (true, true): self = .only
        case (true, false): self = .first
        case (false, true): self = .last
        case (false, false): self = .middle
        }
    }

    var startsCard: Bool { self == .only || self == .first }
    var endsCard: Bool { self == .only || self == .last }
}

/// Puts a section's rows, whatever they turn out to be, on one raised card with hairlines between.
struct RaisedRows<Content: View>: View {
    var padding = Depth.rowPadding
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { rows in
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                row.raisedRow(RaisedPosition(index: index, count: rows.count), padding: padding)
            }
        }
    }
}

private struct RaisedRowBackground: View {
    let position: RaisedPosition
    let radius: CGFloat
    let dividerInset: CGFloat

    @Environment(\.displayScale) private var displayScale

    /// How far a card runs past the row it continues into. It only has to hide the corners.
    private var overrun: CGFloat { radius + 24 }

    var body: some View {
        RaisedSurface(radius: radius)
            .padding(.top, position.startsCard ? Depth.roomAbove : -overrun)
            .padding(.bottom, position.endsCard ? Depth.roomBelow : -overrun)
            .padding(.horizontal, Depth.pageMargin)
            .overlay(alignment: .bottom) {
                if !position.endsCard {
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(height: 1 / displayScale)
                        .padding(.leading, Depth.pageMargin + dividerInset)
                        .padding(.trailing, Depth.pageMargin)
                }
            }
            .clipped()
    }
}

private struct Letterpress: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if contrast == .increased {
            content
        } else if colorScheme == .dark {
            content.shadow(color: .black.opacity(0.9), radius: 0, y: -1)
        } else {
            content.shadow(color: .white.opacity(0.95), radius: 0, y: 1)
        }
    }
}

/// The shared parts of the app's one light source. See docs/design.md.
enum Depth {
    /// The distance a raised card keeps from the screen's edge.
    static let pageMargin: CGFloat = 16
    /// Empty row above and below a card, for its shadow to fall into.
    static let roomAbove: CGFloat = 4
    static let roomBelow: CGFloat = 12
    /// The space between a card's edge and the content of a row.
    static let rowPadding = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)

    /// The corner of every card, whether it is a `cardSurface()` or a run of `raisedRow()`s.
    static let cardRadius: CGFloat = 24
    /// The corner of smaller boxes on the page or on a card: buttons, tiles, chips, fields.
    static let controlRadius: CGFloat = 14
    /// The corner of a small picture, such as a receipt thumbnail.
    static let thumbnailRadius: CGFloat = 8

    /// Warm ink, so shadows look like they fall on paper rather than on grey.
    static let warmShadow = Color(red: 42.0 / 255, green: 33.0 / 255, blue: 24.0 / 255)

    /// White that fades out down an edge, for the lit top of a raised thing.
    static func topLight(strength: Double) -> LinearGradient {
        LinearGradient(
            colors: [.white.opacity(strength), .white.opacity(0)],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.3)
        )
    }
}

extension View {
    /// The rare raised surface: a sheet of card stock with gentle corners.
    func cardSurface(radius: CGFloat = Depth.cardRadius) -> some View {
        background { RaisedSurface(radius: radius) }
    }

    /// Raises a List row as a card, or as part of one when rows share a card through `RaisedRows`.
    ///
    /// List clips every row to its bounds, so the card is the row's background, drawn inset within
    /// the row with room around it for the shadow. A row that continues a card draws the card past
    /// its own edges and lets the clip cut it, which keeps the shadow unbroken down the sides.
    /// In a grouped List, also put `raisedSection()` on the section.
    func raisedRow(
        _ position: RaisedPosition = .only,
        radius: CGFloat = Depth.cardRadius,
        padding: EdgeInsets = Depth.rowPadding
    ) -> some View {
        listRowInsets(
            EdgeInsets(
                top: padding.top + (position.startsCard ? Depth.roomAbove : 0),
                leading: padding.leading + Depth.pageMargin,
                bottom: padding.bottom + (position.endsCard ? Depth.roomBelow : 0),
                trailing: padding.trailing + Depth.pageMargin
            )
        )
        .listRowBackground(RaisedRowBackground(position: position, radius: radius, dividerInset: padding.leading))
        .listRowSeparator(.hidden)
    }

    /// Lifts just the card when a raised row's context menu opens, rather than the whole row.
    /// Apply directly before `contextMenu`.
    func raisedContextMenuShape(padding: EdgeInsets = Depth.rowPadding) -> some View {
        // Growing a rounded rectangle grows its corner by the same amount, so start that much
        // tighter to land on the card's own corner.
        contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: max(0, Depth.cardRadius - padding.leading), style: .continuous)
                .inset(by: -padding.leading)
        )
    }

    /// Lets a section's `raisedRow()` reach the edges of a grouped List.
    func raisedSection() -> some View {
        listSectionMargins(.horizontal, 0)
            .listSectionSpacing(0)
    }

    /// Sets the one big number into the page, as if printed by letterpress: a lit lip where the
    /// paper dips below the ink. Increase Contrast leaves plain ink.
    func letterpress() -> some View {
        modifier(Letterpress())
    }

    /// Makes a person's disc read as a solid object: a soft highlight up and to the left, and a
    /// small shadow where it meets the page. Increase Contrast leaves the disc flat so its
    /// initials keep their exact contrast. Apply to the filled circle, beneath any initials.
    func solidDisc(diameter: CGFloat) -> some View {
        modifier(SolidDisc(diameter: diameter))
    }
}

private struct SolidDisc: ViewModifier {
    let diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if contrast == .increased {
            content
        } else {
            let isDark = colorScheme == .dark
            content
                .overlay {
                    Circle().fill(
                        RadialGradient(
                            stops: [
                                .init(color: .white.opacity(isDark ? 0.12 : 0.16), location: 0),
                                .init(color: .white.opacity(0), location: 0.5),
                                .init(color: .black.opacity(isDark ? 0.1 : 0.08), location: 1),
                            ],
                            center: UnitPoint(x: 0.32, y: 0.22),
                            startRadius: 0,
                            endRadius: diameter * 0.85
                        )
                    )
                }
                .shadow(
                    color: isDark ? Color.black.opacity(0.6) : Depth.warmShadow.opacity(0.22),
                    radius: max(0.5, diameter * 0.03),
                    y: max(0.5, diameter * 0.025)
                )
        }
    }
}
