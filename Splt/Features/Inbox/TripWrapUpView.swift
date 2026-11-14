import SpltCore
import SwiftUI

/// Every payment from a finished trip as a checklist, all ticked. Untick the ones that were only yours,
/// and the rest go to the trip in one tap, paid by you and split the group's usual way.
struct TripWrapUpView: View {
    let wrapUp: InboxReview.WrapUp
    let controller: InboxController

    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var kept: Set<UUID>

    init(wrapUp: InboxReview.WrapUp, controller: InboxController) {
        self.wrapUp = wrapUp
        self.controller = controller
        _kept = State(initialValue: Set(wrapUp.payments.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RaisedRows {
                        ForEach(wrapUp.payments) { payment in
                            Toggle(isOn: binding(for: payment.id)) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(payment.merchant)
                                            .foregroundStyle(Ink.text)
                                        Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.footnote)
                                            .foregroundStyle(Ink.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(MoneyFormatting.magnitudeString(payment.amount))
                                        .monospacedDigit()
                                        .foregroundStyle(Ink.text)
                                }
                            }
                            .tint(Ink.switchOn)
                        }
                    }
                } footer: {
                    Text("Untick anything that was only yours. The rest is added to \(wrapUp.trip.name), paid by you and split the group's usual way.")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, Depth.pageMargin)
                }
                .paperSection()
            }
            .listStyle(.plain)
            .paperBackground()
            .navigationTitle("Wrap Up \(wrapUp.trip.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: finish)
                        .accessibilityIdentifier("wrapUp.split")
                }
            }
        }
    }

    private var confirmTitle: String {
        let amounts = wrapUp.payments.filter { kept.contains($0.id) }.map(\.amount)
        guard !amounts.isEmpty else { return String(localized: "Done") }
        return String(localized: "Split \(amounts.count) · \(TripLiveActivity.totalText(amounts))")
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { kept.contains(id) },
            set: { isOn in if isOn { kept.insert(id) } else { kept.remove(id) } }
        )
    }

    private func finish() {
        guard controller.wrapUp(wrapUp, keeping: kept) else { return }
        let trip = wrapUp.trip.id.rawValue
        let splitAny = !kept.isEmpty
        dismiss()
        // the trip's own page has the recap, now with everything in it
        if splitAny { router.open(.group(trip)) }
    }
}
