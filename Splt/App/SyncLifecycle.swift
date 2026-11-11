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
    @Bindable var router: Router

    @State private var failure: String?
    @State private var asksForNotifications = false

    func body(content: Content) -> some View {
        content
            .environment(\.groupSharing, SyncGroupSharing())
            .task {
                let runtime = SyncRuntime.shared
                runtime.onGroupJoined = { group in
                    router.open(.group(group.rawValue))
                    if let claim = runtime.takeClaim(for: group) {
                        // the invite was for someone added by name: ask first, notifications after
                        switch claim {
                        case .person(let person): router.joinClaim = JoinClaim(group: group, person: person)
                        case .askWho: router.joinClaim = JoinClaim(group: group, person: nil)
                        }
                    } else if NotificationAsk.shouldAsk() {
                        // joining is when changes from other people start to arrive
                        asksForNotifications = true
                    }
                }
                runtime.onInvitationFailed = { failure = $0 }
                if let services {
                    try? AccountProfile.shared.applyNameIfNoProfile(to: services.people)
                    await runtime.start(services: services)
                    #if DEBUG
                    showSampleJoin(services: services)
                    #endif
                }
            }
            .onChange(of: router.pendingJoin, initial: true) { _, invite in
                guard let invite else { return }
                router.pendingJoin = nil
                // someone who never chose a name joins with the one the group already knows them by, so
                // "Hana joined Lisbon Trip" says Hana from the first moment, on every device
                if let name = invite.name, let services {
                    try? AccountProfile.shared.takeInvitedName(name, people: services.people)
                }
                SyncRuntime.shared.receive(ShareInvitation(shareURL: invite.shareURL, claim: invite.joinAs))
            }
            .sheet(item: $router.joinClaim, onDismiss: {
                if NotificationAsk.shouldAsk() { asksForNotifications = true }
            }) { claim in
                if let services {
                    JoinGroupSheet(claim: claim, services: services)
                }
            }
            .notificationAsk(isPresented: $asksForNotifications)
            .alert("Couldn't Join Group", isPresented: failureBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    #if DEBUG
    /// `-sampledata -samplejoin` opens the sample trip as if Hana had just joined from her invite,
    /// to see the "which one are you" sheet without a second iCloud account.
    private func showSampleJoin(services: DataServices) {
        guard ProcessInfo.processInfo.arguments.contains("-samplejoin"),
              let trip = (try? services.groups.groups(includeArchived: false))?.first(where: { $0.name == "Lisbon Trip" }),
              let hana = (try? services.people.people(ids: trip.memberIDs))?.first(where: { $0.isPlaceholder })
        else { return }
        router.open(.group(trip.id.rawValue))
        let everyone = ProcessInfo.processInfo.arguments.contains("-samplejoineveryone")
        router.joinClaim = JoinClaim(group: trip.id, person: everyone ? nil : hana.id)
    }
    #endif

    private var failureBinding: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
