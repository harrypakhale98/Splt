import CloudKit
import SwiftUI
import UIKit

/// The system invite sheet for a shared group: add people, set who can edit, stop sharing or leave.
/// Present it in a sheet once `GroupSharingModel` has a share ready.
struct CloudSharingView: UIViewControllerRepresentable {
    let groupShare: GroupShare
    var onSaved: () -> Void = {}
    var onStopped: () -> Void = {}
    var onFailure: (any Error) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: groupShare.share, container: groupShare.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.modalPresentationStyle = .formSheet
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        var parent: CloudSharingView

        init(parent: CloudSharingView) {
            self.parent = parent
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            parent.onFailure(error)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.groupShare.groupName
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopped()
        }
    }
}
