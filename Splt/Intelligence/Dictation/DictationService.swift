import AVFAudio
import Foundation
import Speech

enum DictationPermission: Equatable, Sendable {
    case granted
    /// The person said no. Dictation stays off and the keyboard still works.
    case denied
    /// This device, language or build cannot dictate. Treated the same as off.
    case unavailable
}

/// Live, on-device dictation. The stream carries the whole text heard so far each time it
/// changes, and finishes when dictation stops or cannot run. It never throws.
protocol Dictating: Sendable {
    func requestPermission() async -> DictationPermission
    func start(locale: Locale) async -> AsyncStream<String>
    func stop() async
}

/// Joins finished phrases with the phrase still being heard.
struct DictationTranscript: Equatable, Sendable {
    private(set) var finalized = ""
    private(set) var volatile = ""

    var text: String {
        [finalized, volatile].filter { !$0.isEmpty }.joined(separator: " ").tidied
    }

    mutating func apply(_ segment: String, isFinal: Bool) {
        let cleaned = segment.tidied
        if isFinal {
            finalized = [finalized, cleaned].filter { !$0.isEmpty }.joined(separator: " ")
            volatile = ""
        } else {
            volatile = cleaned
        }
    }
}

/// Dictation with the SpeechAnalyzer and SpeechTranscriber from the Speech framework. The speech
/// model runs on the device, and its language data is downloaded once by the system if needed.
actor SpeechDictationService: Dictating {
    private struct Live {
        var engine: AVAudioEngine
        var analyzer: SpeechAnalyzer
        var input: AsyncStream<AnalyzerInput>.Continuation
    }

    private var task: Task<Void, Never>?
    private var live: Live?

    func requestPermission() async -> DictationPermission {
        // asking without a usage description would end the app, so stay quiet instead
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { return .unavailable }
        guard SpeechTranscriber.isAvailable else { return .unavailable }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return await AVAudioApplication.requestRecordPermission() ? .granted : .denied
        @unknown default: return .denied
        }
    }

    func start(locale: Locale) async -> AsyncStream<String> {
        await stop()
        let (stream, output) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        output.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        task = Task { await self.run(locale: locale, output: output) }
        return stream
    }

    func stop() async {
        guard task != nil || live != nil else { return }
        let running = task
        if let live {
            live.engine.stop()
            live.engine.inputNode.removeTap(onBus: 0)
            live.input.finish()
            try? await live.analyzer.finalizeAndFinishThroughEndOfInput()
        } else {
            running?.cancel()
        }
        await running?.value
        task = nil
    }

    private func run(locale: Locale, output: AsyncStream<String>.Continuation) async {
        defer { output.finish() }
        guard await requestPermission() == .granted,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        do {
            if await AssetInventory.status(forModules: [transcriber]) < .installed {
                try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
            }
            try Task.checkCancellation()

            let engine = AVAudioEngine()
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber], considering: inputFormat
            ) else { return }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let converter = AudioBufferConverter(from: inputFormat, to: analyzerFormat)

            try activateAudioSession()
            engine.inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat,
                block: Self.tapHandler(converter: converter, continuation: inputContinuation)
            )
            live = Live(engine: engine, analyzer: analyzer, input: inputContinuation)
            try await analyzer.start(inputSequence: inputStream)
            engine.prepare()
            try engine.start()

            var transcript = DictationTranscript()
            for try await result in transcriber.results {
                transcript.apply(String(result.text.characters), isFinal: result.isFinal)
                output.yield(transcript.text)
            }
        } catch {
            // no banner: the stream just ends and the keyboard stays available
        }
        tearDown()
    }

    private func tearDown() {
        if let live {
            live.engine.stop()
            live.engine.inputNode.removeTap(onBus: 0)
            live.input.finish()
        }
        live = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Built outside the actor on purpose: the audio thread calls it, and a closure written inside
    /// an actor method would assert that it runs on the actor.
    private nonisolated static func tapHandler(
        converter: AudioBufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}

/// Converts microphone buffers to the format the speech analyzer wants. Used only from the audio thread.
final class AudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) {
        outputFormat = output
        converter = input == output ? nil : AVAudioConverter(from: input, to: output)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
