import XCTest
@testable import DoubleTapTalk

/// Unit tests for PolishProcessor — the shared polish pipeline used by both
/// the file-based ASR path and the streaming Apple path (DRY).
final class PolishProcessorTests: XCTestCase {

    private var processor: PolishProcessor!

    override func setUp() {
        super.setUp()
        processor = PolishProcessor()
    }

    // MARK: - Disabled / unconfigured paths (LLM must never be touched)

    func testReturnsOriginalWhenPolishingDisabled() async {
        let settings = LLMSettings.default  // enabled == false
        let raw = "hello world"

        let result = await processor.process(rawText: raw, settings: settings)

        XCTAssertEqual(result, raw, "Polishing disabled in settings must return text unchanged")
    }

    func testReturnsOriginalWhenAPIKeyMissing() async {
        var settings = LLMSettings.default
        settings.enabled = true
        settings.apiKey = nil
        let raw = "hello world"

        let result = await processor.process(rawText: raw, settings: settings)

        XCTAssertEqual(result, raw, "Missing API key must return text unchanged")
    }

    func testReturnsOriginalWhenAPIKeyEmpty() async {
        var settings = LLMSettings.default
        settings.enabled = true
        settings.apiKey = ""
        let raw = "hello world"

        let result = await processor.process(rawText: raw, settings: settings)

        XCTAssertEqual(result, raw, "Empty API key must return text unchanged")
    }

    func testReturnsOriginalWhenTextEmpty() async {
        var settings = LLMSettings.default
        settings.enabled = true
        settings.apiKey = "sk-test-123"

        let result = await processor.process(rawText: "", settings: settings)

        XCTAssertEqual(result, "", "Empty input should short-circuit before any LLM call")
    }

    func testReturnsOriginalWhenTextWhitespaceOnly() async {
        var settings = LLMSettings.default
        settings.enabled = true
        settings.apiKey = "sk-test-123"

        let result = await processor.process(rawText: "   \n  ", settings: settings)

        XCTAssertEqual(result, "   \n  ", "Whitespace-only input should return unchanged")
    }
}