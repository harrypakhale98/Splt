import SwiftUI

extension View {
    /// Starts settling when `request` is set: straight to the sheet for one payment, or after
    /// choosing the group when the friend has balances in several.
    func settleFlow(_ request: Binding<SettleRequest?>) -> some View {
        modifier(SettleFlowModifier(request: request))
    }
}

private struct SettleFlowModifier: ViewModifier {
    @Binding var request: SettleRequest?
    @State private var route: SettleRoute?
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .onChange(of: request) {
                if let request, request.legs.count == 1, let leg = request.legs.first {
                    route = leg.route
                    self.request = nil
                } else if let request, request.legs.isEmpty {
                    self.request = nil
                }
            }
            .confirmationDialog(
                "Settle Up", isPresented: dialogBinding, titleVisibility: .visible, presenting: request
            ) { request in
                ForEach(request.legs) { leg in
                    Button(title(for: leg)) {
                        route = leg.route
                        self.request = nil
                    }
                }
            } message: { request in
                Text("Choose what to settle with \(request.friendName).")
            }
            .sheet(item: $route) { SettleUpSheet(route: $0) }
    }

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { (request?.legs.count ?? 0) > 1 },
            set: { if !$0 { request = nil } }
        )
    }

    private func title(for leg: SettleLeg) -> String {
        let amount = MoneyFormatting.magnitudeString(leg.debt.amount, locale: locale)
        return leg.youOwe
            ? String(localized: "\(leg.groupName): you owe \(amount)")
            : String(localized: "\(leg.groupName): owes you \(amount)")
    }
}
