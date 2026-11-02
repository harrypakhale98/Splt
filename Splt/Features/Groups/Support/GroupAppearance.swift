import SpltCore
import SwiftUI

enum GroupAppearance {
    /// Stable per group, so a group keeps its color on every device.
    static func color(for id: GroupID) -> Color {
        AvatarStyle.color(for: id.description)
    }
}
