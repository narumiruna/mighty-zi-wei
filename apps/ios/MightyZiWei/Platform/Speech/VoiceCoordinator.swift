import Foundation
import Observation

@MainActor
protocol VoiceInputControlling: AnyObject {
  func start(eventHandler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void) async throws
  func finish() async
  func cancel() async
}

@MainActor
protocol VoiceOutputControlling: AnyObject {
  var eventHandler: (@MainActor @Sendable (VoiceOutputEvent) -> Void)? { get set }

  func speak(text: String) throws
  func pause()
  func resume()
  func stop()
}

enum VoiceInputEvent: Equatable, Sendable {
  case transcription(text: String, isFinal: Bool)
  case interrupted(message: String)
}

enum VoiceOutputEvent: Equatable, Sendable {
  case started
  case paused
  case resumed
  case finished
  case cancelled
  case failed(message: String)
}

struct VoiceDraftComposer: Equatable, Sendable {
  let initialDraft: String
  let limit: Int
  private(set) var recognizedText = ""

  init(initialDraft: String, limit: Int) {
    self.initialDraft = initialDraft
    self.limit = max(0, limit)
  }

  mutating func updateRecognizedText(_ text: String) -> (draft: String, reachedLimit: Bool) {
    recognizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let combined = Self.combine(initialDraft: initialDraft, recognizedText: recognizedText)
    guard combined.count > limit else {
      return (combined, false)
    }
    return (String(combined.prefix(limit)), true)
  }

  private static func combine(initialDraft: String, recognizedText: String) -> String {
    guard !recognizedText.isEmpty else { return initialDraft }
    guard !initialDraft.isEmpty else { return recognizedText }
    let needsSeparator = initialDraft.last?.isWhitespace == false
    return initialDraft + (needsSeparator ? " " : "") + recognizedText
  }
}

@MainActor
@Observable
final class VoiceCoordinator {
  enum InputState: Equatable {
    case idle
    case preparing
    case recording
    case finalizing
    case failed(message: String)
  }

  enum OutputState: Equatable {
    case idle
    case speaking(contentID: String)
    case paused(contentID: String)
    case failed(contentID: String?, message: String)
  }

  struct InputControl: Equatable, Sendable {
    let systemImage: String
    let label: String
    let hint: String
    let value: String
    let isEnabled: Bool
  }

  private let inputController: any VoiceInputControlling
  private let outputController: any VoiceOutputControlling
  private var inputTask: Task<Void, Never>?
  private var inputSessionID: UUID?
  private var inputCleanupID: UUID?
  private var draftComposer: VoiceDraftComposer?
  private var draftHandler: (@MainActor @Sendable (String) -> Void)?
  private var outputRequestID: UUID?
  private var activeOutputContentID: String?

  private(set) var inputState: InputState = .idle
  private(set) var outputState: OutputState = .idle

  init(
    inputController: (any VoiceInputControlling)? = nil,
    outputController: (any VoiceOutputControlling)? = nil
  ) {
    self.inputController = inputController ?? AppleVoiceInputController()
    self.outputController = outputController ?? AppleVoiceOutputController()
    self.outputController.eventHandler = { [weak self] event in
      self?.receiveOutput(event)
    }
  }

  var isInputActive: Bool {
    switch inputState {
    case .preparing, .recording, .finalizing:
      true
    case .idle, .failed:
      false
    }
  }

  var inputStatusMessage: String? {
    switch inputState {
    case .idle:
      nil
    case .preparing:
      "正在準備正體中文語音辨識…"
    case .recording:
      "正在聆聽，點一下停止並保留文字。"
    case .finalizing:
      "正在結束語音輸入…"
    case .failed(let message):
      message
    }
  }

