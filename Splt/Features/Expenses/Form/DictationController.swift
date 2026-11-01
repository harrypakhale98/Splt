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
        task = Task { [service] in
            let stream = await service.start(locale: locale)
            for await text in stream {
                update(text)
            }
            isListening = false
            finished()
        }
    }

    func stop() {
        Task { [service] in await service.stop() }
    }
}
