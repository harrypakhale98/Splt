import SpltCore
import SwiftUI

struct DetailsSection: View {
    @Bindable var model: ExpenseFormModel
    var focus: FocusState<ExpenseFormField?>.Binding

    var body: some View {
        Section {
            TextField("Title", text: $model.title, prompt: Text("What was it for?"))
                .focused(focus, equals: .title)
                .submitLabel(.done)
                .onChange(of: model.title) { model.titleDidChange() }

            if let suggestion = model.suggestedCategory, suggestion != model.category {
                Button {
                    model.acceptSuggestedCategory()
                } label: {
                    Label("Use \(suggestion.title)", systemImage: suggestion.symbolName)
                }
                .accessibilityHint("Suggested category for this title")
            }

            Picker("Category", selection: $model.category) {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    Label(category.title, systemImage: category.symbolName).tag(category)
                }
            }

            let groups = model.availableGroups
            if groups.count > 1, let current = model.group {
                Picker("Group", selection: Binding(get: { current.id }, set: { model.switchGroup(to: $0) })) {
                    ForEach(groups) { group in
                        Label(group.name, systemImage: group.symbol).tag(group.id)
                    }
                }
            }

            if model.isEditingRecurring {
                LabeledContent("Starts") { Text(model.date, format: .dateTime.day().month().year()) }
            } else {
                DatePicker("Date", selection: $model.date, displayedComponents: .date)
            }
        }
    }
}
