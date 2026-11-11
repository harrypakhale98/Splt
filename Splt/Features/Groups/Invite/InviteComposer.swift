import MessageUI
import SwiftUI

/// Apple's own Messages or Mail screen, addressed and filled in, for sending an invite straight to the
/// number or email address someone was added with. Nothing is sent until the person taps Send there.
struct InviteComposer: UIViewControllerRepresentable {
    let recipient: InvitePersonModel.Recipient
    let subject: String
    let body: String
    var onFinish: () -> Void

    /// False on a device that can't send texts or has no mail account, and on the simulator. The share
    /// sheet is used then.
    static func canSend(to recipient: InvitePersonModel.Recipient) -> Bool {
        switch recipient {
        case .phone: MFMessageComposeViewController.canSendText()
        case .email: MFMailComposeViewController.canSendMail()
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        switch recipient {
        case .phone(let number):
            let controller = MFMessageComposeViewController()
            controller.recipients = [number]
            controller.body = body
            controller.messageComposeDelegate = context.coordinator
            return controller
        case .email(let address):
            let controller = MFMailComposeViewController()
            controller.setToRecipients([address])
            controller.setSubject(subject)
            controller.setMessageBody(body, isHTML: false)
            controller.mailComposeDelegate = context.coordinator
            return controller
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            onFinish()
        }
    }
}
