import XCTest
import Foundation
@testable import DoubleTapTalk

/// Pure logic tests for the OpenAI-compatible cloud transcription service:
/// endpoint normalization, request body construction, and response parsing.
final class CloudTranscriptionTests: XCTestCase {

    // MARK: - Endpoint URL normalization

    func testEndpointAppendsChatCompletions() {
        let url = CloudTranscriptionService.endpointURL(
            for: "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
        )
        XCTAssertEqual(url?.absoluteString,
                       "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    func testEndpointHandlesTrailingSlash() {
        let url = CloudTranscriptionService.endpointURL(
            for: "https://host.example/v1/"
        )
        XCTAssertEqual(url?.absoluteString, "https://host.example/v1/chat/completions")
    }

    func testEndpointPassesThroughFullURL() {
        let url = CloudTranscriptionService.endpointURL(
            for: "https://host.example/v1/chat/completions"
        )
        XCTAssertEqual(url?.absoluteString, "https://host.example/v1/chat/completions")
    }

    func testEndpointTrimsWhitespace() {
        let url = CloudTranscriptionService.endpointURL(
            for: "  https://host.example/v1  "
        )
        XCTAssertEqual(url?.absoluteString, "https://host.example/v1/chat/completions")
    }

    func testEndpointNilForEmpty() {
        XCTAssertNil(CloudTranscriptionService.endpointURL(for: ""))
        XCTAssertNil(CloudTranscriptionService.endpointURL(for: "   "))
    }

    // MARK: - Request body

    func testRequestBodyStructure() throws {
        let dataURL = "data:audio/wav;base64,AAAA"
        let data = try CloudTranscriptionService.buildRequestBody(model: "qwen3-asr-flash", dataURL: dataURL, language: "zh")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model"] as? String, "qwen3-asr-flash")
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        XCTAssertEqual(content[0]["type"] as? String, "input_audio")
        let audio = content[0]["input_audio"] as! [String: Any]
        XCTAssertEqual(audio["data"] as? String, dataURL)

        // DashScope extension for ASR models
        let asrOptions = json["asr_options"] as! [String: Any]
        XCTAssertEqual(asrOptions["enable_itn"] as? Bool, false)
        XCTAssertEqual(asrOptions["language"] as? String, "zh")
    }

    func testRequestBodyOmitsASROptionsForNonASRModel() throws {
        let data = try CloudTranscriptionService.buildRequestBody(model: "gpt-4o-mini", dataURL: "data:audio/wav;base64,QQ==")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["asr_options"], "asr_options must not be sent to non-ASR endpoints")
    }

    func testRequestBodyOmitsLanguageWhenAuto() throws {
        let data = try CloudTranscriptionService.buildRequestBody(model: "qwen3-asr-flash", dataURL: "data:audio/wav;base64,QQ==", language: "auto")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let options = json["asr_options"] as! [String: Any]
        XCTAssertNil(options["language"])
    }

    // MARK: - Response parsing

    func testParseTranscription() throws {
        let json = #"{"choices":[{"message":{"content":"Hello World，这里是阿里。","role":"assistant"}}]}"#
        let text = try CloudTranscriptionService.parseTranscription(from: Data(json.utf8))
        XCTAssertEqual(text, "Hello World，这里是阿里。")
    }

    func testParseTranscriptionThrowsOnMissingContent() {
        let json = #"{"choices":[{"message":{"role":"assistant"}}]}"#
        XCTAssertThrowsError(try CloudTranscriptionService.parseTranscription(from: Data(json.utf8)))
    }

    func testParseTranscriptionThrowsOnEmptyChoices() {
        let json = #"{"choices":[]}"#
        XCTAssertThrowsError(try CloudTranscriptionService.parseTranscription(from: Data(json.utf8)))
    }

    func testParseTranscriptionThrowsOnNonJSON() {
        XCTAssertThrowsError(try CloudTranscriptionService.parseTranscription(from: Data("<html>".utf8)))
    }
}