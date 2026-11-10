import Foundation
import Observation
import Speech

/// Starts and stops dictation for the "Describe it" field and passes the text heard so far to the form.
@MainActor
@Observable
final class DictationController {
    private(set) var isListening = false

    @ObservationIgnored private let service: any Dictating
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Set by `cancel()`, so the words heard so far stay but the form is not filled in.
    @ObservationIgnored private var skipsFinish = false

    init(service: any Dictating = SpeechDictationService()) {
        self.service = service
    }

    /// False on devices and languages without on-device dictation, where the microphone button is hidden.
    static var isSupported: Bool { SpeechTranscriber.isAvailable }

    func toggle(locale: Locale, update: @escaping @MainActor (String) -> Void, finished: @escaping @MainActor () -> Void) {
        if isListening {
            stop()
            return
        }
        isListening = true
        skipsFinish = false
        task = Task { [service] in
            let stream = await service.start(locale: locale)
            for await text in stream {
                update(text)
            }
            isListening = false
            if !skipsFinish { finished() }
            skipsFinish = false
        }
    }

    func stop() {
        Task { [service] in await service.stop() }
    }

    /// Stops listening without filling in the form, for when the person leaves the field or the screen.
    func cancel() {
        guard isListening else { return }
        skipsFinish = true
        stop()
    }
}
