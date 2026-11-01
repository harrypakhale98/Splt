import CoreSpotlight
import SpltCore
import UIKit
import UniformTypeIdentifiers

/// How groups appear in Spotlight and how a tapped result is turned back into a group.
enum GroupSpotlight {
    static let domain = "com.harrypakhale.splt.groups"
    private static let prefix = "group."

    static func identifier(for id: GroupID) -> String {
        prefix + id.description
    }

    static func groupID(fromIdentifier identifier: String) -> GroupID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return GroupID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    /// The group a Spotlight result opens, or nil for an activity that is not one of ours.
    static func groupID(from activity: NSUserActivity) -> GroupID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return groupID(fromIdentifier: identifier)
    }

    /// Groups worth finding: the ones that are active and that people made themselves.
    static func isIndexed(_ group: SplitGroup) -> Bool {
        !group.isArchived && group.kind != .friend
    }

    static func item(for group: SplitGroup, memberNames: [String]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = group.name
        attributes.contentDescription = memberNames.isEmpty
            ? String(localized: "Splt group")
            : String(localized: "Splt group with \(memberNames.joined(separator: ", "))")
        attributes.keywords = [group.name, "Splt", "group"] + memberNames
        attributes.thumbnailData = thumbnail(symbol: group.symbol, color: UIColor(GroupAppearance.color(for: group.id)))
        let item = CSSearchableItem(
            uniqueIdentifier: identifier(for: group.id), domainIdentifier: domain, attributeSet: attributes
        )
        return item
    }

    private static func thumbnail(symbol: String, color: UIColor) -> Data? {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 28).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
            guard let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let origin = CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2)
            glyph.draw(at: origin)
        }
        return image.pngData()
    }
}
