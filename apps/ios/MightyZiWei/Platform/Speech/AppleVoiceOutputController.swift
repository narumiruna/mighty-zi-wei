import AVFAudio
import Foundation

@MainActor
final class AppleVoiceOutputController: NSObject, VoiceOutputControlling {
  enum VoiceOutputError: LocalizedError {
    case unavailableVoice
    case emptyText

    var errorDescription: String? {
      switch self {
      case .unavailableVoice:
        "這台 iPhone 目前沒有可用的正體中文語音，文字仍可正常閱讀。"
      case .emptyText:
        "這段內容目前無法朗讀。"
      }
    }
  }

  var eventHandler: (@MainActor @Sendable (VoiceOutputEvent) -> Void)?

  private let synthesizer: AVSpeechSynthesizer
  private var currentUtteranceID: ObjectIdentifier?

  override init() {
    synthesizer = AVSpeechSynthesizer()
    super.init()
    synthesizer.delegate = self
  }

  func speak(text: String) throws {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      throw VoiceOutputError.emptyText
    }
    guard let voice = AVSpeechSynthesisVoice(language: "zh-TW") else {
      throw VoiceOutputError.unavailableVoice
    }

    if synthesizer.isSpeaking || synthesizer.isPaused {
      stop()
    }

    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try audioSession.setActive(true)

    let utterance = AVSpeechUtterance(string: trimmedText)
    utterance.voice = voice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.prefersAssistiveTechnologySettings = true
    currentUtteranceID = ObjectIdentifier(utterance)
    synthesizer.speak(utterance)
  }

  func pause() {
    guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
    if !synthesizer.pauseSpeaking(at: .word) {
      synthesizer.stopSpeaking(at: .immediate)
      currentUtteranceID = nil
      deactivateAudioSession()
      eventHandler?(.failed(message: "目前無法暫停朗讀，請停止後再試。"))
    }
  }

  func resume() {
    guard synthesizer.isPaused else { return }
    if !synthesizer.continueSpeaking() {
      synthesizer.stopSpeaking(at: .immediate)
      currentUtteranceID = nil
      deactivateAudioSession()
      eventHandler?(.failed(message: "目前無法繼續朗讀，請重新開始。"))
    }
  }

  func stop() {
    guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
    currentUtteranceID = nil
    synthesizer.stopSpeaking(at: .immediate)
    deactivateAudioSession()
    eventHandler?(.cancelled)
  }

  private func handle(
    _ event: VoiceOutputEvent,
    utteranceID: ObjectIdentifier,
    completesPlayback: Bool
  ) {
    guard currentUtteranceID == utteranceID else { return }
    if completesPlayback {
      currentUtteranceID = nil
      deactivateAudioSession()
    }
    eventHandler?(event)
  }

  private func deactivateAudioSession() {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: [.notifyOthersOnDeactivation]
    )
  }
}

extension AppleVoiceOutputController: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.handle(
        .started,
        utteranceID: utteranceID,
        completesPlayback: false
      )
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didPause utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.handle(
        .paused,
        utteranceID: utteranceID,
        completesPlayback: false
      )
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didContinue utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.handle(
        .resumed,
        utteranceID: utteranceID,
        completesPlayback: false
      )
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.handle(
        .finished,
        utteranceID: utteranceID,
        completesPlayback: true
      )
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    let utteranceID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.handle(
        .cancelled,
        utteranceID: utteranceID,
        completesPlayback: true
      )
    }
  }
}
