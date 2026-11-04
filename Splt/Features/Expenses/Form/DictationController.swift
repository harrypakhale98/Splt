import Foundation
import Observation
import Speech

/// Starts and stops dictation for the "Describe it" field and passes the text heard so far to the form.
@MainActor
@Observable
final class DictationController {
    private(set) var isListening = false
    /// Why dictation ended without hearing anything, when the person did not stop it themselves.
    private(set) var notice: String?

    @ObservationIgnored private let service: any Dictating
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false

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
        notice = nil
        stopRequested = false
        task = Task { [service] in
            let stream = await service.start(locale: locale)
            var heardSomething = false
            for await text in stream {
                heardSomething = true
                update(text)
            }
            isListening = false
            if !heardSomething, !stopRequested {
                notice = await service.requestPermission() == .denied
                    ? String(localized: "Microphone access is off for Splt. Turn it on in Settings, or type instead.")
                    : String(localized: "Dictation could not start. You can type instead.")
            }
            finished()
        }
    }

    func stop() {
        stopRequested = true
        Task { [service] in await service.stop() }
    }
}
