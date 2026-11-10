import SwiftUI

/// Where the settle moment is: the arc contracts, a ring closes, the amount rolls, then the receipt settles.
struct SettleCeremony: Equatable {
    /// 0 for the full arc, 1 for a single point.
    var contraction: CGFloat = 0
    /// How much of the ring around the people is drawn.
    var ring: CGFloat = 0
    /// The amount has rolled to what remains.
    var rolled = false
    /// Everything has settled and the receipt shows.
    var finished = false

    static let idle = SettleCeremony()

    /// Plays one calm second on `state`. Reduce Motion gets a single cross fade. The haptic lands
    /// as the ring starts to close, so it confirms what you see rather than running ahead of it.
    /// These hand-tuned timings are the app's one celebration, so they don't use the `Motion` tokens.
    @MainActor
    static func play(on state: Binding<SettleCeremony>, reduceMotion: Bool) async {
        if reduceMotion {
            Haptics.play(.settle, reduceMotion: reduceMotion)
            withAnimation(.easeInOut(duration: 0.3)) {
                state.wrappedValue = SettleCeremony(contraction: 1, ring: 1, rolled: true, finished: true)
            }
            return
        }
        withAnimation(.easeIn(duration: 0.35)) { state.wrappedValue.contraction = 1 }
        try? await Task.sleep(for: .milliseconds(280))
        Haptics.play(.settle, reduceMotion: reduceMotion)
        withAnimation(.easeOut(duration: 0.4)) { state.wrappedValue.ring = 1 }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.smooth(duration: 0.6)) { state.wrappedValue.rolled = true }
        try? await Task.sleep(for: .milliseconds(560))
        withAnimation(Motion.settle) { state.wrappedValue.finished = true }
    }
}
