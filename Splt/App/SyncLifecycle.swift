import SpltCore
import SwiftUI

extension View {
    /// Starts sync with the app's data, opens groups that arrive through an invitation and
    /// provides the sharing the group screens use.
    func syncLifecycle(services: DataServices?, router: Router) -> some View {
        modifier(SyncLifecycle(services: services, router: router))
    }
}

private struct SyncLifecycle: ViewModifier {
    let services: DataServices?
    let router: Router

    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .environment(\.groupSharing, SyncGroupSharing())
            .task {
                let runtime = SyncRuntime.shared
                runtime.onGroupJoined = { router.open(.group($0.rawValue)) }
                runtime.onInvitationFailed = { failure = $0 }
                if let services {
                    try? AccountProfile.shared.applyNameIfNoProfile(to: services.people)
                    await runtime.start(services: services)
                }
            }
            .alert("Couldn't Join Group", isPresented: failureBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
