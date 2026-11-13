import CloudKit
import SwiftUI
import UIKit

/// The system invite sheet for a group you shared: add people, set who can join, or stop sharing.
/// Present it in a sheet once `GroupSharingModel` has a share ready. A participant is never given it,
/// because its Remove Me option leaves the share without leaving the member list.
struct CloudSharingView: UIViewControllerRepresentable {
    let groupShare: GroupShare
    /// The group's picture, shown beside its name. See `GroupShareThumbnail`.
    var thumbnail: Data?
    var onSaved: () -> Void = {}
    var onStopped: () -> Void = {}
    var onFailure: (any Error) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: groupShare.share, container: groupShare.container)
        controller.availablePermissions = [.allowPublic, .allowPrivate, .allowReadWrite]
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

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            parent.thumbnail
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.onSaved()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopped()
        }
    }
}