  var inputControl: InputControl {
    switch inputState {
    case .idle:
      InputControl(
        systemImage: "mic.circle.fill",
        label: "開始語音輸入",
        hint: "將說出的問題填入草稿，不會自動送出",
        value: "未收音",
        isEnabled: true
      )
    case .preparing:
      InputControl(
        systemImage: "xmark.circle.fill",
        label: "取消語音輸入",
        hint: "取消語音辨識準備並保留原有草稿",
        value: "正在準備語音辨識",
        isEnabled: true
      )
    case .recording:
      InputControl(
        systemImage: "stop.circle.fill",
        label: "停止語音輸入",
        hint: "停止聆聽並保留已辨識文字",
        value: "正在收音",
        isEnabled: true
      )
    case .finalizing:
      InputControl(
        systemImage: "hourglass.circle.fill",
        label: "正在結束語音輸入",
        hint: "請稍候，結束後即可編輯或送出草稿",
        value: "正在結束語音輸入",
        isEnabled: false
      )
    case .failed:
      InputControl(
        systemImage: "mic.circle.fill",
        label: "重新開始語音輸入",
        hint: "再次嘗試將說出的問題填入草稿",
        value: "語音輸入未完成",
        isEnabled: true
      )
    }
  }

  var outputContentID: String? {
    switch outputState {
    case .speaking(let contentID), .paused(let contentID):
      contentID
    case .idle, .failed:
      nil
    }
  }

  var outputStatusContentID: String? {
    switch outputState {
    case .speaking(let contentID), .paused(let contentID):
      contentID
    case .failed(let contentID, _):
      contentID
    case .idle:
      nil
    }
  }

