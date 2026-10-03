import XCTest
import Foundation
@testable import DoubleTapTalk

/// Tests for the LLM round-trip log classification.
///
/// The endpoint used to be logged only from the response side, so a request that
/// died at the timeout left no trace of which provider/model it had hit. Failure
/// classification is now part of the fix, so it is pinned down here.
final class LLMRoundTripLogTests: XCTestCase {

    func testURLTimeoutIsDescribedAsTimeout() {
        let text = LLMService.describeFailure(URLError(.timedOut))
        XCTAssertTrue(text.contains("timeout"), text)
        XCTAssertTrue(text.contains("\(Int(LLMService.requestTimeout))s"), text)
    }

    func testCancellationIsDescribedAsCancelled() {
        XCTAssertTrue(LLMService.describeFailure(URLError(.cancelled)).contains("cancelled"))
        XCTAssertTrue(LLMService.describeFailure(CancellationError()).contains("cancelled"))
    }

    func testOfflineIsDistinguishedFromTimeout() {
        let text = LLMService.describeFailure(URLError(.notConnectedToInternet))
        XCTAssertTrue(text.contains("no network"), text)
        XCTAssertFalse(text.contains("timeout"), text)
    }

    func testPipelineTimeoutIsDescribedAsTimeout() {
        XCTAssertEqual(LLMService.describeFailure(PipelineError.timeout), "timeout")
    }

    func testUnknownErrorsKeepTheirDescription() {
        let text = LLMService.describeFailure(PipelineError.invalidResponse)
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("timeout"), text)
    }

    func testElapsedMsIsNonNegativeAndMonotonic() throws {
        let start = Date()
        let first = LLMService.elapsedMs(since: start)
        Thread.sleep(forTimeInterval: 0.05)
        let second = LLMService.elapsedMs(since: start)
        XCTAssertGreaterThanOrEqual(first, 0)
        XCTAssertGreaterThan(second, first)
    }

    func testRequestTimeoutMatchesLoggedValue() {
        // The logged "timeout: Ns" must be the value actually applied to the session.
        XCTAssertEqual(LLMService.requestTimeout, 30)
    }
}