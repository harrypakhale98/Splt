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
}
