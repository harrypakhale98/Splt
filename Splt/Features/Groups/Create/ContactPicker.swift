import Contacts
import ContactsUI
import SwiftUI

/// The system contact picker. It needs no Contacts permission because the person chooses what to share.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: ([MemberDraft]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: ([MemberDraft]) -> Void

        init(onPick: @escaping ([MemberDraft]) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts.compactMap(Self.draft))
        }

        private static func draft(for contact: CNContact) -> MemberDraft? {
            let name = CNContactFormatter.string(from: contact, style: .fullName)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let hint = contact.emailAddresses.first.map { $0.value as String }
                ?? contact.phoneNumbers.first?.value.stringValue
            return MemberDraft(name: name, contactHint: hint)
        }
    }
}
