import SwiftUI

/// Where the settle moment is: the arc contracts, a ring closes, the amount rolls, then the card settles.
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

    /// Plays one calm second on `state`. Reduce Motion gets a single cross fade.
    @MainActor
    static func play(on state: Binding<SettleCeremony>, reduceMotion: Bool) async {
        Haptics.play(.settle, reduceMotion: reduceMotion)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                state.wrappedValue = SettleCeremony(contraction: 1, ring: 1, rolled: true, finished: true)
            }
            return
        }
        withAnimation(.easeIn(duration: 0.35)) { state.wrappedValue.contraction = 1 }
        try? await Task.sleep(for: .milliseconds(280))
        withAnimation(.easeOut(duration: 0.4)) { state.wrappedValue.ring = 1 }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.smooth(duration: 0.6)) { state.wrappedValue.rolled = true }
        try? await Task.sleep(for: .milliseconds(560))
        withAnimation(.smooth) { state.wrappedValue.finished = true }
    }
}
