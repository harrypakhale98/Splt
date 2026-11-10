import SwiftUI

/// One quiet line under the settled hero: when the payment was recorded and how. Undo lives on the
/// banner that follows the sheet.
struct SettleDoneCard: View {
    let model: SettleModel

    var body: some View {
        if model.receipt != nil {
            Text("Recorded \(model.date.formatted(.dateTime.day().month(.abbreviated))) \u{00B7} \(model.method.title)")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
    }
}
