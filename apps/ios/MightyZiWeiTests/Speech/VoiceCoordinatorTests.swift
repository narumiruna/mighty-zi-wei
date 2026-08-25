import CoreMedia
import XCTest
@testable import MightyZiWei

@MainActor
final class VoiceCoordinatorTests: XCTestCase {
    func test草稿保留既有文字並替換逐步辨識結果() {
        var composer = VoiceDraftComposer(initialDraft: "原本問題", limit: 20)

        XCTAssertEqual(
            composer.updateRecognizedText("命宮").draft,
            "原本問題 命宮"
        )
        XCTAssertEqual(
            composer.updateRecognizedText("命宮有什麼特色").draft,
            "原本問題 命宮有什麼特色"
        )
    }

    func test草稿達上限時只保留合法字數() {
        var composer = VoiceDraftComposer(initialDraft: "原本", limit: 6)

        let result = composer.updateRecognizedText("一二三四五六")

        XCTAssertEqual(result.draft, "原本 一二三")
        XCTAssertEqual(result.draft.count, 6)
        XCTAssertTrue(result.reachedLimit)
    }

    func test辨識片段依時間替換而不重複() {
        var transcript = VoiceTranscriptAccumulator()

        XCTAssertEqual(
            transcript.update(
                text: "紫微",
                range: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
                isFinal: false
            ),
            "紫微"
        )
        XCTAssertEqual(
            transcript.update(
                text: "紫微斗數",
                range: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 1_000)),
                isFinal: true
            ),
            "紫微斗數"
        )
        XCTAssertEqual(
            transcript.update(
                text: "命宮",
                range: CMTimeRange(
                    start: CMTime(seconds: 2, preferredTimescale: 1_000),
                    duration: CMTime(seconds: 1, preferredTimescale: 1_000)
                ),
                isFinal: true
            ),
            "紫微斗數命宮"
        )
    }

    func test已Final片段不會被較晚到達的Volatile結果覆蓋() {
        var transcript = VoiceTranscriptAccumulator()
        let range = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1, preferredTimescale: 1_000)
        )

        XCTAssertEqual(
            transcript.update(text: "命宮", range: range, isFinal: true),
            "命宮"
        )
        XCTAssertEqual(
            transcript.update(text: "命", range: range, isFinal: false),
            "命宮"
        )
    }

    func test語音輸入只更新草稿且停止後保留文字() async {
        let input = FakeVoiceInputController()
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: output
        )
        var draft = "原本"

        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        await waitUntil { coordinator.inputState == .recording }
        input.emit(.transcription(text: "命盤問題", isFinal: false))
        XCTAssertEqual(draft, "原本 命盤問題")

        coordinator.finishInput()
        await waitUntil { coordinator.inputState == .idle }

        XCTAssertEqual(input.finishCount, 1)
        XCTAssertEqual(draft, "原本 命盤問題")
    }

    func test取消可選擇恢復錄音前草稿() async {
        let input = FakeVoiceInputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = "錄音前"

        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        await waitUntil { coordinator.inputState == .recording }
        input.emit(.transcription(text: "暫時文字", isFinal: false))
        coordinator.cancelInput(restoresInitialDraft: true)
        await waitUntil { coordinator.inputState == .idle }

        XCTAssertEqual(input.cancelCount, 1)
        XCTAssertEqual(draft, "錄音前")
    }

    func test準備期間取消不會由過期Task恢復已送出的草稿() async {
        let input = FakeVoiceInputController()
        input.startDelay = .milliseconds(100)
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = "準備送出"

        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        coordinator.cancelInput(restoresInitialDraft: false)
        draft = ""
        await waitUntil { coordinator.inputState == .idle }
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(draft, "")
        XCTAssertGreaterThanOrEqual(input.cancelCount, 1)
    }

    func test權限或資產錯誤顯示安全訊息並恢復草稿() async {
        let input = FakeVoiceInputController()
        input.startError = TestVoiceError(message: "正體中文語音資產無法準備。")
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = "保留我"

        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        await waitUntil {
            coordinator.inputState == .failed(message: "正體中文語音資產無法準備。")
        }

        XCTAssertEqual(draft, "保留我")
        XCTAssertEqual(input.cancelCount, 1)
    }

    func test超過字數會停止輸入並保留上限內文字() async {
        let input = FakeVoiceInputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = ""

        coordinator.startInput(initialDraft: draft, limit: 5) { draft = $0 }
        await waitUntil { coordinator.inputState == .recording }
        input.emit(.transcription(text: "一二三四五六", isFinal: false))
        await waitUntil {
            coordinator.inputState == .failed(
                message: "語音輸入已達 5 字上限，已保留目前文字。"
            )
        }

        XCTAssertEqual(draft, "一二三四五")
        XCTAssertEqual(input.cancelCount, 1)
    }

    func test開始朗讀會停止錄音且支援暫停繼續與停止() async {
        let input = FakeVoiceInputController()
        input.cancelDelay = .milliseconds(50)
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: output
        )

        coordinator.startInput(initialDraft: "", limit: 500) { _ in }
        await waitUntil { coordinator.inputState == .recording }
        coordinator.speak(contentID: "answer.1", text: "命盤回答")
        XCTAssertTrue(output.spokenTexts.isEmpty)
        await waitUntil {
            coordinator.outputState == .speaking(contentID: "answer.1")
        }

        XCTAssertEqual(input.cancelCount, 1)
        XCTAssertEqual(output.spokenTexts, ["命盤回答"])

        coordinator.pauseOutput()
        XCTAssertEqual(coordinator.outputState, .paused(contentID: "answer.1"))
        coordinator.resumeOutput()
        XCTAssertEqual(coordinator.outputState, .speaking(contentID: "answer.1"))
        coordinator.stopOutput()
        XCTAssertEqual(coordinator.outputState, .idle)
        XCTAssertEqual(output.pauseCount, 1)
        XCTAssertEqual(output.resumeCount, 1)
        XCTAssertGreaterThanOrEqual(output.stopCount, 1)
    }

    func test草稿已達上限時不會啟動麥克風或修改文字() {
        let input = FakeVoiceInputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = "一二三四五"

        coordinator.startInput(initialDraft: draft, limit: 5) { draft = $0 }

        XCTAssertEqual(
            coordinator.inputState,
            .failed(message: "問題草稿已達 5 字上限，請先修改文字再使用語音輸入。")
        )
        XCTAssertEqual(input.startCount, 0)
        XCTAssertEqual(draft, "一二三四五")
    }

    func test語音輸入中斷會保留目前文字並可重試() async {
        let input = FakeVoiceInputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: FakeVoiceOutputController()
        )
        var draft = ""

        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        await waitUntil { coordinator.inputState == .recording }
        input.emit(.transcription(text: "保留內容", isFinal: true))
        input.emit(.interrupted(message: "麥克風已中斷。"))
        await waitUntil {
            coordinator.inputState == .failed(message: "麥克風已中斷。")
        }

        XCTAssertEqual(draft, "保留內容")
        coordinator.startInput(initialDraft: draft, limit: 500) { draft = $0 }
        await waitUntil { coordinator.inputState == .recording }
    }

    func test停止所有語音會取消等待中的朗讀切換() async {
        let input = FakeVoiceInputController()
        input.cancelDelay = .milliseconds(100)
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: output
        )

        coordinator.startInput(initialDraft: "", limit: 500) { _ in }
        await waitUntil { coordinator.inputState == .recording }
        coordinator.speak(contentID: "answer", text: "不該播放")
        coordinator.stopAll()
        await waitUntil { coordinator.inputState == .idle }
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(output.spokenTexts.isEmpty)
        XCTAssertEqual(coordinator.outputState, .idle)
    }

    func test停止所有語音會清理輸入與輸出() async {
        let input = FakeVoiceInputController()
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: input,
            outputController: output
        )

        coordinator.startInput(initialDraft: "", limit: 500) { _ in }
        await waitUntil { coordinator.inputState == .recording }
        coordinator.stopAll()
        await waitUntil { coordinator.inputState == .idle }
        XCTAssertEqual(input.cancelCount, 1)

        coordinator.speak(contentID: "answer", text: "回答")
        coordinator.stopAll()
        XCTAssertEqual(coordinator.outputState, .idle)
        XCTAssertGreaterThanOrEqual(output.stopCount, 2)
    }

    func test朗讀失敗顯示在指定內容且文字流程不受影響() {
        let output = FakeVoiceOutputController()
        output.speakError = TestVoiceError(message: "沒有正體中文語音。")
        let coordinator = VoiceCoordinator(
            inputController: FakeVoiceInputController(),
            outputController: output
        )

        coordinator.speak(contentID: "section", text: "仍可閱讀")

        XCTAssertEqual(
            coordinator.outputState,
            .failed(contentID: "section", message: "沒有正體中文語音。")
        )
    }

    func test所有系統語音輸入錯誤都有正體中文說明() {
        let errors: [AppleVoiceInputController.VoiceInputError] = [
            .speechPermissionDenied,
            .speechPermissionRestricted,
            .microphonePermissionDenied,
            .unsupportedLocale,
            .unavailableAudioFormat,
            .microphoneUnavailable,
            .assetPreparationFailed
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertNotEqual(error.localizedDescription, "The operation couldn’t be completed.")
        }
    }

    func test朗讀完成Callback會清除目前內容() {
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: FakeVoiceInputController(),
            outputController: output
        )

        coordinator.speak(contentID: "section", text: "內容")
        output.emit(.finished)

        XCTAssertEqual(coordinator.outputState, .idle)
        XCTAssertNil(coordinator.outputContentID)
    }

    func test切換朗讀內容會先停止舊內容() {
        let output = FakeVoiceOutputController()
        let coordinator = VoiceCoordinator(
            inputController: FakeVoiceInputController(),
            outputController: output
        )

        coordinator.speak(contentID: "section.1", text: "第一段")
        coordinator.speak(contentID: "section.2", text: "第二段")

        XCTAssertEqual(output.spokenTexts, ["第一段", "第二段"])
        XCTAssertEqual(output.stopCount, 2)
        XCTAssertEqual(coordinator.outputState, .speaking(contentID: "section.2"))
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private struct TestVoiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class FakeVoiceInputController: VoiceInputControlling {
    var startError: Error?
    var startDelay: Duration?
    var cancelDelay: Duration?
    private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0

    func start(
        eventHandler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void
    ) async throws {
        startCount += 1
        if let startDelay {
            try await Task.sleep(for: startDelay)
        }
        if let startError { throw startError }
        self.eventHandler = eventHandler
    }

    func finish() async {
        finishCount += 1
        eventHandler = nil
    }

    func cancel() async {
        if let cancelDelay {
            try? await Task.sleep(for: cancelDelay)
        }
        cancelCount += 1
        eventHandler = nil
    }

    func emit(_ event: VoiceInputEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class FakeVoiceOutputController: VoiceOutputControlling {
    var eventHandler: (@MainActor @Sendable (VoiceOutputEvent) -> Void)?
    var speakError: Error?
    private(set) var spokenTexts: [String] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    func speak(text: String) throws {
        if let speakError { throw speakError }
        spokenTexts.append(text)
        eventHandler?(.started)
    }

    func pause() {
        pauseCount += 1
        eventHandler?(.paused)
    }

    func resume() {
        resumeCount += 1
        eventHandler?(.resumed)
    }

    func stop() {
        stopCount += 1
        eventHandler?(.cancelled)
    }

    func emit(_ event: VoiceOutputEvent) {
        eventHandler?(event)
    }
}
