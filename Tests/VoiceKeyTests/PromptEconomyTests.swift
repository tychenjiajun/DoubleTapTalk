import XCTest
@testable import DoubleTapTalk

/// Guards prompt economy: compact shared sections and small per-profile
/// prompts (measured without user context). This is a regression guard
/// against verbose drift — borrowed from the lean prompt style of
/// yetone/voice-input-dist (~200 tokens per refinement).
final class PromptEconomyTests: XCTestCase {

    /// Maximum allowed size of a profile system prompt WITHOUT user context.
    /// Baseline measured on the compact design: ~480 chars.
    private let maxPromptChars = 620

    private func prompt(for profile: PolishProfile) -> String {
        let appContext = AppContext(
            appName: "TestApp",
            bundleID: "com.test.app",
            isTerminal: false,
            isBrowser: false,
            isCodeEditor: false,
            isTradingApp: false,
            focusedElementRole: nil,
            windowTitle: nil,
            focusedElementValue: nil
        )
        let context = PolishContext(
            targetApp: appContext,
            existingText: nil,
            conversationHint: nil,
            userLocale: "en_US"
        )
        return profile.systemPrompt(context: context)
    }

    func testAllProfilePromptsAreCompact() {
        for profile in PolishProfile.allCases {
            let prompt = prompt(for: profile)
            XCTAssertLessThanOrEqual(
                prompt.count, maxPromptChars,
                "\(profile.rawValue) prompt must stay compact, got \(prompt.count) chars"
            )
        }
    }

    func testAllProfilesInheritSharedAntiTranslationGuard() {
        for profile in PolishProfile.allCases {
            XCTAssertTrue(
                prompt(for: profile).contains("NEVER translate"),
                "\(profile.rawValue) prompt must include the shared anti-translation guard"
            )
        }
    }

    func testAllProfilesRequireOutputOnly() {
        for profile in PolishProfile.allCases {
            XCTAssertTrue(prompt(for: profile).contains("Output ONLY"))
        }
    }

    func testAntiTranslationGuardCarriesCompactWorkedExample() {
        // The critical WRONG/RIGHT example must survive the economy pass.
        let prompt = prompt(for: .general)
        XCTAssertTrue(prompt.contains("查看日志"), "Guard must keep the Chinese preservation example")
    }

    func testProfileRulesAreDistinct() {
        // DRY: shared sections live in one place — each profile prompt must
        // still be unique thanks to its own rule line.
        let prompts = PolishProfile.allCases.map { prompt(for: $0) }
        XCTAssertEqual(Set(prompts).count, PolishProfile.allCases.count, "Each profile must produce a distinct prompt")
    }
}