import XCTest
@testable import DoubleTapTalk

/// Tests for the overlay's state → visual-language mapping. These are the
/// guarantees behind "the capsule never looks frozen but alive": every pipeline
/// stage must look different, and only the listening stage may show the raw
/// audio level / the streamed transcript.
final class OverlayStateTests: XCTestCase {

    private let allStates: [OverlayState] = [
        .listening, .transcribing, .polishing, .success, .empty, .error
    ]
    private let languages: [OverlayLanguage] = [.simplifiedChinese, .english]

    // MARK: - Language selection

    func testChinesePreferredLanguagesResolveToSimplifiedChinese() {
        for tag in ["zh-Hans", "zh-Hans-CN", "zh-CN", "ZH"] {
            XCTAssertEqual(OverlayStyle.language(preferredLanguages: [tag]), .simplifiedChinese,
                           "\(tag) should use Chinese overlay copy")
        }
    }

    func testNonChineseLanguagesResolveToEnglish() {
        for tag in ["en-US", "en-GB", "ja", "ko", "de"] {
            XCTAssertEqual(OverlayStyle.language(preferredLanguages: [tag]), .english,
                           "\(tag) should use English overlay copy")
        }
    }

    func testEmptyLanguageListFallsBackToEnglish() {
        XCTAssertEqual(OverlayStyle.language(preferredLanguages: []), .english)
    }

    func testFirstPreferredLanguageWins() {
        XCTAssertEqual(OverlayStyle.language(preferredLanguages: ["zh-Hans-CN", "en-US"]), .simplifiedChinese)
    }

    // MARK: - Every state resolves, in every language

    func testEveryStateHasCopyInEveryLanguage() {
        for state in allStates {
            for language in languages {
                let resolved = OverlayStyle.resolve(state, language: language)
                XCTAssertFalse(resolved.statusText.isEmpty,
                               "\(state)/\(language) must have a status line")
            }
        }
    }

    func testChineseAndEnglishCopyDiffer() {
        for state in allStates {
            let zh = OverlayStyle.resolve(state, language: .simplifiedChinese).statusText
            let en = OverlayStyle.resolve(state, language: .english).statusText
            XCTAssertNotEqual(zh, en, "\(state) must not ship English copy to a Chinese user")
        }
    }

    // MARK: - The listening state is the only live one

    func testOnlyListeningDrivesBarsFromAudioLevel() {
        for state in allStates {
            let waveform = OverlayStyle.resolve(state, language: .english).waveform
            let isLevelDriven: Bool
            if case .level = waveform { isLevelDriven = true } else { isLevelDriven = false }
            XCTAssertEqual(isLevelDriven, state == .listening,
                           "\(state) must not animate a live audio level")
        }
    }

    func testOnlyPayloadStatesShowTheirOwnText() {
        // listening shows the live transcript and success shows the final
        // result; the wait/failure states must show their own status line
        // instead of stale text.
        XCTAssertTrue(OverlayStyle.resolve(.listening, language: .english).prefersText)
        XCTAssertTrue(OverlayStyle.resolve(.success, language: .english).prefersText)
        for state in [OverlayState.transcribing, .polishing, .empty, .error] {
            XCTAssertFalse(OverlayStyle.resolve(state, language: .english).prefersText,
                           "\(state) must show its status line, not carried-over text")
        }
    }

    // MARK: - Stage semantics

    func testBusyStagesAreIndeterminateAndDimTheClock() {
        for state in [OverlayState.transcribing, .polishing] {
            let resolved = OverlayStyle.resolve(state, language: .english)
            XCTAssertEqual(resolved.waveform, .indeterminate, "\(state) must animate without audio")
            XCTAssertTrue(resolved.dimsTimer, "\(state) is post-recording: the clock is stale")
            XCTAssertEqual(resolved.tint, .dimmed)
        }
    }

    func testOutcomeStagesUseASymbolAndAColoredAccent() {
        let expectations: [(OverlayState, String, OverlayStyle.Tint)] = [
            (.success, "checkmark", .positive),
            (.empty, "mic.slash", .caution),
            (.error, "exclamationmark.triangle.fill", .critical)
        ]
        for (state, symbol, tint) in expectations {
            let resolved = OverlayStyle.resolve(state, language: .english)
            XCTAssertEqual(resolved.waveform, .symbol(symbol))
            XCTAssertEqual(resolved.tint, tint)
            XCTAssertTrue(resolved.dimsTimer)
        }
    }

