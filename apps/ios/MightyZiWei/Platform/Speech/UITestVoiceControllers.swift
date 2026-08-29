import Foundation

@MainActor
final class UITestVoiceInputController: VoiceInputControlling {
  private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?

  func start(
    eventHandler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void
  ) async throws {
    self.eventHandler = eventHandler
    try await Task.sleep(for: .milliseconds(300))
    eventHandler(
      .transcription(
        text: "語音輸入的命盤問題",
        isFinal: false
      )
    )
  }

  func finish() async {
    try? await Task.sleep(for: .milliseconds(300))
    eventHandler?(
      .transcription(
        text: "語音輸入的命盤問題。",
        isFinal: true
      )
    )
    eventHandler = nil
  }

  func cancel() async {
    eventHandler = nil
  }
}

@MainActor
final class UITestVoiceOutputController: VoiceOutputControlling {
  var eventHandler: (@MainActor @Sendable (VoiceOutputEvent) -> Void)?

  func speak(text: String) throws {
    eventHandler?(.started)
  }

  func pause() {
    eventHandler?(.paused)
  }

  func resume() {
    eventHandler?(.resumed)
  }

  func stop() {
    eventHandler?(.cancelled)
  }
}
