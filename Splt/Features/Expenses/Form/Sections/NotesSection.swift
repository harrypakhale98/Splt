import SwiftUI
import UIKit

struct NotesSection: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section(header: Text("Notes and Receipt").foregroundStyle(.legible)) {
            TextField("Notes", text: $model.note, prompt: Text("Add a note"), axis: .vertical)
                .lineLimit(1...6)

            if !model.receipt.isEmpty {
                ReceiptAttachmentRow(model: model)
            } else if model.isEditing {
                ReceiptActions(model: model)
                    .labelStyle(.titleAndIcon)
            }
            if model.isScanning {
                HStack {
                    ProgressView()
                    Text("Reading the receipt")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct ReceiptAttachmentRow: View {
    let model: ExpenseFormModel

    var body: some View {
        HStack {
            ReceiptThumbnail(
                fileName: model.receipt.storedFileName, pendingImage: model.receipt.pendingImage,
                store: model.dependencies.receipts
            )
            Text("Receipt attached")
            Spacer()
            Button("Remove", role: .destructive, action: model.clearReceipt)
                .buttonStyle(.borderless)
        }
    }
}
