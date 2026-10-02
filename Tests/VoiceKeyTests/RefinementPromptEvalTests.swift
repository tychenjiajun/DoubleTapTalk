import XCTest
@testable import DoubleTapTalk

/// **Live** eval of every refinement prompt against a real model:
/// `liquid/lfm-2.5-2.6b:free` on OpenRouter (free tier, no credits needed).
///
/// Why this model: it is small enough that prompt regressions are visible. Two
/// were found by these tests and fixed in the prompts —
/// `LLMService.wrapUserContent` now repeats the script rule in the user turn
/// (Chinese dictation was translated in 3/6 samples), and the `chatMessaging` /
/// `general` rules were reworded to stop slang loss and filler survival.
///
/// Skipped unless `OPENROUTER_API_KEY` is set:
///
///     OPENROUTER_API_KEY=sk-or-... swift test --filter RefinementPromptEval
///
/// Requests go through the shipping path (`LLMService.polish` with a pinned
/// `PolishProfile`), so what is measured here is what the app does.
final class RefinementPromptEvalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? RefinementEval.skipUnlessConfigured()
    }

    // MARK: - One test per refinement prompt

    func testTerminalProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .terminal,
            input: "um can you please run the unit tests with npm test and show me the output",
            appName: "iTerm2",
            bundleID: "com.googlecode.iterm2",
            isTerminal: true,
            mustContain: ["npm test", "unit tests"],
            mustNotContain: ["```"]
        )

        try await refine(testCase, extra: noFillers)
    }

    func testCodeCommentProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .codeComment,
            input: "so basically this function it caches the result in memory right",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            isCodeEditor: true,
            mustContain: ["caches", "result", "memory"],
            maxChars: 60
        )

        let outputs = try await refine(testCase)
        for output in outputs {
            // A comment stays a comment — never a paragraph.
            if output.count > testCase.input.count {
                XCTFail("comment refinement grew (\(testCase.input.count) → \(output.count)): \(output)")
            }
        }
    }

    func testCodeEditorProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        // Identifiers, product names and acronyms must survive verbatim.
        let testCase = RefinementEval.Case(
            profile: .codeEditor,
            input: "um so like update the readme to mention the new CI pipeline okay",
            appName: "Visual Studio Code",
            bundleID: "com.microsoft.VSCode",
            isCodeEditor: true,
            mustContain: ["README", "CI", "pipeline"]
        )

        try await refine(testCase, extra: noFillers)
    }

    func testTradingTerminalProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        // Rule under test: an explicit order becomes "BUY 100 TSLA MARKET".
        let testCase = RefinementEval.Case(
            profile: .tradingTerminal,
            input: "buy one hundred tesla shares at market price",
            appName: "Tiger Trade",
            bundleID: "com.itiger.trade",
            mustContain: ["buy 100", "market"]
        )

        try await refine(testCase) { output in
            var issues: [String] = []
            if output.lowercased().contains("one hundred") {
                issues.append("quantity not normalized to digits: \(output)")
            }
            if output.lowercased().contains("price") {
                issues.append("trailing filler kept in the order: \(output)")
            }
            return issues
        }
    }

    func testChatMessagingProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        // Voice must survive: casual chat keeps its slang and light tone.
        // Majority vote over 3 samples: measured ~1 in 8 runs still drops the
        // slang on this model even with the "NEVER delete casual slang" rule,
        // so requiring 3/3 would make the eval flap more than it informs.
        let testCase = RefinementEval.Case(
            profile: .chatMessaging,
            input: "haha yeah that is totally fine lol see you tomorrow",
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            mustContain: ["tomorrow"]
        )

        try await refine(testCase, samples: 3, minPasses: 2) { output in
            let lowercased = output.lowercased()
            guard lowercased.contains("lol") || lowercased.contains("haha") else {
                return ["chat slang ('haha'/'lol') was deleted: \(output)"]
            }
            return []
        }
    }

    func testEmailFormalProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        // Rule under test: contractions are expanded (don't → do not). Asserted as
        // "no contractions survive" rather than a fixed phrasing — the model
        // legitimately rewords (e.g. "please ensure it is completed") instead of
        // writing "do not", which is fine for a formal email.
        let testCase = RefinementEval.Case(
            profile: .emailFormal,
            input: "hey just wanted to follow up on the Q3 report don't let me down thanks",
            appName: "Mail",
            bundleID: "com.apple.mail",
            mustContain: ["Q3"],
            mustNotContain: ["hey just"]
        )

        try await refine(testCase, extra: noContractions)
    }

    func testSearchQueryProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        // Keywords only: articles dropped, technical terms exact, no punctuation.
        let testCase = RefinementEval.Case(
            profile: .searchQuery,
            input: "how to fix a python import error in pycharm",
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            mustContain: ["python", "import error", "pycharm"],
            maxChars: 45
        )

        try await refine(testCase) { output in
            output.hasSuffix(".") ? ["search query ends with punctuation: \(output)"] : []
        }
    }

    func testGeneralProfileRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .general,
            input: "um so like we should probably ship it tomorrow right",
            appName: "Notes",
            bundleID: "com.apple.Notes",
            mustContain: ["tomorrow", "ship"]
        )

        try await refine(testCase, samples: 3, minPasses: 3, extra: noFillers)
    }

    // MARK: - Language preservation (the critical guard)

    /// Chinese dictation must come back in Chinese — never translated away.
    /// Before the user-turn script reminder existed this passed only 3/6.
    /// Terms are checked loosely (the model freely reorders Chinese words) —
    /// the hard invariant is "still Chinese", asserted on every sample.
    func testChineseDictationIsNotTranslated() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .general,
            input: "查看 日志 帮 我 看一下 昨天 的 报错",
            appName: "备忘录",
            bundleID: "com.apple.Notes",
            mustContain: ["查看", "报错"],
            mustNotContain: ["logs"],
            ignoresSpaces: true
        )

        try await refine(testCase, samples: 3, minPasses: 3)
    }

    /// Same guarantee when the focused field already holds Chinese text — the
    /// model must continue in the on-screen language and must not answer with the
    /// field's existing text (which the model did in 1 of 4 samples before the
    /// context hint was labelled as context-only).
    ///
    /// Majority vote: OpenRouter's free pool is a *shared* upstream pool
    /// (`limit_source: upstream_provider_shared_pool`), so an occasional
    /// low-quality sample is expected even when the prompt is correct.
    func testChineseExistingTextKeepsChineseContinuation() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .chatMessaging,
            input: "这个 方案 的 风险 有点 高",
            appName: "微信",
            bundleID: "com.tencent.xinWeChat",
            mustContain: ["风险"],
            ignoresSpaces: true
        )

        try await refine(testCase, samples: 3, minPasses: 2, existingText: "今天我们讨论了")
    }

    // MARK: - Session context

    /// The terminal prompt carries the detected shell plus the session history;
    /// the refinement must answer the *new* utterance, not replay the history.
    func testTerminalPromptUsesShellAndSessionHistory() async throws {
        try RefinementEval.skipUnlessConfigured()
        let testCase = RefinementEval.Case(
            profile: .terminal,
            input: "now run the build again",
            appName: "Warp",
            bundleID: "dev.warp.Warp-Stable",
            isTerminal: true,
            mustContain: ["build"]
        )

        let outputs = try await refine(
            testCase,
            conversationHint: "➜  double-tap-talk git:(main) ✗ ",
            previousSegments: ["已经执行过 npm test，全部通过"]
        )
        for output in outputs where output.contains("已经执行过") {
            XCTFail("history is context, not output: \(output)")
        }
    }

    // MARK: - Coverage guard: every profile prompt round-trips

    /// Smoke test over `PolishProfile.allCases`: no profile prompt may return an
    /// empty or scaffolding-laden refinement, and the key term must survive.
    func testAllProfilePromptsProduceUsableRefinement() async throws {
        try RefinementEval.skipUnlessConfigured()

        for profile in PolishProfile.allCases {
            let testCase = RefinementEval.Case(
                profile: profile,
                input: "um please check the logs for yesterday's error",
                appName: "TestApp",
                bundleID: "com.test.app"
            )

            let outputs = try await refine(testCase)
            for output in outputs where !output.lowercased().contains("log") {
                XCTFail("\(profile.rawValue): lost the key term 'logs' → \(output)")
            }
        }
    }

    // MARK: - Helpers

    /// Refines a case through the shipping path.
    ///
    /// Every sample must be structurally well-formed (non-empty, no fences, no
    /// preamble, no CJK translation); the case expectations plus `extra` must
    /// hold for at least `minPasses` samples. Sampling is needed because this
    /// model is non-deterministic even at temperature 0.3 — before the prompt
    /// fixes, the slang and filler rules each failed roughly 1 run in 5.
    @discardableResult
    private func refine(
        _ testCase: RefinementEval.Case,
        samples: Int = 1,
        minPasses: Int? = nil,
        extra: @escaping (String) -> [String] = { _ in [] },
        existingText: String? = nil,
        conversationHint: String? = nil,
        previousSegments: [String] = []
    ) async throws -> [String] {
        let requiredPasses = minPasses ?? samples
        var passed = 0
        var outputs: [String] = []

        for sample in 1...max(samples, 1) {
            let output = try await RefinementEval.refine(
                testCase,
                existingText: existingText,
                conversationHint: conversationHint,
                previousSegments: previousSegments
            )
            outputs.append(output)
            print("[eval:\(testCase.profile.rawValue) #\(sample)] \(testCase.input) → \(output)")

            let structural = RefinementEval.wellFormedViolations(output, input: testCase.input)
            XCTAssertTrue(
                structural.isEmpty,
                "\(testCase.profile.rawValue) sample \(sample) malformed: \(structural.joined(separator: "; "))"
            )

            let issues = RefinementEval.violations(output, satisfies: testCase) + extra(output)
            if issues.isEmpty {
                passed += 1
            } else {
                print("[eval:\(testCase.profile.rawValue) #\(sample)] violations: \(issues.joined(separator: "; "))")
            }
        }

        XCTAssertGreaterThanOrEqual(
            passed, requiredPasses,
            "\(testCase.profile.rawValue): \(passed)/\(samples) samples met the expectations "
                + "(needed \(requiredPasses)) — input: \(testCase.input)"
        )
        return outputs
    }

    /// The prompts promise to strip these; a survivor is a prompt regression.
    private func noFillers(_ output: String) -> [String] {
        ["um", "uh", "like"].compactMap { filler in
            RefinementEval.containsWord(filler, in: output)
                ? "filler '\(filler)' survived in: \(output)"
                : nil
        }
    }

    /// Formal email must expand contractions — nothing like "don't" may survive.
    private func noContractions(_ output: String) -> [String] {
        guard let match = output.range(of: #"\b[A-Za-z]+n't\b"#, options: .regularExpression) else {
            return []
        }
        return ["contraction '\(output[match])' survived in: \(output)"]
    }
}
