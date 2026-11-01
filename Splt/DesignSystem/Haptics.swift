import SwiftUI

extension View {
    /// Plays system feedback when `trigger` changes, unless the user turned haptics off in Settings.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(PreferenceHaptic(feedback: feedback, trigger: trigger))
    }
}

private struct PreferenceHaptic<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    private let preferences = Preferences()

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in
            preferences.hapticsEnabled
        }
    }
}
