import SpltCore
import SwiftUI
import Translation

/// Everything about one expense. Pushed with `Route.expense`.
struct ExpenseDetailView: View {
    let expenseID: ExpenseID

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            ExpenseDetailScreen(expenseID: expenseID, services: services)
        } else {
            EmptyStateView.dataUnavailable
                .navigationTitle("Expense")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ExpenseDetailScreen: View {
    @State private var model: ExpenseDetailModel
    @State private var showsEditor = false
    @State private var showsDuplicate = false
    @State private var confirmsDelete = false
    @State private var translating: String?
    @State private var deleteCount = 0

    init(expenseID: ExpenseID, services: DataServices) {
        _model = State(initialValue: ExpenseDetailModel(expenseID: expenseID, services: services))
    }

    var body: some View {
        Group {
            if model.failed {
                EmptyStateView(
                    title: "Expense Not Found",
                    systemImage: "questionmark.circle",
                    description: "This expense may have been removed."
                )
            } else if let expense = model.expense {
                content(expense)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.expense?.title ?? String(localized: "Expense"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .confirmationDialog("Delete this expense?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive) {
                model.delete()
                deleteCount += 1
                AccessibilityNotification.Announcement(String(localized: "Expense deleted")).post()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves everyone's balances. You can undo this right after.")
        }
        .alert("Couldn't Finish", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .sheet(isPresented: $showsEditor, onDismiss: model.reload) {
            ExpenseFormView(mode: .edit(model.expenseID))
        }
        .sheet(isPresented: $showsDuplicate) {
            if let groupID = model.expense?.groupID {
                ExpenseFormView(mode: .add(groupID: groupID, prefill: model.duplicateDraft))
            }
        }
        .translationPresentation(isPresented: Binding(
            get: { translating != nil }, set: { if !$0 { translating = nil } }
        ), text: translating ?? "")
        .haptic(.warning, trigger: deleteCount)
    }

    private func content(_ expense: Expense) -> some View {
        List {
            ExpenseHeaderSection(model: model, expense: expense)
            ShareBreakdownSection(model: model, expense: expense)
            PaidBySection(model: model)
            ReceiptSection(model: model)
            if !expense.note.isEmpty {
                Section {
                    RaisedRows { Text(expense.note) }
                } header: {
                    SectionHeader("Notes")
                }
            }
            if model.details?.extras.recurringExpenseID != nil, let groupID = expense.groupID {
                Section {
                    RaisedRows {
                        NavigationLink(value: Route.recurringExpenses(groupID.rawValue)) {
                            Label("Part of a recurring expense", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    SectionHeader("Repeats")
                }
            }
            CommentsSection(model: model) { translating = $0 }
            ExpenseHistorySection(model: model)
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .safeAreaBar(edge: .bottom) {
            if model.isDeleted {
                DeletedBanner { model.undoDelete() }
                    .motionTransition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(Motion.settle, value: model.isDeleted)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let expense = model.expense, !model.isDeleted {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showsEditor = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { showsDuplicate = true }
                    ShareLink(item: model.shareText, subject: Text(expense.title)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }
}

private struct DeletedBanner: View {
    let undo: () -> Void

    var body: some View {
        HStack {
            Label("Expense deleted", systemImage: "trash")
            Spacer(minLength: 8)
            Button("Undo", action: undo)
                .font(.body.weight(.medium))
                .frame(minHeight: 44)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .cardSurface()
        .padding(.horizontal, Depth.pageMargin)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Shared equally") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { ExpenseDetailView(expenseID: scene.expense("airbnb")) }
        .environment(\.dataServices, scene.services)
}

#Preview("Itemized") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { ExpenseDetailView(expenseID: scene.expense("seafood")) }
        .environment(\.dataServices, scene.services)
}

#Preview("Deleted") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { ExpenseDetailView(expenseID: scene.expense("mistake")) }
        .environment(\.dataServices, scene.services)
}

#Preview("Refund") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { ExpenseDetailView(expenseID: scene.expense("refund")) }
        .environment(\.dataServices, scene.services)
}

#Preview("Large text") {
    let scene = ExpensePreviewSupport.scene()
    NavigationStack { ExpenseDetailView(expenseID: scene.expense("beachbar")) }
        .environment(\.dataServices, scene.services)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Not found") {
    NavigationStack { ExpenseDetailView(expenseID: ExpenseID()) }
}
#endif
