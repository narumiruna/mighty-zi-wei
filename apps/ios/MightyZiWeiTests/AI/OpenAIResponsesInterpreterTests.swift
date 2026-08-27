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
            XCTAssertTrue((json["input"] as? String)?.contains("合計不得超過 1200 個字元") == true)
            XCTAssertFalse((json["input"] as? String)?.contains("BirthProfile") == true)

            let text = try XCTUnwrap(json["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            XCTAssertEqual(format["strict"] as? Bool, true)
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            let sections = try XCTUnwrap(properties["sections"] as? [String: Any])
            let section = try XCTUnwrap(sections["items"] as? [String: Any])
            let sectionProperties = try XCTUnwrap(section["properties"] as? [String: Any])
            let content = try XCTUnwrap(sectionProperties["content"] as? [String: Any])
            let maximumSectionCharacters = try XCTUnwrap(content["maxLength"] as? Int)
            XCTAssertEqual(maximumSectionCharacters, 240)
            XCTAssertLessThanOrEqual(
                maximumSectionCharacters * InterpretationCategory.allCases.count,
                1_200
            )

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

    func test連線測試會補齊BaseURL並發出小型StructuredOutputRequest() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.com/custom/responses"
            )
            let body = try XCTUnwrap(Self.requestBody(from: request))
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["model"] as? String, "test-model")
            XCTAssertEqual(json["store"] as? Bool, false)
            XCTAssertEqual(json["stream"] as? Bool, false)
            XCTAssertFalse((json["input"] as? String)?.contains("natal.") == true)
            let text = try XCTUnwrap(json["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["name"] as? String, "connection_test")
            return Self.response(
                request: request,
                statusCode: 200,
                object: Self.outputEnvelope(["status": "ok"])
            )
        }

        try await makeInterpreter().testConnection(
            configuration: try OpenAIResponsesConfiguration(
                endpoint: "https://example.com/custom",
                model: "test-model",
                apiKey: "test-key"
            )
        )
    }

    func test多輪命盤問答只傳送已驗證資料並解析回答() async throws {
        let history = [
            ChartConversationTurn(
                question: "我的工作風格如何？",
                answer: "你可能傾向先掌握方向。",
                evidenceFactIDs: [fact.id]
            )
        ]
        MockURLProtocol.handler = { [fact] request in
            let body = try XCTUnwrap(Self.requestBody(from: request))
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["store"] as? Bool, false)
            XCTAssertEqual(json["stream"] as? Bool, false)
            let input = try XCTUnwrap(json["input"] as? String)
            XCTAssertTrue(input.contains("可以再說清楚一點嗎？"))
            XCTAssertTrue(input.contains("我的工作風格如何？"))
            XCTAssertTrue(input.contains("不要只因使用者提到年齡"))
            XCTAssertTrue(input.contains(fact.id))
            XCTAssertFalse(input.contains("BirthProfile"))
            XCTAssertFalse(input.contains("1990/01/01"))

            let text = try XCTUnwrap(json["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["name"] as? String, "chart_conversation_answer")
            XCTAssertEqual(format["strict"] as? Bool, true)
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            let answer = try XCTUnwrap(properties["answer"] as? [String: Any])
            XCTAssertEqual(answer["maxLength"] as? Int, 1_200)
            let evidence = try XCTUnwrap(properties["evidenceFactIDs"] as? [String: Any])
            let evidenceItems = try XCTUnwrap(evidence["items"] as? [String: Any])
            XCTAssertEqual(evidenceItems["enum"] as? [String], [fact.id])

            return Self.response(
                request: request,
                statusCode: 200,
                object: Self.outputEnvelope([
                    "status": "answered",
                    "answer": "你可能會先確認整體方向，再處理細節。",
                    "evidenceFactIDs": [fact.id, fact.id]
                ])
            )
        }

        let result = try await makeInterpreter().answer(
            question: "可以再說清楚一點嗎？",
            history: history,
            facts: [fact],
            seeds: makeSeeds(),
            configuration: try makeConfiguration(apiKey: "test-key")
        )

        XCTAssertEqual(result.status, .answered)
        XCTAssertEqual(result.evidenceFactIDs, [fact.id])
    }

    func test不支援問題可安全回應且不引用依據() async throws {
        MockURLProtocol.handler = { [fact] request in
            Self.response(
                request: request,
                statusCode: 200,
                object: Self.outputEnvelope([
                    "status": "unsupported",
                    "answer": "目前命盤資料無法提供健康診斷。",
                    "evidenceFactIDs": [fact.id]
                ])
            )
        }

        let result = try await makeInterpreter().answer(
            question: "請診斷我的健康問題",
            history: [],
            facts: [fact],
            seeds: makeSeeds(),
            configuration: try makeConfiguration(apiKey: nil)
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.evidenceFactIDs.isEmpty)
    }

    func test對話回答會忽略未知依據並把Seed轉成已驗證依據() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                request: request,
                statusCode: 200,
                object: Self.outputEnvelope([
                    "status": "answered",
                    "answer": "你可能傾向先掌握方向。",
                    "evidenceFactIDs": ["unknown", "seed.career"]
                ])
            )
        }

        let result = try await makeInterpreter().answer(
            question: "我想問工作上的事情，然後我已經快四十歲了。",
            history: [],
            facts: [fact],
            seeds: makeSeeds(),
            configuration: try makeConfiguration(apiKey: nil)
        )

        XCTAssertEqual(result.evidenceFactIDs, [fact.id])
    }

    func test對話回答未知依據會被拒絕() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                request: request,
                statusCode: 200,
                object: Self.outputEnvelope([
                    "status": "answered",
                    "answer": "你可能傾向先掌握方向。",
                    "evidenceFactIDs": ["unknown"]
                ])
            )
        }

        do {
            _ = try await makeInterpreter().answer(
                question: "我的個性如何？",
                history: [],
                facts: [fact],
                seeds: makeSeeds(),
                configuration: try makeConfiguration(apiKey: nil)
            )
            XCTFail("未知依據不應顯示")
        } catch is ConversationAnswerValidator.ValidationError {
        }
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

    func test舊版對話JSON可推導回答狀態且新格式可往返() throws {
        let answeredID = UUID()
        let legacyAnswered = """
        {
          "id": "\(answeredID.uuidString)",
          "question": "我的工作方式如何？",
          "answer": "你可能傾向先掌握方向。",
          "evidenceFactIDs": ["\(fact.id)"],
          "futureField": "應忽略"
        }
        """
        let legacyUnsupported = """
        {
          "id": "\(UUID().uuidString)",
          "question": "請預測確定事件",
          "answer": "目前無法用命盤回答。",
          "evidenceFactIDs": []
        }
        """

        let decoder = JSONDecoder()
        let answered = try decoder.decode(
            ChartConversationTurn.self,
            from: Data(legacyAnswered.utf8)
        )
        let unsupported = try decoder.decode(
            ChartConversationTurn.self,
            from: Data(legacyUnsupported.utf8)
        )

        XCTAssertEqual(answered.id, answeredID)
        XCTAssertEqual(answered.status, .answered)
        XCTAssertEqual(unsupported.status, .unsupported)

        let encoded = try JSONEncoder().encode(unsupported)
        let roundTrip = try decoder.decode(ChartConversationTurn.self, from: encoded)
        XCTAssertEqual(roundTrip, unsupported)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("status"))
    }

    func test缺少必要欄位的舊版對話JSON不會產生不完整回答() {
        let malformed = """
        {
          "id": "\(UUID().uuidString)",
          "answer": "缺少問題的回答。",
          "evidenceFactIDs": ["\(fact.id)"]
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ChartConversationTurn.self,
                from: Data(malformed.utf8)
            )
        )
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
        outputEnvelope(["sections": sections])
    }

    private nonisolated static func outputEnvelope(_ object: [String: Any]) -> [String: Any] {
        let generated = try! JSONSerialization.data(withJSONObject: object)
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
