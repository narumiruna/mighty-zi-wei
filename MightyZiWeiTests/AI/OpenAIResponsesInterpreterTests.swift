import Foundation
import XCTest
@testable import MightyZiWei

@MainActor
final class OpenAIResponsesInterpreterTests: XCTestCase {
    private let fact = ChartFact(
        id: "natal.star.ziwei.palace",
        category: .star,
        subject: .init(kind: "star", identifier: "ziWei"),
        value: .init(kind: "palace", identifier: "life"),
        displayText: "紫微位於命宮。"
    )

    override func tearDown() {
        MockURLProtocol.handler = nil
        HangingURLProtocol.didStart = nil
        HangingURLProtocol.didStop = nil
        super.tearDown()
    }

    func test請求符合ResponsesAPI並解析五個分類() async throws {
        MockURLProtocol.handler = { [fact] request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/custom/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try XCTUnwrap(Self.requestBody(from: request))
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["model"] as? String, "test-model")
            XCTAssertEqual(json["store"] as? Bool, false)
            XCTAssertEqual(json["stream"] as? Bool, false)
            XCTAssertTrue((json["instructions"] as? String)?.contains("Only use chart facts") == true)
            XCTAssertTrue((json["input"] as? String)?.contains(fact.id) == true)
            XCTAssertFalse((json["input"] as? String)?.contains("BirthProfile") == true)

            let text = try XCTUnwrap(json["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            XCTAssertEqual(format["strict"] as? Bool, true)
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

            return Self.response(
                request: request,
                statusCode: 200,
                object: Self.validEnvelope(evidence: fact.id)
            )
        }
        let interpreter = OpenAIResponsesInterpreter(session: makeSession())

        let result = try await interpreter.generate(
            facts: [fact],
            seeds: makeSeeds(),
            configuration: try makeConfiguration(apiKey: "test-key")
        )

        XCTAssertEqual(result.source, .remoteAI)
        XCTAssertEqual(result.sections.count, InterpretationCategory.allCases.count)
        XCTAssertTrue(result.sections.allSatisfy { $0.evidenceFactIDs == [fact.id] })
    }

    func test空白APIKey不傳AuthorizationHeader() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return Self.response(
                request: request,
                statusCode: 200,
                object: Self.validEnvelope(evidence: "natal.star.ziwei.palace")
            )
        }

