import SwiftData
import SwiftUI

private struct UITestCredentialStore: APICredentialStoring {
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ apiKey: String?) throws {}
}

enum AppModelContainerLoader {
    static func load(arguments: [String]) -> Result<ModelContainer, any Error> {
        let schema = Schema([
            SavedChart.self,
            SavedInsight.self,
            SavedConversation.self,
            CloudDeletion.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: arguments.contains("-UITestResetData")
        )
        return load {
            try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    static func load(
        makeContainer: () throws -> ModelContainer
    ) -> Result<ModelContainer, any Error> {
        do {
            return .success(try makeContainer())
        } catch {
            return .failure(error)
        }
    }
}

@main
struct MightyZiWeiApp: App {
    private let modelContainer: ModelContainer?
    @State private var aiConfigurationStore: AIConfigurationStore
    @State private var aiUsageStore: AIUsageStore
    @State private var appLockStore: AppLockStore
    @State private var iCloudSyncCoordinator: ICloudSyncCoordinator
    @State private var voiceCoordinator: VoiceCoordinator

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        switch AppModelContainerLoader.load(arguments: arguments) {
        case .success(let container):
            modelContainer = container
        case .failure:
            modelContainer = nil
        }
        _aiUsageStore = State(initialValue: AIUsageStore())
        _appLockStore = State(initialValue: AppLockStore())
        _iCloudSyncCoordinator = State(initialValue: ICloudSyncCoordinator())
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
            if let modelContainer {
                RootView()
                    .environment(aiConfigurationStore)
                    .environment(aiUsageStore)
                    .environment(appLockStore)
                    .environment(iCloudSyncCoordinator)
                    .environment(voiceCoordinator)
                    .modelContainer(modelContainer)
            } else {
                PersistenceUnavailableView()
            }
        }
    }
}

private struct PersistenceUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("無法載入本機資料", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("請完全關閉 App 後再試一次。原有資料不會被清除。")
        }
        .accessibilityIdentifier("startup.persistenceUnavailable")
    }
}
