import SwiftData
import SwiftUI

private struct UITestCredentialStore: APICredentialStoring {
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ apiKey: String?) throws {}
}

@main
struct MightyZiWeiApp: App {
    @State private var aiConfigurationStore: AIConfigurationStore
    @State private var voiceCoordinator: VoiceCoordinator

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestMockSpeech") {
            _voiceCoordinator = State(
                initialValue: VoiceCoordinator(
                    inputController: UITestVoiceInputController(),
                    outputController: UITestVoiceOutputController()
                )
            )
        } else {
            _voiceCoordinator = State(initialValue: VoiceCoordinator())
        }

        if arguments.contains("-UITestMockAI") {
            let defaults = UserDefaults(suiteName: "MightyZiWei.UITesting.AI")!
            defaults.removePersistentDomain(forName: "MightyZiWei.UITesting.AI")
            let store = AIConfigurationStore(
                defaults: defaults,
                credentialStore: UITestCredentialStore()
            )
            try? store.save(
                endpoint: "https://example.com/v1",
                model: "ui-test-model",
                apiKey: ""
            )
            _aiConfigurationStore = State(initialValue: store)
        } else {
            _aiConfigurationStore = State(initialValue: AIConfigurationStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(aiConfigurationStore)
                .environment(voiceCoordinator)
        }
        .modelContainer(for: SavedChart.self)
    }
}
