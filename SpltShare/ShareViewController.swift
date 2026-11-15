import SpltCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// Takes a screenshot, or a copied bank text, from the share sheet and saves the payment in it to To Split.
/// It reads on the device, shows what it found, and keeps nothing but the shop and the amount.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
@Observable
final class ShareModel {
    var merchant = ""
    var amountText = ""
    var currencyCode = PaymentAmount.localCurrencyCode
    var isReading = true
    var foundNothing = false

    private let context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    /// Read as the app's amount field reads it, in this iPhone's way of writing numbers, and failing that
    /// the forgiving way bank texts are read, so "12.50" still works on a phone that writes "12,50".
    var amount: Money? {
        let text = amountText.trimmingCharacters(in: .whitespaces)
        if let parsed = try? MoneyParser.parse(text, currencyCode: currencyCode, locale: .current, allowNegative: false),
           parsed.isPositive {
            return parsed
        }
        return PaymentTextParser.decimal(text).flatMap { PaymentAmount.money($0, currencyCode: currencyCode) }
    }

    /// The currency menu: what was found and this iPhone's currency first, then every other in code order.
    var currencyChoices: [String] {
        let lead = [currencyCode, PaymentAmount.localCurrencyCode]
        var seen = Set<String>()
        return (lead + Self.allCurrencies).filter { seen.insert($0).inserted }
    }

    private static let allCurrencies = Locale.commonISOCurrencyCodes.sorted()

    func load() async {
        defer { isReading = false }
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
           let data = await Self.data(from: provider, type: .image),
           let image = UIImage(data: data)?.cgImage {
            fill(await ScreenshotPaymentReader.read(image))
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
                  let data = await Self.data(from: provider, type: .plainText),
                  let text = String(data: data, encoding: .utf8) {
            if let parsed = PaymentTextParser.parse(text) {
                fill(ScreenshotPaymentReader.Reading(merchant: parsed.merchant, amount: parsed.amount))
            } else {
                fill(ScreenshotPaymentReader.reading(from: text.components(separatedBy: .newlines)))
            }
        }
        foundNothing = amount == nil
    }

    private func fill(_ reading: ScreenshotPaymentReader.Reading) {
        merchant = reading.merchant ?? ""
        if let found = reading.amount {
            currencyCode = found.currencyCode
            // written as the app writes amounts: "12.50", or "12,50" where that is the way
            amountText = found.plainString(locale: .current)
        }
    }

    func save() {
        guard let amount else { return }
        let name = merchant
        PaymentInboxFile.shared.update {
            $0.capture(merchant: name, amount: amount, date: Date(), source: .screenshot, now: Date())
        }
        WidgetCenter.shared.reloadAllTimelines()
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                if model.isReading {
                    ProgressView("Reading…")
                } else {
                    Section {
                        TextField("Shop or person", text: $model.merchant)
                        HStack {
                            TextField("Amount", text: $model.amountText)
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                            Picker("Currency", selection: $model.currencyCode) {
                                ForEach(model.currencyChoices, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                    } footer: {
                        Text(model.foundNothing
                             ? "Splt couldn't find an amount. Type it in, and it waits in To Split until you split it."
                             : "Check what Splt found. It waits in To Split on this iPhone until you split it.")
                    }
                }
            }
            .navigationTitle("Add to To Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { model.save() }
                        .disabled(model.amount == nil)
                }
            }
        }
    }
}
