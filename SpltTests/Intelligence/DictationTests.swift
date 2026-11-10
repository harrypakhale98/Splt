import AVFAudio
import Testing
@testable import Splt

@Suite("Dictation")
struct DictationTests {
    @Test func transcriptShowsFinishedPhrasesPlusTheLiveOne() {
        var transcript = DictationTranscript()
        transcript.apply("dinner sixty", isFinal: false)
        #expect(transcript.text == "dinner sixty")
        transcript.apply("Dinner 60 dollars", isFinal: true)
        #expect(transcript.text == "Dinner 60 dollars")
        transcript.apply("with sam", isFinal: false)
        #expect(transcript.text == "Dinner 60 dollars with sam")
        transcript.apply("with Sam and Priya", isFinal: false)
        #expect(transcript.text == "Dinner 60 dollars with Sam and Priya")
        transcript.apply("with Sam and Priya", isFinal: true)
        #expect(transcript.text == "Dinner 60 dollars with Sam and Priya")
        #expect(transcript.finalized == transcript.text)
    }

    @Test func emptySegmentsAddNoStraySpaces() {
        var transcript = DictationTranscript()
        transcript.apply("  ", isFinal: true)
        transcript.apply("hello", isFinal: false)
        #expect(transcript.text == "hello")
    }

    @Test func converterPassesMatchingFormatsThrough() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        let converter = AudioBufferConverter(from: format, to: format)
        #expect(converter.convert(buffer) === buffer)
    }

    @Test func converterResamplesToTheAnalyzerFormat() throws {
        let input = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let output = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
        buffer.frameLength = 4800
        let converted = try #require(AudioBufferConverter(from: input, to: output).convert(buffer))
        #expect(converted.format.sampleRate == 16_000)
        #expect(converted.frameLength > 1000 && converted.frameLength <= 1700)
    }

    @Test func permissionIsNeverGrantedWithoutAUsageDescription() async {
        let hasDescription = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        guard !hasDescription else { return }
        #expect(await SpeechDictationService().requestPermission() == .unavailable)
    }

    private actor FakeDictation: Dictating {
        let permission: DictationPermission
        let heard: [String]
        init(permission: DictationPermission, heard: [String] = []) {
            self.permission = permission
            self.heard = heard
        }
        func requestPermission() async -> DictationPermission { permission }
        func start(locale: Locale) async -> AsyncStream<String> {
            let words = heard
            return AsyncStream { continuation in
                words.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
        func stop() async {}
    }

    @MainActor
    private func run(_ controller: DictationController) async -> [String] {
        var updates: [String] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            controller.toggle(locale: Locale(identifier: "en_US"), update: { updates.append($0) }, finished: { done.resume() })
        }
        return updates
    }

    @MainActor
    @Test func aDeniedMicrophoneIsExplained() async {
        let controller = DictationController(service: FakeDictation(permission: .denied))
        #expect(await run(controller).isEmpty)
        #expect(controller.notice?.contains("Settings") == true)
        #expect(!controller.isListening)
    }

    @MainActor
    @Test func dictationThatCannotStartIsExplained() async {
        let controller = DictationController(service: FakeDictation(permission: .granted))
        _ = await run(controller)
        #expect(controller.notice?.contains("could not start") == true)
    }

    @MainActor
    @Test func dictationThatHeardWordsSaysNothing() async {
        let controller = DictationController(service: FakeDictation(permission: .granted, heard: ["dinner"]))
        #expect(await run(controller) == ["dinner"])
        #expect(controller.notice == nil)
    }
}
