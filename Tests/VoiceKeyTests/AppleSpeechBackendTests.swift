import XCTest
@testable import DoubleTapTalk

/// Tests for the pure accumulation logic of the Apple on-device streaming backend.
final class RecognitionTranscriptTests: XCTestCase {

    private var transcript: RecognitionTranscript!

    override func setUp() {
        super.setUp()
        transcript = RecognitionTranscript()
    }

    func testInitialTextIsEmpty() {
        XCTAssertEqual(transcript.currentText, "")
    }

    func testPartialResultShownImmediately() {
        transcript.apply(transcript: "hello", isFinal: false)
        XCTAssertEqual(transcript.currentText, "hello")
    }

    func testLaterPartialReplacesEarlierPartial() {
        transcript.apply(transcript: "hello", isFinal: false)
        transcript.apply(transcript: "hello world", isFinal: false)
        XCTAssertEqual(transcript.currentText, "hello world", "Partial results must reflect the latest best transcription")
    }

    func testFinalResultOverridesPartial() {
        transcript.apply(transcript: "hello worl", isFinal: false)
        transcript.apply(transcript: "hello world", isFinal: true)
        XCTAssertEqual(transcript.currentText, "hello world")
    }

    func testPartialAfterFinalIsIgnored() {
        transcript.apply(transcript: "hello world", isFinal: true)
        transcript.apply(transcript: "hello world and more", isFinal: false)
        XCTAssertEqual(transcript.currentText, "hello world", "Non-final updates after finalization must be ignored")
    }

    func testFinalAfterFinalOverrides() {
        transcript.apply(transcript: "hello", isFinal: true)
        transcript.apply(transcript: "hello world", isFinal: true)
        XCTAssertEqual(transcript.currentText, "hello world", "A later final result supersedes an earlier one")
    }

    func testEmptyPartialAfterFinalKeepsFinal() {
        transcript.apply(transcript: "hello world", isFinal: true)
        transcript.apply(transcript: "", isFinal: false)
        XCTAssertEqual(transcript.currentText, "hello world")
    }

    func testResetClearsState() {
        transcript.apply(transcript: "hello world", isFinal: true)
        transcript.reset()
        XCTAssertEqual(transcript.currentText, "")
    }
}

/// Tests for mapping app language codes ("auto", "zh", "en", ...) to
/// SFSpeechRecognizer locales.
final class SpeechLocaleMapperTests: XCTestCase {

    func testMapsSimplifiedChinese() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "zh").identifier, "zh-CN")
    }

    func testMapsEnglish() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "en").identifier, "en-US")
    }

    func testMapsJapanese() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "ja").identifier, "ja-JP")
    }

    func testMapsKorean() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "ko").identifier, "ko-KR")
    }

    func testMapsSpanish() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "es").identifier, "es-ES")
    }

    func testMapsFrench() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "fr").identifier, "fr-FR")
    }

    func testMapsGerman() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "de").identifier, "de-DE")
    }

    func testAutoUsesCurrentLocale() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "auto").identifier, Locale.current.identifier)
    }

    func testUnknownLanguageCodeFallsBackToCurrentLocale() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "zz").identifier, Locale.current.identifier)
    }

    func testExtendedIdentifierPassesThrough() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "en-GB").identifier, "en-GB")
    }

    func testNilLanguageFallsBackToCurrentLocale() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: nil).identifier, Locale.current.identifier)
    }
}