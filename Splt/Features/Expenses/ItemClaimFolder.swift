import SwiftUI

/// Folds people's item picks into the expenses this person added. Sync folds what arrives; this
/// catches up when the app becomes active, for picks that arrived while a fold could not run.
/// Safe to run any number of times: nothing is written when no split would change.
private struct FoldsItemClaims: ViewModifier {
    @Environment(\.dataServices) private var services
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.task(id: phase) {
            guard phase == .active, let services else { return }
            _ = try? services.claims.foldClaims(inGroups: nil)
        }
    }
}

extension View {
    /// Folds item picks into your own expenses whenever the app becomes active.
    func foldsItemClaims() -> some View {
        modifier(FoldsItemClaims())
    }
}
