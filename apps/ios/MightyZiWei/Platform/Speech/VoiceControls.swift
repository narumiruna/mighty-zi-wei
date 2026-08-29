import Accessibility
import SwiftUI

struct VoicePlaybackControls: View {
  let contentID: String
  let text: String

  @Environment(VoiceCoordinator.self) private var voiceCoordinator
  @State private var wasActive = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if voiceCoordinator.outputContentID == contentID {
        HStack(spacing: 10) {
          Button {
            togglePause()
          } label: {
            Label(
              isPaused ? "繼續" : "暫停",
              systemImage: isPaused ? "play.fill" : "pause.fill"
            )
          }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("voice.output.toggle.\(contentID)")

          Button(role: .cancel) {
            voiceCoordinator.stopOutput()
          } label: {
            Label("停止", systemImage: "stop.fill")
          }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("voice.output.stop.\(contentID)")
        }
        .accessibilityElement(children: .contain)
      } else {
        Button {
          voiceCoordinator.speak(contentID: contentID, text: text)
        } label: {
          Label("朗讀", systemImage: "speaker.wave.2")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("朗讀這一段文字，不會傳送到第三方服務")
        .accessibilityIdentifier("voice.output.start.\(contentID)")
      }

      if case .failed(let failedContentID, let message) = voiceCoordinator.outputState,
        failedContentID == contentID
      {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("voice.output.error.\(contentID)")
      }
    }
    .onChange(of: voiceCoordinator.outputState) { _, state in
      switch state {
      case .speaking(let activeID) where activeID == contentID:
        wasActive = true
        AccessibilityNotification.Announcement("已開始朗讀。")
          .post()
      case .paused(let activeID) where activeID == contentID:
        wasActive = true
        AccessibilityNotification.Announcement("已暫停朗讀。")
          .post()
      case .idle where wasActive:
        wasActive = false
        AccessibilityNotification.Announcement("已停止朗讀。")
          .post()
      case .failed(let failedID, _) where failedID == contentID:
        wasActive = false
        AccessibilityNotification.Announcement("朗讀未完成，文字仍可正常閱讀。")
          .post()
      case .speaking, .paused:
        wasActive = false
      default:
        break
      }
    }
  }

  private var isPaused: Bool {
    if case .paused(let activeID) = voiceCoordinator.outputState {
      return activeID == contentID
    }
    return false
  }

  private func togglePause() {
    if isPaused {
      voiceCoordinator.resumeOutput()
    } else {
      voiceCoordinator.pauseOutput()
    }
  }
}