        _ = try await OpenAIResponsesInterpreter(session: makeSession()).generate(
            facts: [fact],
            seeds: makeSeeds(),
            configuration: try makeConfiguration(apiKey: nil)
        )
    }

    func testHTTP錯誤會轉成可判斷的錯誤() async throws {
        let cases: [(Int, OpenAIResponsesInterpreter.InterpreterError)] = [
            (401, .unauthorized),
            (403, .unauthorized),
            (429, .rateLimited),
            (500, .httpError(500))
        ]

        for (statusCode, expectedError) in cases {
            MockURLProtocol.handler = { request in
                Self.response(request: request, statusCode: statusCode, object: ["error": "private"])
            }
            do {
                _ = try await makeInterpreter().generate(
                    facts: [fact],
                    seeds: makeSeeds(),
                    configuration: try makeConfiguration(apiKey: "key")
                )
                XCTFail("狀態碼 \(statusCode) 應失敗")
            } catch let error as OpenAIResponsesInterpreter.InterpreterError {
                XCTAssertEqual(error, expectedError)
            }
        }
    }

    func test逾時會回傳TimedOut() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }

        do {
            _ = try await makeInterpreter().generate(
                facts: [fact],
                seeds: makeSeeds(),
                configuration: try makeConfiguration(apiKey: nil)
            )
            XCTFail("逾時應失敗")
        } catch let error as OpenAIResponsesInterpreter.InterpreterError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func test拒答空白與無效JSON都不會形成解讀() async throws {
        let envelopes: [([String: Any], OpenAIResponsesInterpreter.InterpreterError)] = [
            (["output": [["content": [["type": "refusal", "refusal": "no"]]]]], .refusal),
            (["output": [["content": [["type": "output_text", "text": "   "]]]]], .emptyResponse),
            (["output": [["content": [["type": "output_text", "text": "not-json"]]]]], .invalidGeneratedContent),
            ([:], .emptyResponse)
        ]

        for (envelope, expectedError) in envelopes {
            let responseData = Self.jsonData(envelope)
            MockURLProtocol.handler = { request in
                Self.response(request: request, statusCode: 200, data: responseData)
            }
            do {
                _ = try await makeInterpreter().generate(
                    facts: [fact],
                    seeds: makeSeeds(),
                    configuration: try makeConfiguration(apiKey: nil)
                )
                XCTFail("不相容回應應失敗")
            } catch let error as OpenAIResponsesInterpreter.InterpreterError {
                XCTAssertEqual(error, expectedError)
            }
        }
    }

    func test過大回應會被拒絕() async throws {
        let responseData = Data(repeating: 0, count: 1_000_001)
        MockURLProtocol.handler = { request in
            Self.response(request: request, statusCode: 200, data: responseData)
        }

        do {
            _ = try await makeInterpreter().generate(
                facts: [fact],
                seeds: makeSeeds(),
                configuration: try makeConfiguration(apiKey: nil)
            )
            XCTFail("過大回應應失敗")
        } catch let error as OpenAIResponsesInterpreter.InterpreterError {
            XCTAssertEqual(error, .responseTooLarge)
        }
    }

    func test缺少分類重複或未知依據空白與不安全內容都無法通過驗證() async throws {
        let valid = Self.validSections(evidence: fact.id)
        let invalidSections: [[[String: Any]]] = [
            Array(valid.dropLast()),
            valid.enumerated().map { index, section in
                var changed = section
                if index == 0 { changed["evidenceFactIDs"] = [fact.id, fact.id] }
                return changed
            },
            valid.enumerated().map { index, section in
                var changed = section
                if index == 0 { changed["evidenceFactIDs"] = ["unknown"] }
                return changed
            },
            valid.enumerated().map { index, section in
                var changed = section
                if index == 0 { changed["content"] = "   " }
                return changed
            },
            valid.enumerated().map { index, section in
                var changed = section
                if index == 0 { changed["content"] = "你一定會成功。" }
                return changed
            }
        ]

        for sections in invalidSections {
            let responseData = Self.jsonData(Self.envelope(sections: sections))
            MockURLProtocol.handler = { request in
                Self.response(request: request, statusCode: 200, data: responseData)
            }
            do {
                _ = try await makeInterpreter().generate(
                    facts: [fact],
                    seeds: makeSeeds(),
                    configuration: try makeConfiguration(apiKey: nil)
                )
                XCTFail("未通過驗證的內容不應顯示")
            } catch is InterpretationValidator.ValidationError {
                continue
            }
        }
    }

    func test取消會停止底層URLSessionTask() async throws {
        let started = expectation(description: "request started")
        let stopped = expectation(description: "request stopped")
        HangingURLProtocol.didStart = { started.fulfill() }
        HangingURLProtocol.didStop = { stopped.fulfill() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let interpreter = OpenAIResponsesInterpreter(session: URLSession(configuration: configuration))
        let requestTask = Task {
            try await interpreter.generate(
                facts: [fact],
                seeds: makeSeeds(),
                configuration: try makeConfiguration(apiKey: nil)
            )
        }

        await fulfillment(of: [started], timeout: 2)
        requestTask.cancel()

        do {
            _ = try await requestTask.value
            XCTFail("取消後不應成功")
        } catch is CancellationError {
        }
        await fulfillment(of: [stopped], timeout: 2)
    }

    private func makeInterpreter() -> OpenAIResponsesInterpreter {
        OpenAIResponsesInterpreter(session: makeSession())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeConfiguration(apiKey: String?) throws -> OpenAIResponsesConfiguration {
        try OpenAIResponsesConfiguration(
            endpoint: "https://example.com/custom/responses",
            model: "test-model",
            apiKey: apiKey
        )
    }

    private func makeSeeds() -> [InterpretationSeed] {
        InterpretationCategory.allCases.map { category in
            InterpretationSeed(
                id: "seed.\(category.rawValue)",
                category: category,
                meaning: "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }
    }

    private nonisolated static func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private nonisolated static func response(
        request: URLRequest,
        statusCode: Int,
        object: [String: Any]
    ) -> (HTTPURLResponse, Data) {
        response(request: request, statusCode: statusCode, data: jsonData(object))
    }

    private nonisolated static func response(
        request: URLRequest,
        statusCode: Int,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    private nonisolated static func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private nonisolated static func validEnvelope(evidence: String) -> [String: Any] {
        envelope(sections: validSections(evidence: evidence))
    }

    private nonisolated static func envelope(sections: [[String: Any]]) -> [String: Any] {
        let generated = try! JSONSerialization.data(withJSONObject: ["sections": sections])
        let text = String(decoding: generated, as: UTF8.self)
        return [
            "output": [
                ["type": "message", "content": [["type": "output_text", "text": text]]]
            ]
        ]
    }

    private nonisolated static func validSections(evidence: String) -> [[String: Any]] {
        InterpretationCategory.allCases.map { category in
            [
                "category": category.rawValue,
                "title": category.title,
                "content": "你可能傾向先掌握整體方向。",
                "evidenceFactIDs": [evidence]
            ]
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HangingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var didStart: (@Sendable () -> Void)?
    nonisolated(unsafe) static var didStop: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.didStart?() }
    override func stopLoading() { Self.didStop?() }
}
