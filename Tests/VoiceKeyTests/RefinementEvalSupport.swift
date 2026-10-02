import XCTest
@testable import DoubleTapTalk

/// Shared infrastructure for **live** refinement-prompt evals.
///
/// These tests call the real OpenRouter endpoint with the free Liquid LFM
/// 2.6B model (`liquid/lfm-2.5-2.6b:free`) so every `PolishProfile` prompt is
/// exercised against a real — and deliberately small — model. Small models are
/// where prompt regressions actually show up: `RefinementPromptEvalTests`
/// exists because this model translates Chinese dictation into English roughly
/// half the time unless the script reminder rides along in the user turn.
///
/// Offline behaviour: every test skips unless `OPENROUTER_API_KEY` is set, so
/// `swift test` stays green without network access or a paid key.
///
///     OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEval
enum RefinementEval {

    // MARK: - Model under test

    static let model = "liquid/lfm-2.5-2.6b:free"
    static let endpoint = "https://openrouter.ai/api/v1/chat/completions"

    /// OpenRouter's free tier allows ~20 requests/minute; stay well under it so
    /// a full eval run does not spend its time in 429 back-off.
    static let minRequestInterval: TimeInterval = 4

    // MARK: - Cases

    /// One dictation sample plus what a good refinement must (and must not) do.
    struct Case {
        let profile: PolishProfile
        /// Raw ASR output, filler words and all.
        let input: String
        /// App the user is dictating into — drives the context handed to the prompt.
        let appName: String
        let bundleID: String
        let isTerminal: Bool
        let isCodeEditor: Bool
        /// Substrings that must survive refinement (case-insensitive).
        let mustContain: [String]
        /// Substrings that must be gone after refinement (case-insensitive).
        let mustNotContain: [String]
        /// Upper bound on output size — guards against "polishing" that rambles.
        let maxChars: Int?
        /// Compare with whitespace stripped (for CJK, where the model may or
        /// may not re-insert spaces between words).
        var ignoresSpaces: Bool = false

        init(
            profile: PolishProfile,
            input: String,
            appName: String,
            bundleID: String,
            isTerminal: Bool = false,
            isCodeEditor: Bool = false,
            mustContain: [String] = [],
            mustNotContain: [String] = [],
            maxChars: Int? = nil,
            ignoresSpaces: Bool = false
        ) {
            self.profile = profile
            self.input = input
            self.appName = appName
            self.bundleID = bundleID
            self.isTerminal = isTerminal
            self.isCodeEditor = isCodeEditor
            self.mustContain = mustContain
            self.mustNotContain = mustNotContain
            self.maxChars = maxChars
            self.ignoresSpaces = ignoresSpaces
        }
    }

    // MARK: - Configuration

    static var apiKey: String? {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key
    }

    /// Skips the calling test when no API key is configured.
    static func skipUnlessConfigured(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try XCTSkipUnless(
            apiKey != nil,
            "Set OPENROUTER_API_KEY to run live refinement evals against \(model)",
            file: file,
            line: line
        )
    }

    /// Settings that pin the eval to one profile + the OpenRouter endpoint.
    static func makeSettings(pinned profile: PolishProfile, key: String? = nil) -> LLMSettings {
        var settings = LLMSettings.default
        settings.enabled = true
        settings.provider = .openai          // OpenRouter speaks the OpenAI schema
        settings.apiKey = key ?? apiKey
        settings.model = model
        settings.baseURL = endpoint
        settings.temperature = 0.3           // matches the shipping pipeline
        settings.useAppSpecificPolish = true
        settings.pinnedProfile = profile
        return settings
    }

    /// Context for a case — mirrors what `PolishProcessor` builds at runtime.
    static func context(
        for testCase: Case,
        existingText: String? = nil,
        conversationHint: String? = nil,
        previousSegments: [String] = []
    ) -> PolishContext {
        let appContext = AppContext(
            appName: testCase.appName,
            bundleID: testCase.bundleID,
            isTerminal: testCase.isTerminal,
            isBrowser: false,
            isCodeEditor: testCase.isCodeEditor,
            isTradingApp: false,
            focusedElementRole: nil,
            windowTitle: nil,
            focusedElementValue: nil
        )
        return PolishContext(
            targetApp: appContext,
            existingText: existingText,
            conversationHint: conversationHint,
            userLocale: "zh_CN",
            previousSegments: previousSegments
        )
    }

    // MARK: - Live call

    /// Serializes eval requests and enforces `minRequestInterval` spacing.
    private static let gate = RequestGate()

    /// Refines `testCase.input` through the real polish pipeline.
    static func refine(
        _ testCase: Case,
        existingText: String? = nil,
        conversationHint: String? = nil,
        previousSegments: [String] = []
    ) async throws -> String {
        let settings = makeSettings(pinned: testCase.profile)
        let context = context(
            for: testCase,
            existingText: existingText,
            conversationHint: conversationHint,
            previousSegments: previousSegments
        )
        return try await refine(
            text: testCase.input,
            profile: testCase.profile,
            llmSettings: settings,
            context: context
        )
    }

