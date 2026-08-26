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

    func test對話狀態成功後原子加入回答並清除草稿() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let answerer = SequenceConversationAnswerer(results: [
            .success(ChartConversationAnswer(
                status: .answered,
                content: "你可能傾向先掌握方向。",
                evidenceFactIDs: [fact.id]
            ))
        ])
        let store = ChartAssistantStore(answerer: answerer, defaults: defaults)
        store.select(makeAssistantChart())
        store.draft = "我的工作性格如何？"

        store.send(configuration: try makeConfiguration(apiKey: nil))
        XCTAssertTrue(store.turns.isEmpty)
        XCTAssertTrue(store.isRequesting)
        await waitForRequestToFinish(store)

        XCTAssertEqual(store.turns.count, 1)
        XCTAssertEqual(store.turns.first?.question, "我的工作性格如何？")
        XCTAssertEqual(store.draft, "")
        XCTAssertEqual(store.requestState, .idle)
    }

    func test對話失敗與取消會保留問題草稿及既有回答() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let answerer = SequenceConversationAnswerer(results: [
            .success(ChartConversationAnswer(
                status: .answered,
                content: "第一個回答。",
                evidenceFactIDs: [fact.id]
            )),
            .failure(OpenAIResponsesInterpreter.InterpreterError.rateLimited)
        ])
        let store = ChartAssistantStore(answerer: answerer, defaults: defaults)
        store.select(makeAssistantChart())
        store.draft = "第一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        store.draft = "第二題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        XCTAssertEqual(store.turns.count, 1)
        XCTAssertEqual(store.draft, "第二題")
        guard case .failed(let message) = store.requestState else {
            return XCTFail("應保留可重試的錯誤狀態")
        }
        XCTAssertTrue(message.contains("速率"))

        let slowStore = ChartAssistantStore(
            answerer: SlowConversationAnswerer(),
            defaults: defaults
        )
        slowStore.select(makeAssistantChart())
        slowStore.draft = "保留這個問題"
        slowStore.send(configuration: try makeConfiguration(apiKey: nil))
        slowStore.cancelRequest()

        XCTAssertEqual(slowStore.draft, "保留這個問題")
        XCTAssertEqual(slowStore.requestState, .cancelled)
        XCTAssertTrue(slowStore.turns.isEmpty)
    }

    func test本次對話最多十輪且不會靜默丟棄舊內容() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let results = (0..<ChartAssistantStore.maximumRounds).map { index in
            Result<ChartConversationAnswer, OpenAIResponsesInterpreter.InterpreterError>.success(
                ChartConversationAnswer(
                    status: .answered,
                    content: "第 \(index + 1) 個回答。",
                    evidenceFactIDs: [fact.id]
                )
            )
        }
        let store = ChartAssistantStore(
            answerer: SequenceConversationAnswerer(results: results),
            defaults: defaults
        )
        store.select(makeAssistantChart())

        for index in 0..<ChartAssistantStore.maximumRounds {
            store.draft = "第 \(index + 1) 題"
            store.send(configuration: try makeConfiguration(apiKey: nil))
            await waitForRequestToFinish(store)
        }

        XCTAssertTrue(store.hasReachedRoundLimit)
        XCTAssertEqual(store.turns.count, ChartAssistantStore.maximumRounds)
        store.draft = "第十一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        XCTAssertFalse(store.isRequesting)
        XCTAssertEqual(store.turns.count, ChartAssistantStore.maximumRounds)
    }

    func test切換命盤前需要確認且確認後清除本次對話() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let answerer = SequenceConversationAnswerer(results: [
            .success(ChartConversationAnswer(
                status: .answered,
                content: "已驗證回答。",
                evidenceFactIDs: [fact.id]
            ))
        ])
        let store = ChartAssistantStore(answerer: answerer, defaults: defaults)
        let firstChart = makeAssistantChart()
        let secondChart = ChartAssistantChart(
            id: UUID(),
            savedChartID: UUID(),
            name: "另一張命盤",
            detail: "本機顯示資料",
            facts: [fact],
            seeds: makeSeeds()
        )
        store.select(firstChart)
        store.draft = "第一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        XCTAssertTrue(store.requiresConfirmation(toSelect: secondChart))
        XCTAssertEqual(store.selectedChart?.id, firstChart.id)
        XCTAssertEqual(store.turns.count, 1)

        store.select(secondChart)

        XCTAssertEqual(store.selectedChart?.id, secondChart.id)
        XCTAssertTrue(store.turns.isEmpty)
        XCTAssertEqual(store.lastSelectedSavedChartID, secondChart.savedChartID)
    }

    func test儲存目前命盤時遷移識別且不清除對話() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let answerer = SequenceConversationAnswerer(results: [
            .success(ChartConversationAnswer(
                status: .answered,
                content: "保留這則回答。",
                evidenceFactIDs: [fact.id]
            ))
        ])
        let store = ChartAssistantStore(answerer: answerer, defaults: defaults)
        let temporaryChart = makeAssistantChart()
        let savedID = UUID()
        let savedChart = ChartAssistantChart(
            id: savedID,
            savedChartID: savedID,
            name: temporaryChart.name,
            detail: temporaryChart.detail,
            facts: temporaryChart.facts,
            seeds: temporaryChart.seeds
        )
        store.select(temporaryChart)
        store.draft = "先保留這段對話"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        store.migrateSelection(from: temporaryChart.id, to: savedChart)

        XCTAssertEqual(store.selectedChart?.id, savedID)
        XCTAssertEqual(store.selectedChart?.savedChartID, savedID)
        XCTAssertEqual(store.turns.map(\.answer), ["保留這則回答。"])
        XCTAssertFalse(store.requiresConfirmation(toSelect: savedChart))
        XCTAssertEqual(store.lastSelectedSavedChartID, savedID)
    }

    func test刪除從首頁儲存的命盤時不受觀察順序影響並保留對話() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let store = ChartAssistantStore(
            answerer: SequenceConversationAnswerer(results: [
                .success(ChartConversationAnswer(
                    status: .answered,
                    content: "刪除紀錄後仍保留。",
                    evidenceFactIDs: [fact.id]
                ))
            ]),
            defaults: defaults
        )
        let temporaryChart = makeAssistantChart()
        let savedID = UUID()
        let savedChart = ChartAssistantChart(
            id: savedID,
            savedChartID: savedID,
            name: temporaryChart.name,
            detail: temporaryChart.detail,
            facts: temporaryChart.facts,
            seeds: temporaryChart.seeds
        )
        store.select(temporaryChart)
        store.draft = "保留這次對話"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)
        store.migrateSelection(from: temporaryChart.id, to: savedChart)

        store.reconcileDeletedSavedChart(savedID)

        XCTAssertEqual(store.selectedChart?.id, temporaryChart.id)
        XCTAssertNil(store.selectedChart?.savedChartID)
        XCTAssertEqual(store.turns.map(\.answer), ["刪除紀錄後仍保留。"])
    }

    func test同ID命盤來源更新時重建選擇並清除舊對話() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let store = ChartAssistantStore(
            answerer: SequenceConversationAnswerer(results: [
                .success(ChartConversationAnswer(
                    status: .answered,
                    content: "這是舊命盤回答。",
                    evidenceFactIDs: [fact.id]
                ))
            ]),
            defaults: defaults
        )
        let savedID = UUID()
        let original = ChartAssistantChart(
            id: savedID,
            savedChartID: savedID,
            name: "原命盤",
            detail: "1990/06/15　10:30",
            facts: [fact],
            seeds: makeSeeds()
        )
        let replacementFact = ChartFact(
            id: fact.id,
            category: fact.category,
            subject: fact.subject,
            value: .init(kind: "palace", identifier: "career"),
            displayText: "紫微位於官祿宮。"
        )
        let replacement = ChartAssistantChart(
            id: savedID,
            savedChartID: savedID,
            name: "還原後命盤",
            detail: "1992/08/20　18:30",
            facts: [replacementFact],
            seeds: []
        )
        store.select(original)
        store.draft = "詢問原命盤"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        store.reconcileSelection(with: replacement)

        XCTAssertEqual(store.selectedChart?.name, "還原後命盤")
        XCTAssertEqual(store.selectedChart?.facts, [replacementFact])
        XCTAssertTrue(store.turns.isEmpty)
        XCTAssertEqual(store.draft, "")
    }

    private func waitForRequestToFinish(_ store: ChartAssistantStore) async {
        for _ in 0..<100 where store.isRequesting {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeAssistantChart() -> ChartAssistantChart {
        ChartAssistantChart(
            id: UUID(),
            savedChartID: nil,
            name: "測試命盤",
            detail: "本機顯示資料",
            facts: [fact],
            seeds: makeSeeds()
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

private actor SequenceConversationAnswerer: ChartConversationAnswering {
    private var results: [Result<
        ChartConversationAnswer,
        OpenAIResponsesInterpreter.InterpreterError
    >]

    init(results: [Result<
        ChartConversationAnswer,
        OpenAIResponsesInterpreter.InterpreterError
    >]) {
        self.results = results
    }

    func answer(
        question: String,
        history: [ChartConversationTurn],
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartConversationAnswer {
        guard !results.isEmpty else {
            throw OpenAIResponsesInterpreter.InterpreterError.emptyResponse
        }
        return try results.removeFirst().get()
    }
}

private struct SlowConversationAnswerer: ChartConversationAnswering {
    func answer(
        question: String,
        history: [ChartConversationTurn],
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartConversationAnswer {
        try await Task.sleep(for: .seconds(30))
        return ChartConversationAnswer(
            status: .answered,
            content: "不應完成",
            evidenceFactIDs: facts.prefix(1).map(\.id)
        )
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
