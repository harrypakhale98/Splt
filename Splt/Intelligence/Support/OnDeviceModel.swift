import Foundation
import FoundationModels

/// The one place the app talks to the system language model.
///
/// Every feature that uses it is optional: when the model is missing, still downloading,
/// turned off or too slow, callers get nil or a thrown error and quietly use their fallback.
enum OnDeviceModel {
    struct TimedOut: Error {}

    /// Whether the system model can answer right now. Cheap to call.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Greedy sampling so the same input reads the same way every time.
    static let options = GenerationOptions(samplingMode: .greedy)

    /// Asks the model one question in a fresh session and returns its structured answer.
    /// Throws on timeout, cancellation, guardrails or an unsupported language.
    static func respond<Output: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: Output.Type,
        timeout: Duration = .seconds(5)
    ) async throws -> Output {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: Output.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, generating: type, options: options)
                return response.content
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    /// Asks the model to pick exactly one of `choices`. Returns nil when it picks anything else.
    static func choose(
        from choices: [String],
        instructions: String,
        prompt: String,
        timeout: Duration = .seconds(4)
    ) async throws -> String? {
        guard !choices.isEmpty else { return nil }
        try Task.checkCancellation()
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(name: "Choice", anyOf: choices),
            dependencies: []
        )
        let answer = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, schema: schema, options: options)
                return try response.content.value(String.self)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
        return choices.contains(answer) ? answer : nil
    }
}