    /// Refines arbitrary text with an explicit profile, retrying the free tier's
    /// rate limits (429) and transient gateway errors (502).
    static func refine(
        text: String,
        profile: PolishProfile,
        llmSettings: LLMSettings? = nil,
        context: PolishContext
    ) async throws -> String {
        let resolved = llmSettings ?? makeSettings(pinned: profile)
        let maxAttempts = 5

        for attempt in 1...maxAttempts {
            let delay = await gate.reserve(interval: minRequestInterval)
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            do {
                return try await LLMService.shared.polish(
                    text: text,
                    settings: resolved,
                    context: context
                )
            } catch {
                guard attempt < maxAttempts, isRetryable(error) else { throw error }
                // 15s, 30s, 45s, 60s — free-tier back-off.
                let backoff = 15.0 * Double(attempt)
                print("[RefinementEval] retry \(attempt)/\(maxAttempts - 1) after \(Int(backoff))s: \(error)")
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
        throw PipelineError.invalidResponse
    }

    /// `LLMService` flattens HTTP failures into `PipelineError.transcriptionFailed`,
    /// so detect rate limiting / gateway hiccups from the error text.
    private static func isRetryable(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("429") || text.contains("502") || text.contains("503")
            || text.contains("-1") || text.contains("timed out")
    }

    /// Minimal spacing gate: at most one eval request every `minRequestInterval`.
    private actor RequestGate {
        private var reservedUntil: TimeInterval = 0

        /// Reserves the next slot and returns how long the caller must wait.
        func reserve(interval: TimeInterval) -> TimeInterval {
            let now = Date().timeIntervalSince1970
            let start = max(now, reservedUntil)
            reservedUntil = start + interval
            return max(0, start - now)
        }
    }

    // MARK: - Assertions

    /// Invariants every refinement must satisfy, whatever the profile:
    /// non-empty, no markdown scaffolding, no preamble, no echoed instruction.
    /// - Returns: human-readable descriptions of every violation (empty = clean),
    ///   so sampling tests can count how many runs behaved.
    static func wellFormedViolations(_ output: String, input: String) -> [String] {
        var issues: [String] = []
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            issues.append("refinement is empty")
        }
        if output.contains("```") {
            issues.append("markdown code fence in: \(output)")
        }
        if output.lowercased().contains("speech to polish") {
            issues.append("echoed the user wrapper: \(output)")
        }
        if output.lowercased().contains("keep the same language") {
            issues.append("echoed the script reminder: \(output)")
        }
        if output.contains("//") || output.contains("# ") {
            issues.append("added code comment markers: \(output)")
        }

        let lowercased = trimmed.lowercased()
        let preambles = ["sure,", "sure!", "here is", "here's", "polished:", "output:", "rewritten:"]
        if preambles.contains(where: { lowercased.hasPrefix($0) }) {
            issues.append("started with a preamble: \(output)")
        }

        // The anti-translation guard is the product's hard requirement: if the
        // user spoke CJK, an all-Latin answer means the model translated it.
        if containsCJK(input), !containsCJK(trimmed) {
            issues.append("CJK input was translated away: \(output)")
        }
        return issues
    }

    static func assertWellFormed(
        _ output: String,
        input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for issue in wellFormedViolations(output, input: input) {
            XCTFail(issue, file: file, line: line)
        }
    }

    /// Unmet per-case expectations (required/forbidden terms, size cap).
    static func violations(_ output: String, satisfies testCase: Case) -> [String] {
        var issues: [String] = []

        for needle in testCase.mustContain
        where !contains(needle, in: output, ignoringSpaces: testCase.ignoresSpaces) {
            issues.append("missing '\(needle)' in: \(output)")
        }
        for needle in testCase.mustNotContain
        where contains(needle, in: output, ignoringSpaces: testCase.ignoresSpaces) {
            issues.append("forbidden '\(needle)' in: \(output)")
        }
        if let maxChars = testCase.maxChars, output.count > maxChars {
            issues.append("over \(maxChars) chars (\(output.count)): \(output)")
        }
        return issues
    }

    /// Asserts the per-case expectations (required/forbidden terms, size cap).
    static func assert(
        _ output: String,
        satisfies testCase: Case,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertWellFormed(output, input: testCase.input, file: file, line: line)
        for issue in violations(output, satisfies: testCase) {
            XCTFail("\(testCase.profile.rawValue): \(issue)", file: file, line: line)
        }
    }

    /// Whole-word check — "um"/"uh"/"like" must not match inside "summary"/"unlike".
    static func containsWord(_ word: String, in output: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "(?i)(?<![A-Za-z])\(escaped)(?![A-Za-z])"
        return output.range(of: pattern, options: .regularExpression) != nil
    }

    static func contains(_ needle: String, in output: String, ignoringSpaces: Bool = false) -> Bool {
        if ignoringSpaces {
            return stripSpaces(output).lowercased().contains(stripSpaces(needle).lowercased())
        }
        return output.lowercased().contains(needle.lowercased())
    }

    static func stripSpaces(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// Han, Hiragana, Katakana or Hangul — "the output left the input's script".
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0x3400...0x4DBF:
                return true
            default:
                return false
            }
        }
    }
}
