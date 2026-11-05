import PhotosUI
import SpltCore
import SwiftUI

/// The small sheets behind the chips.
struct FormSheetContent: View {
    @Bindable var model: ExpenseFormModel
    let sheet: FormSheet
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm, action: onDone)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .category:
            CategorySheet(model: model, onDone: onDone).navigationTitle("Category")
        case .date:
            DateSheet(model: model).navigationTitle("Date")
        case .note:
            NoteSheet(model: model).navigationTitle("Note")
        case .receipt:
            ReceiptSheet(model: model, onDone: onDone).navigationTitle("Receipt")
        case .repeating:
            Form { RepeatSection(model: model) }.paperBackground().navigationTitle("Repeat")
        case .currency:
            ExpenseCurrencyPicker(
                selection: Binding(get: { model.currencyCode }, set: { model.changeCurrency(to: $0) }),
                groupCurrencyCode: model.groupCurrencyCode
            )
        case .more:
            MoreOptionsSheet(model: model).navigationTitle("More Options")
        }
    }

    static func detents(for sheet: FormSheet) -> Set<PresentationDetent> {
        switch sheet {
        case .category: [.medium, .large]
        case .date: [.medium]
        case .note: [.medium]
        case .receipt: [.medium]
        case .repeating: [.medium, .large]
        case .currency, .more: [.large]
        }
    }
}

private struct CategorySheet: View {
    let model: ExpenseFormModel
    var onDone: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    let selected = category == model.category
                    Button {
                        model.category = category
                        model.suggestedCategory = nil
                        onDone()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbolName).font(.title2)
                            Text(category.title).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                            if category == model.suggestedCategory, !selected {
                                Text("Suggested").font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? Ink.text : Ink.secondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Ink.text : Ink.hairline, lineWidth: selected ? 1.5 : 1)
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .paperBackground()
    }
}

private struct DateSheet: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        DatePicker("Date", selection: $model.date, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paperBackground()
    }
}

private struct NoteSheet: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        TextField("Add a note", text: $model.note, axis: .vertical)
            .lineLimit(3...10)
            .padding(16)
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.hairline) }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .paperBackground()
    }
}

private struct ReceiptSheet: View {
    let model: ExpenseFormModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if model.receipt.isEmpty {
                ContentUnavailableView {
                    Label("No Receipt", systemImage: "doc.text.viewfinder")
                } description: {
                    Text("Scan a receipt and the items fly onto the people who shared them.")
                }
            } else {
                ReceiptThumbnail(
                    fileName: model.receipt.storedFileName, pendingImage: model.receipt.pendingImage,
                    store: model.dependencies.receipts, side: 160
                )
                Button("Remove Receipt", role: .destructive) { model.clearReceipt() }
            }
            HStack(spacing: 12) {
                ReceiptActions(model: model)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderless)
            }
            if model.isScanning {
                HStack { ProgressView(); Text("Reading the receipt") }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .onChange(of: model.isScanning) { was, now in
            if was, !now { onDone() }
        }
    }
}

private struct MoreOptionsSheet: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Form {
            PayerSection(model: model)
            SplitSection(model: model)
            NotesSection(model: model)
        }
        .paperBackground()
    }
}
