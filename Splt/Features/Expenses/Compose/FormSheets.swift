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
            DateSheet(model: model, onDone: onDone).navigationTitle("Date")
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
        case .items:
            Form { ItemizedSplitEditor(model: model) }.paperBackground().navigationTitle("Items")
        }
    }

    static func detents(for sheet: FormSheet) -> Set<PresentationDetent> {
        switch sheet {
        case .category: [.medium, .large]
        case .date: [.medium, .large]
        case .note: [.medium]
        case .receipt: [.medium, .large]
        case .repeating, .items: [.medium, .large]
        case .currency, .more: [.large]
        }
    }
}

private struct CategorySheet: View {
    let model: ExpenseFormModel
    var onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes each category gets the full width, so its name does not break mid word.
    private var columns: [GridItem] {
        [typeSize.isAccessibilitySize ? GridItem(.flexible()) : GridItem(.adaptive(minimum: 96), spacing: 10)]
    }

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
                            Image(systemName: selected ? "checkmark.circle.fill" : category.symbolName).font(.title2)
                            Text(category.title).font(.caption.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.center)
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
                        RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous)
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
    var onDone: () -> Void

    var body: some View {
        // the calendar is taller than the medium height on small phones
        ScrollView {
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paperBackground()
        // Picking a day is the whole job, as with a category. Paging months leaves the date alone.
        .onChange(of: model.date) { onDone() }
    }
}

private struct NoteSheet: View {
    @Bindable var model: ExpenseFormModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Add a note", text: $model.note, axis: .vertical)
            .lineLimit(3...10)
            .focused($isFocused)
            .padding(16)
            .overlay { RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous).strokeBorder(Ink.hairline) }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .paperBackground()
            .onAppear { isFocused = true }
    }
}

private struct ReceiptSheet: View {
    let model: ExpenseFormModel
    var onDone: () -> Void

    @State private var sheetHeight: CGFloat = 0

    var body: some View {
        // centered when it fits; with a receipt on a small phone it is taller than the medium height, so it scrolls
        ScrollView {
            VStack(spacing: 20) {
                if model.receipt.isEmpty {
                    Text("Scan a receipt to split it by item.")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
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
            .frame(maxWidth: .infinity, minHeight: sheetHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { sheetHeight = $0 }
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
