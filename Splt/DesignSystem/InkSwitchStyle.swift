import SwiftUI

/// The system switch, with an on track that stays visible in dark mode. Set once at the root, so
/// every switch in the app gets it; a toggle that asks for another style, such as a button, keeps it.
struct InkSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(Ink.switchOn)
    }
}
