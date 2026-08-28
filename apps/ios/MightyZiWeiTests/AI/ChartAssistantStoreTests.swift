import Foundation
import XCTest
@testable import MightyZiWei

@MainActor
final class ChartAssistantStoreTests: XCTestCase {
    private let fact = ChartFact(
        id: "natal.star.ziwei.palace",
        category: .star,
        subject: .init(kind: "star", identifier: "ziWei"),
        value: .init(kind: "palace", identifier: "life"),
        displayText: "紫微位於命宮。"
    )

    func test草稿也屬於未保存工作且切換命盤前需要確認() {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let store = ChartAssistantStore(answerer: SlowConversationAnswerer(), defaults: defaults)
        let first = makeAssistantChart()
        let second = makeAssistantChart()
        store.select(first)

        store.draft = "   "
        XCTAssertFalse(store.hasUnsavedWork)
        XCTAssertFalse(store.requiresConfirmation(toSelect: second))

        store.draft = "保留這個草稿"
        XCTAssertTrue(store.hasUnsavedWork)
        XCTAssertTrue(store.requiresConfirmation(toSelect: second))
        XCTAssertEqual(store.selectedChart?.id, first.id)
        XCTAssertEqual(store.draft, "保留這個草稿")
    }

    func test對話保存狀態會追蹤同一副本與尚未保存輪數() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let answerer = SequenceConversationAnswerer(results: [
            .success(ChartConversationAnswer(
                status: .answered,
                content: "第一個回答。",
                evidenceFactIDs: [fact.id]
            )),
            .success(ChartConversationAnswer(
                status: .answered,
                content: "第二個回答。",
                evidenceFactIDs: [fact.id]
            ))
        ])
        let store = ChartAssistantStore(answerer: answerer, defaults: defaults)
        store.select(makeAssistantChart())
        store.draft = "第一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        XCTAssertNil(store.savedConversationID)
        XCTAssertEqual(store.unsavedTurnCount, 1)
        XCTAssertTrue(store.hasUnsavedChanges)

        let savedID = UUID()
        store.markConversationSaved(id: savedID)
        XCTAssertEqual(store.savedConversationID, savedID)
        XCTAssertEqual(store.savedTurnCount, 1)
        XCTAssertEqual(store.unsavedTurnCount, 0)
        XCTAssertFalse(store.hasUnsavedChanges)

        store.draft = "第二題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)
        XCTAssertEqual(store.savedConversationID, savedID)
        XCTAssertEqual(store.unsavedTurnCount, 1)
        XCTAssertTrue(store.hasUnsavedChanges)

        store.clearConversation()
        XCTAssertNil(store.savedConversationID)
        XCTAssertEqual(store.savedTurnCount, 0)
        XCTAssertEqual(store.unsavedTurnCount, 0)
    }

    func test刪除已保存副本後目前對話會恢復為未保存() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let store = ChartAssistantStore(
            answerer: SequenceConversationAnswerer(results: [
                .success(ChartConversationAnswer(
                    status: .answered,
                    content: "保留中的回答。",
                    evidenceFactIDs: [fact.id]
                ))
            ]),
            defaults: defaults
        )
        store.select(makeAssistantChart())
        store.draft = "第一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        let savedID = UUID()
        store.markConversationSaved(id: savedID)
        store.reconcileDeletedSavedConversation(savedID)

        XCTAssertNil(store.savedConversationID)
        XCTAssertEqual(store.savedTurnCount, 0)
        XCTAssertEqual(store.unsavedTurnCount, 1)
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(store.turns.count, 1)
    }

    func test刪除其他保存對話不會清除目前對話的保存狀態() async throws {
        let defaults = UserDefaults(suiteName: "ChartAssistantStoreTests.\(UUID().uuidString)")!
        let store = ChartAssistantStore(
            answerer: SequenceConversationAnswerer(results: [
                .success(ChartConversationAnswer(
                    status: .answered,
                    content: "目前對話的回答。",
                    evidenceFactIDs: [fact.id]
                ))
            ]),
            defaults: defaults
        )
        store.select(makeAssistantChart())
        store.draft = "第一題"
        store.send(configuration: try makeConfiguration(apiKey: nil))
        await waitForRequestToFinish(store)

        let activeSavedID = UUID()
        store.markConversationSaved(id: activeSavedID)
        store.reconcileDeletedSavedConversation(UUID())

        XCTAssertEqual(store.savedConversationID, activeSavedID)
        XCTAssertEqual(store.savedTurnCount, 1)
        XCTAssertEqual(store.unsavedTurnCount, 0)
        XCTAssertFalse(store.hasUnsavedChanges)
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
        XCTAssertEqual(store.turns.first?.status, .answered)
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

    func test所有問答API錯誤都有可恢復的安全訊息() async throws {
        let cases: [(OpenAIResponsesInterpreter.InterpreterError, String)] = [
            (.invalidRequest, "無法建立"),
            (.connectionFailed, "無法連上"),
            (.timedOut, "逾時"),
            (.unauthorized, "授權"),
            (.rateLimited, "速率"),
            (.httpError(404), "endpoint"),
            (.httpError(500), "無法完成"),
            (.refusal, "拒絕"),
            (.emptyResponse, "沒有產生"),
            (.invalidResponse, "格式不相容"),
            (.responseTooLarge, "超過"),
            (.invalidGeneratedContent, "格式不相容")
        ]

        for (error, expectedText) in cases {
            let defaults = UserDefaults(suiteName: "ChartAssistantErrorTests.\(UUID().uuidString)")!
            let store = ChartAssistantStore(
                answerer: SequenceConversationAnswerer(results: [.failure(error)]),
                defaults: defaults
            )
            store.select(makeAssistantChart())
            store.draft = "保留問題"
            store.send(configuration: try makeConfiguration(apiKey: nil))
            await waitForRequestToFinish(store)

            guard case .failed(let message) = store.requestState else {
                return XCTFail("\(error) 應轉成失敗狀態")
            }
            XCTAssertTrue(message.contains(expectedText), "\(error) 的訊息不具體：\(message)")
            XCTAssertEqual(store.draft, "保留問題")
            XCTAssertTrue(store.turns.isEmpty)
        }
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