    func testListeningAccentStaysNeutral() {
        for language in languages {
            let resolved = OverlayStyle.resolve(.listening, language: language)
            XCTAssertEqual(resolved.tint, .neutral, "listening must keep today's white look")
            XCTAssertFalse(resolved.dimsTimer)
        }
    }

    func testNoTwoStagesShareTheSameVisualLanguage() {
        // transcribing/polishing deliberately share one "busy" language — they
        // are the same kind of wait. Everything else must be distinguishable.
        var groups: [String: Set<OverlayState>] = [:]
        for state in allStates {
            let resolved = OverlayStyle.resolve(state, language: .english)
            groups["\(resolved.waveform)|\(resolved.tint)", default: []].insert(state)
        }
        XCTAssertEqual(groups.count, 5, "expected 5 distinct visual languages, got \(groups.keys.sorted())")
        let busy = groups["indeterminate|dimmed"]
        XCTAssertEqual(busy, [.transcribing, .polishing],
                       "only the two network/LLM waits may look alike")
        // listening / success / empty / error must not share visuals with the
        // busy pair or with each other.
        XCTAssertEqual(groups["level|neutral"], [.listening])
        XCTAssertEqual(groups[#"symbol("checkmark")|positive"#], [.success])
        XCTAssertEqual(groups[#"symbol("mic.slash")|caution"#], [.empty])
        XCTAssertEqual(groups[#"symbol("exclamationmark.triangle.fill")|critical"#], [.error])
    }

    func testErrorCopyTellsTheUserHowToRetry() {
        for language in languages {
            let text = OverlayStyle.resolve(.error, language: language).statusText
            XCTAssertTrue(text.contains("⌃"), "\(language) error copy should name the trigger key: \(text)")
        }
    }

    func testTimerRevealThresholdIsMeaningful() {
        XCTAssertGreaterThan(OverlayStyle.timerRevealSecond, 0,
                             "the clock has to be dimmed at the very start of a recording")
    }
}

/// Tests for the pure "busy" waveform the capsule shows while it uploads or
/// polishes — the animation that replaced a level meter stuck on a stale sample.
final class IndeterminateWaveformTests: XCTestCase {

    func testProducesOneBarPerSlot() {
        let waveform = IndeterminateWaveform(barCount: 5)
        XCTAssertEqual(waveform.bars(atPhase: 0).count, 5)
    }

    func testZeroBarCountProducesNothing() {
        XCTAssertTrue(IndeterminateWaveform(barCount: 0).bars(atPhase: 0.5).isEmpty)
    }

    func testBarsStayInBoundsForEveryPhase() {
        let waveform = IndeterminateWaveform()
        for step in 0...200 {
            let phase = Float(step) / 200
            for bar in waveform.bars(atPhase: phase) {
                XCTAssertTrue(bar >= 0 && bar <= 1, "bar out of range at phase \(phase): \(bar)")
            }
        }
    }

    func testNeverGoesFullyFlat() {
        // A flat capsule during a long upload reads as a frozen app.
        let waveform = IndeterminateWaveform()
        for step in 0...100 {
            for bar in waveform.bars(atPhase: Float(step) / 100) {
                XCTAssertGreaterThan(bar, 0.05, "busy bars must keep a visible floor")
            }
        }
    }

    func testPhaseIsPeriodic() {
        let waveform = IndeterminateWaveform()
        let start = waveform.bars(atPhase: 0)
        let wrapped = waveform.bars(atPhase: 1)
        let past = waveform.bars(atPhase: 3)
        for ((a, b), c) in zip(zip(start, wrapped), past) {
            XCTAssertEqual(a, b, accuracy: 0.0001, "phase 1 must equal phase 0")
            XCTAssertEqual(a, c, accuracy: 0.0001, "phase must wrap, not grow without bound")
        }
    }

    func testBumpSweepsOutAndBack() {
        let waveform = IndeterminateWaveform()
        func peakIndex(at phase: Float) -> Int {
            let bars = waveform.bars(atPhase: phase)
            return bars.enumerated().max(by: { $0.element < $1.element })?.offset ?? -1
        }
        XCTAssertEqual(peakIndex(at: 0), 0)
        XCTAssertEqual(peakIndex(at: 0.5), waveform.barCount - 1, "the bump reaches the far end")
        XCTAssertEqual(peakIndex(at: 0.75), (waveform.barCount - 1) / 2, "and comes back through the middle")
        XCTAssertEqual(peakIndex(at: 1), 0, "one full period returns to the start")
    }

    func testOutermostBarsAreNotNeighbours() {
        // Wrapping would light bar 0 and bar 4 together and read as a glitch.
        let bars = IndeterminateWaveform().bars(atPhase: 0)
        XCTAssertEqual(bars[0], bars.max() ?? 0, accuracy: 0.0001, "the bump peaks on bar 0")
        XCTAssertEqual(bars[bars.count - 1], IndeterminateWaveform().resting, accuracy: 0.0001,
                       "the far end must be resting, not peaking with bar 0")
    }

    func testAnimationIsSmoothNotSnappy() {
        // A bump that jumps bar to bar looks like static; cap how far a bar may
        // move in a single 1/60 s frame.
        let waveform = IndeterminateWaveform()
        var previous = waveform.bars(atPhase: 0)
        for step in 1...120 {
            let current = waveform.bars(atPhase: Float(step) / 120)
            for (before, after) in zip(previous, current) {
                XCTAssertLessThan(abs(after - before), 0.2,
                                  "bar moved \(abs(after - before)) in one frame")
            }
            previous = current
        }
    }

    func testEnvelopeIsUnimodal() {
        // The bump has to rise towards one point and fall away from it — no
        // second hump, no dip in the middle (which is what reading a wrapped
        // bump as two lit ends looks like).
        let waveform = IndeterminateWaveform()
        for step in 0...40 {
            let phase = Float(step) / 40
            let bars = waveform.bars(atPhase: phase)
            var peak = 0
            for index in 1..<bars.count where bars[index] > bars[peak] {
                peak = index
            }
            for index in 1...max(peak, 1) where index <= peak {
                XCTAssertGreaterThanOrEqual(bars[index], bars[index - 1],
                                            "bars must rise up to the peak at phase \(phase)")
            }
            for index in peak..<(bars.count - 1) {
                XCTAssertGreaterThanOrEqual(bars[index], bars[index + 1],
                                            "bars must fall away from the peak at phase \(phase)")
            }
        }
    }

    func testEnvelopeIsSymmetricAboutTheBumpCentre() {
        // Sampled at the phase whose bump centre lands exactly on bar 2.
        let waveform = IndeterminateWaveform()
        let bars = waveform.bars(atPhase: 0.75)
        XCTAssertEqual(bars[2], waveform.peak, accuracy: 0.0001)
        XCTAssertEqual(bars[1], bars[3], accuracy: 0.0001)
        XCTAssertEqual(bars[0], bars[4], accuracy: 0.0001)
    }
}

/// Tests for the capsule corner radius, which used to freeze at the single-line
/// value and turn every tall capsule into a plain rounded rectangle.
final class OverlayCornerRadiusTests: XCTestCase {

    func testShortCapsuleIsAPill() {
        XCTAssertEqual(OverlayMetrics.cornerRadius(forHeight: OverlayMetrics.baseHeight),
                       OverlayMetrics.baseHeight / 2)
    }

    func testTallCapsuleRadiusIsClamped() {
        let tall = OverlayMetrics.height(forLines: OverlayMetrics.maxLines)
        XCTAssertEqual(OverlayMetrics.cornerRadius(forHeight: tall), OverlayMetrics.maxCornerRadius)
        XCTAssertLessThan(OverlayMetrics.maxCornerRadius, tall / 2,
                          "a clamped capsule must not stay a full pill")
    }

    func testRadiusNeverExceedsHalfTheHeight() {
        for lines in 1...OverlayMetrics.maxLines {
            let height = OverlayMetrics.height(forLines: lines)
            XCTAssertLessThanOrEqual(OverlayMetrics.cornerRadius(forHeight: height), height / 2,
                                     "a radius larger than half the height renders as a lozenge")
        }
    }

    func testRadiusGrowsMonotonicallyWithHeight() {
        var last: CGFloat = -1
        for lines in 1...OverlayMetrics.maxLines {
            let radius = OverlayMetrics.cornerRadius(forHeight: OverlayMetrics.height(forLines: lines))
            XCTAssertGreaterThanOrEqual(radius, last)
            last = radius
        }
    }

    func testZeroHeightIsSafe() {
        XCTAssertEqual(OverlayMetrics.cornerRadius(forHeight: 0), 0)
        XCTAssertEqual(OverlayMetrics.cornerRadius(forHeight: -10), 0)
    }
}
