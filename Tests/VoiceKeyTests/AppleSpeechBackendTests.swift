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

    func testAutoReturnsSupportedDictationLocale() {
        let loc = SpeechLocaleMapper.locale(for: "auto")
        let supported = [
            "en-US", "en-GB", "en-AU", "en-CA", "en-IN", "en-SG",
            "zh-CN", "zh-HK", "zh-TW", "ja-JP", "ko-KR",
            "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "ru-RU",
        ]
        XCTAssertTrue(supported.contains(loc.identifier), "auto must resolve to a real dictation locale, got \(loc.identifier)")
        let lang = Locale.current.languageCode ?? ""
        if ["zh", "en", "ja", "ko", "es", "fr", "de"].contains(lang) {
            XCTAssertTrue(loc.identifier.hasPrefix(lang), "auto locale \(loc.identifier) should match system language \(lang)")
        }
    }

    // MARK: - Input-method based auto detection

    func testAutoPrefersChineseInputMethod() {
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "zh-Hans").identifier,
            "zh-CN"
        )
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "zh-Hant").identifier,
            "zh-TW"
        )
    }

    func testAutoPrefersEnglishKeyboard() {
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "en").identifier,
            "en-US"
        )
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "en-US").identifier,
            "en-US"
        )
    }

    func testAutoFollowsOtherInputMethodLanguages() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "ja").identifier, "ja-JP")
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: "ko").identifier, "ko-KR")
    }

    func testAutoFallsBackToSystemWhenNoInputMethodInfo() {
        // nil input method → same as today's system-locale-based resolution
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "auto", inputMethodLanguage: nil).identifier,
            SpeechLocaleMapper.locale(for: "auto").identifier
        )
    }

    func testExplicitLanguageStillOverridesInputMethod() {
        // Manual choice beats the input-method heuristic
        XCTAssertEqual(
            SpeechLocaleMapper.locale(for: "zh", inputMethodLanguage: "en").identifier,
            "zh-CN"
        )
    }

    func testNilLanguageFallsBackToSupportedDictationLocale() {
        let loc = SpeechLocaleMapper.locale(for: nil)
        XCTAssertTrue(loc.identifier.contains("-"), "nil must map to a supported dictation locale, got \(loc.identifier)")
    }

    func testExtendedIdentifierPassesThrough() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "en-GB").identifier, "en-GB")
    }

    func testUnknownLanguageCodeResolvesToDefault() {
        XCTAssertEqual(SpeechLocaleMapper.locale(for: "zz").identifier, "en-US")
    }
}