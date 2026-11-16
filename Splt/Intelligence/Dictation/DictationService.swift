@preconcurrency import AVFAudio
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
        var generation: Int
        var engine: AVAudioEngine
        var analyzer: SpeechAnalyzer
        var input: AsyncStream<AnalyzerInput>.Continuation
    }

    /// Bumped by every start and stop. A run whose number is no longer current gives up at its next
    /// step, so a stop that arrives while dictation is still being set up never leaves the microphone on.
    private var generation = 0
    private var task: Task<Void, Never>?
    private var output: AsyncStream<String>.Continuation?
    /// The microphone once it is running. Set with no await after the run's last check, so a stop finds
    /// either a session still being set up or one it can finish.
    private var live: Live?
    /// The run that turned the audio session on, so an older run never turns off a newer one's session.
    private var sessionOwner: Int?

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
        generation += 1
        let number = generation
        let (stream, output) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // only this session: a late call from an old stream must not stop a newer one
        output.onTermination = { [weak self] _ in
            Task { await self?.stop(generation: number) }
        }
        self.output = output
        task = Task { await self.run(locale: locale, generation: number, output: output) }
        return stream
    }

    func stop() async {
        await stop(generation: generation)
    }

    private func stop(generation number: Int) async {
        guard number == generation, task != nil || live != nil else { return }
        generation += 1
        let running = task
        let stream = output
        task = nil
        output = nil
        if let live, live.generation == number {
            // The microphone is on: finish the audio so the last words still arrive. Once the analyzer
            // has finished, the results end and so does the run.
            self.live = nil
            live.engine.stop()
            live.engine.inputNode.removeTap(onBus: 0)
            live.input.finish()
            do {
                try await live.analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await live.analyzer.cancelAndFinishNow()
            }
            await running?.value
        } else {
            // Still setting up, which can mean waiting on a language download. End the stream now rather
            // than wait: the run sees it is no longer current at its next step and cleans up after itself.
            running?.cancel()
            stream?.finish()
        }
    }

    private func run(locale: Locale, generation number: Int, output: AsyncStream<String>.Continuation) async {
        defer { output.finish() }
        defer { tearDown(generation: number) }
        guard await requestPermission() == .granted, number == generation,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale), number == generation else { return }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        do {
            if await AssetInventory.status(forModules: [transcriber]) < .installed {
                try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
            }
            guard number == generation else { return }

            // The input node reports the microphone's real format only once the session allows recording.
            try activateAudioSession(for: number)
            let engine = AVAudioEngine()
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            // a tap with an empty format ends the app, so a missing microphone just ends dictation
            guard Self.canRecord(from: inputFormat),
                  let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                      compatibleWith: [transcriber], considering: inputFormat
                  ),
                  number == generation else { return }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputStream, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await analyzer.start(inputSequence: inputStream)
            guard number == generation else {
                inputContinuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }

            let converter = AudioBufferConverter(from: inputFormat, to: analyzerFormat)
            engine.inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat,
                block: Self.tapHandler(converter: converter, continuation: inputContinuation)
            )
            engine.prepare()
            do {
                try engine.start()
            } catch {
                engine.inputNode.removeTap(onBus: 0)
                inputContinuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }
            live = Live(generation: number, engine: engine, analyzer: analyzer, input: inputContinuation)

            var transcript = DictationTranscript()
            for try await result in transcriber.results {
                transcript.apply(String(result.text.characters), isFinal: result.isFinal)
                output.yield(transcript.text)
            }
        } catch {
            // no banner: the stream just ends and the keyboard stays available
        }
    }

    /// Whether the input node has a microphone format a tap can use.
    nonisolated static func canRecord(from format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func tearDown(generation number: Int) {
        if let live, live.generation == number {
            live.engine.stop()
            live.engine.inputNode.removeTap(onBus: 0)
            live.input.finish()
            self.live = nil
        }
        guard sessionOwner == number else { return }
        sessionOwner = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateAudioSession(for number: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        sessionOwner = number
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
        // the converter calls this block synchronously, inside convert, on this same thread
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let input = buffer
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        return status == .error ? nil : output
    }
}