  func startInput(
    initialDraft: String,
    limit: Int,
    draftHandler: @escaping @MainActor @Sendable (String) -> Void
  ) {
    guard !isInputActive else { return }
    guard limit > 0, initialDraft.count < limit else {
      inputState = .failed(
        message: "問題草稿已達 \(limit) 字上限，請先修改文字再使用語音輸入。"
      )
      return
    }
    stopOutput()
    inputTask?.cancel()
    let sessionID = UUID()
    inputCleanupID = nil
    inputSessionID = sessionID
    self.draftComposer = VoiceDraftComposer(initialDraft: initialDraft, limit: limit)
    self.draftHandler = draftHandler
    inputState = .preparing
    inputTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await inputController.start { [weak self] event in
          guard self?.inputSessionID == sessionID else { return }
          self?.receiveInput(event)
        }
        try Task.checkCancellation()
        guard inputSessionID == sessionID else { return }
        if inputState == .preparing {
          inputState = .recording
        }
      } catch is CancellationError {
        guard inputSessionID == sessionID else { return }
        await inputController.cancel()
        guard inputSessionID == sessionID else { return }
        resetInput(state: .idle, restoresInitialDraft: true)
      } catch {
        guard inputSessionID == sessionID else { return }
        await inputController.cancel()
        guard inputSessionID == sessionID else { return }
        resetInput(
          state: .failed(message: Self.inputErrorMessage(error)),
          restoresInitialDraft: true
        )
      }
    }
  }

  func finishInput() {
    switch inputState {
    case .preparing:
      cancelInput(restoresInitialDraft: false)
    case .recording:
      guard let sessionID = inputSessionID else { return }
      inputTask?.cancel()
      inputState = .finalizing
      inputTask = Task { [weak self] in
        guard let self else { return }
        await inputController.finish()
        guard inputSessionID == sessionID else { return }
        resetInput(state: .idle, restoresInitialDraft: false)
      }
    case .idle, .finalizing, .failed:
      return
    }
  }

  func cancelInput(
    restoresInitialDraft: Bool,
    completion: (@MainActor @Sendable () -> Void)? = nil
  ) {
    guard inputState != .idle else {
      completion?()
      return
    }
    let cleanupID = UUID()
    inputSessionID = nil
    inputCleanupID = cleanupID
    inputTask?.cancel()
    inputState = .finalizing
    inputTask = Task { [weak self] in
      guard let self else { return }
      await inputController.cancel()
      guard inputCleanupID == cleanupID, inputSessionID == nil else { return }
      resetInput(state: .idle, restoresInitialDraft: restoresInitialDraft)
      completion?()
    }
  }

  func speak(contentID: String, text: String) {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      outputState = .failed(
        contentID: contentID,
        message: "這段內容目前無法朗讀。"
      )
      return
    }

    let requestID = UUID()
    outputRequestID = requestID
    if isInputActive {
      cancelInput(restoresInitialDraft: false) { [weak self] in
        guard self?.outputRequestID == requestID else { return }
        self?.startOutput(
          requestID: requestID,
          contentID: contentID,
          text: trimmedText
        )
      }
    } else {
      startOutput(
        requestID: requestID,
        contentID: contentID,
        text: trimmedText
      )
    }
  }

  func pauseOutput() {
    guard case .speaking(let contentID) = outputState else { return }
    outputState = .paused(contentID: contentID)
    outputController.pause()
  }

  func resumeOutput() {
    guard case .paused(let contentID) = outputState else { return }
    outputState = .speaking(contentID: contentID)
    outputController.resume()
  }

  func stopOutput() {
    outputRequestID = nil
    guard outputState != .idle else { return }
    outputController.stop()
    activeOutputContentID = nil
    outputState = .idle
  }

  func stopAll(
    completion: (@MainActor @Sendable () -> Void)? = nil
  ) {
    stopOutput()
    if isInputActive {
      cancelInput(
        restoresInitialDraft: false,
        completion: completion
      )
    } else {
      completion?()
    }
  }

  private func receiveInput(_ event: VoiceInputEvent) {
    switch event {
    case .transcription(let text, _):
      guard var draftComposer else { return }
      let update = draftComposer.updateRecognizedText(text)
      self.draftComposer = draftComposer
      draftHandler?(update.draft)
      if update.reachedLimit {
        failInput(
          message: "語音輸入已達 \(draftComposer.limit) 字上限，已保留目前文字。"
        )
      }
    case .interrupted(let message):
      failInput(message: message)
    }
  }

  private func startOutput(
    requestID: UUID,
    contentID: String,
    text: String
  ) {
    guard outputRequestID == requestID else { return }
    outputController.stop()
    outputRequestID = requestID
    activeOutputContentID = contentID
    do {
      try outputController.speak(text: text)
      outputState = .speaking(contentID: contentID)
    } catch {
      outputRequestID = nil
      activeOutputContentID = nil
      outputState = .failed(
        contentID: contentID,
        message: Self.outputErrorMessage(error)
      )
    }
  }

  private func receiveOutput(_ event: VoiceOutputEvent) {
    guard let contentID = activeOutputContentID else { return }
    switch event {
    case .started, .resumed:
      outputState = .speaking(contentID: contentID)
    case .paused:
      outputState = .paused(contentID: contentID)
    case .finished, .cancelled:
      outputRequestID = nil
      activeOutputContentID = nil
      outputState = .idle
    case .failed(let message):
      outputRequestID = nil
      activeOutputContentID = nil
      outputState = .failed(contentID: contentID, message: message)
    }
  }

  private func failInput(message: String) {
    let cleanupID = UUID()
    inputSessionID = nil
    inputCleanupID = cleanupID
    inputTask?.cancel()
    inputState = .finalizing
    inputTask = Task { [weak self] in
      guard let self else { return }
      await inputController.cancel()
      guard inputCleanupID == cleanupID, inputSessionID == nil else { return }
      resetInput(
        state: .failed(message: message),
        restoresInitialDraft: false
      )
    }
  }

  private func resetInput(state: InputState, restoresInitialDraft: Bool) {
    if restoresInitialDraft, let draftComposer {
      draftHandler?(draftComposer.initialDraft)
    }
    inputTask = nil
    inputSessionID = nil
    inputCleanupID = nil
    draftComposer = nil
    draftHandler = nil
    inputState = state
  }

  private static func inputErrorMessage(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription
    {
      return description
    }
    return "目前無法使用語音輸入，請稍後再試或繼續使用鍵盤。"
  }

  private static func outputErrorMessage(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription
    {
      return description
    }
    return "目前無法朗讀這段內容，文字仍可正常閱讀。"
  }
}
