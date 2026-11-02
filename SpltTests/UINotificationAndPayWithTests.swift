import Foundation
import SpltCore
import Testing
import UserNotifications
@testable import Splt

@Suite("Notification destinations")
struct UINotificationDestinationTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func reminderLinksAreFollowed() {
        let link = DeepLink.friend(id).url.absoluteString
        let url = NotificationCoordinator.destination(
            identifier: "reminder.x", userInfo: [SystemReminderCenter.linkKey: link]
        )
        #expect(url == DeepLink.friend(id).url)
    }

    @Test func linksOutsideTheAppAreIgnored() {
        let url = NotificationCoordinator.destination(
            identifier: "reminder.x", userInfo: [SystemReminderCenter.linkKey: "https://example.com"]
        )
        #expect(url == nil)
    }

    @Test func changeNotificationsOpenActivity() {
        #expect(NotificationCoordinator.destination(identifier: "splt.activity.abc", userInfo: [:]) == DeepLink.activity.url)
        #expect(NotificationCoordinator.destination(identifier: "splt.summary.abc", userInfo: [:]) == DeepLink.activity.url)
        #expect(NotificationCoordinator.destination(identifier: "other", userInfo: [:]) == nil)
    }

    @Test func activityLinkRoundTrips() {
        #expect(DeepLink(url: DeepLink.activity.url) == .activity)
    }
}

@MainActor
@Suite("Notification coordinator")
struct UINotificationCoordinatorTests {
    @Test func installTakesOverAsTheDelegate() {
        let coordinator = NotificationCoordinator()
        let center = UNUserNotificationCenter.current()
        let before = center.delegate
        coordinator.install(on: center)
        #expect(center.delegate === coordinator)
        center.delegate = before
    }
}

@MainActor
private final class FakeOpener: URLOpening {
    var installed: Set<String>
    var opened: [URL] = []
    var openSucceeds = true

    init(installed: Set<String>) {
        self.installed = installed
    }

    func canOpen(_ url: URL) -> Bool { installed.contains(url.scheme ?? "") }

    func open(_ url: URL) async -> Bool {
        opened.append(url)
        return openSucceeds
    }
}

@MainActor
@Suite("Pay with")
struct UIPayWithTests {
    private let venmo = URL(string: "venmo://paycharge?amount=5")!

    @Test func opensWhenTheAppIsInstalled() async {
        let opener = FakeOpener(installed: ["venmo"])
        let outcome = await PayWithLauncher(opener: opener).launch(venmo)
        #expect(outcome == .opened)
        #expect(opener.opened == [venmo])
    }

    @Test func saysUnavailableWhenTheAppIsMissing() async {
        let opener = FakeOpener(installed: [])
        let outcome = await PayWithLauncher(opener: opener).launch(venmo)
        #expect(outcome == .unavailable)
        #expect(opener.opened.isEmpty)
    }

    @Test func saysUnavailableWhenTheSystemRefuses() async {
        let opener = FakeOpener(installed: ["venmo"])
        opener.openSucceeds = false
        #expect(await PayWithLauncher(opener: opener).launch(venmo) == .unavailable)
    }

    @Test func methodsThatOpenAnAppOrPageHaveASiteOrNone() {
        #expect(SettleMethod.venmo.websiteURL?.scheme == "https")
        #expect(SettleMethod.upi.websiteURL == nil)
        #expect(SettleMethod.cash.websiteURL == nil)
        for method in SettleMethod.allCases {
            if let site = method.websiteURL { #expect(site.scheme == "https") }
        }
    }
}
