import SwiftUI

extension View {
    /// For a screen that presents sheets from its own state. When a link is opened, `close` runs
    /// so those sheets go away, the way the router closes its own, and the link's screen is seen.
    /// A form with unsaved work keeps the link waiting instead, so this never throws typing away.
    func closingSheetsOnLink(_ close: @escaping () -> Void) -> some View {
        modifier(ClosingSheetsOnLink(close: close))
    }
}

private struct ClosingSheetsOnLink: ViewModifier {
    @Environment(Router.self) private var router: Router?
    let close: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: router?.openedLinks) { close() }
    }
}
