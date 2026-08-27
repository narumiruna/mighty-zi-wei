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

    static func resetPersistentStore(arguments: [String]) throws {
        guard !arguments.contains("-UITestResetData") else { return }
        try AppModelStoreResetter().resetDefaultStoreFiles()
    }
}

struct AppModelStoreResetter {
    var fileManager = FileManager.default
    var storeDirectory: URL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory

    func resetDefaultStoreFiles() throws {
        guard fileManager.fileExists(atPath: storeDirectory.path) else { return }
        let defaultStoreFileNames: Set<String> = [
            "default.store",
            "default.store-shm",
            "default.store-wal"
        ]
        let storeFiles = try fileManager.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil
        ).filter { defaultStoreFileNames.contains($0.lastPathComponent) }

        for file in storeFiles {
            try fileManager.removeItem(at: file)
        }
    }
}

enum PersistenceResetError: Error, Equatable {
    case authenticationFailed
    case reloadFailed
}

struct PersistenceResetReloadValidator {
    func validate<Success>(_ result: Result<Success, any Error>) throws {
        guard case .success = result else {
            throw PersistenceResetError.reloadFailed
        }
    }
}

struct PersistenceRecoveryMessage {
    static let unavailable = "系統目前無法讀取這台裝置的本機資料。"

    static func resetFailure(for error: any Error) -> String {
        guard let resetError = error as? PersistenceResetError else {
            return "目前無法重建本機資料。請確認裝置有足夠儲存空間後再試。"
        }
        switch resetError {
        case .authenticationFailed:
            return "身分驗證未完成，本機資料未重建。"
        case .reloadFailed:
            return "本機資料已清除，但仍無法建立新的資料庫。請確認裝置有足夠儲存空間後再試。"
        }
    }
}

@main
struct MightyZiWeiApp: App {
    @State private var modelContainerResult: Result<ModelContainer, any Error>
    @State private var aiConfigurationStore: AIConfigurationStore
    @State private var aiUsageStore: AIUsageStore
    @State private var appLockStore: AppLockStore
    @State private var iCloudSyncCoordinator: ICloudSyncCoordinator
    @State private var voiceCoordinator: VoiceCoordinator

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _modelContainerResult = State(
            initialValue: AppModelContainerLoader.load(arguments: arguments)
        )
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
            switch modelContainerResult {
            case .success(let modelContainer):
                RootView()
                    .environment(aiConfigurationStore)
                    .environment(aiUsageStore)
                    .environment(appLockStore)
                    .environment(iCloudSyncCoordinator)
                    .environment(voiceCoordinator)
                    .modelContainer(modelContainer)
            case .failure:
                PersistenceUnavailableView(
                    retry: reloadModelContainer,
                    resetAndReload: resetPersistentStoreAndReload
                )
            }
        }
    }

    private func reloadModelContainer() {
        modelContainerResult = AppModelContainerLoader.load(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private func resetPersistentStoreAndReload() async throws {
        guard await appLockStore.authorizeDataReset() else {
            throw PersistenceResetError.authenticationFailed
        }

        let arguments = ProcessInfo.processInfo.arguments
        try AppModelContainerLoader.resetPersistentStore(arguments: arguments)
        await ReviewReminderScheduler().cancelAllReviewReminders()
        PinnedChartShortcut.reconcile(charts: [])

        let reloadResult = AppModelContainerLoader.load(arguments: arguments)
        modelContainerResult = reloadResult
        try PersistenceResetReloadValidator().validate(reloadResult)
    }
}

private struct PersistenceUnavailableView: View {
    let retry: () -> Void
    let resetAndReload: () async throws -> Void

    @State private var isShowingResetConfirmation = false
    @State private var resetErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label("無法載入本機資料", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("你可以先重試。若仍無法開啟，可重建空白本機資料庫讓 App 立即恢復使用。")
                } actions: {
                    VStack(spacing: 12) {
                        Button("再試一次", action: retry)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("startup.persistenceRetry")

                        Button("重建空白本機資料") {
                            isShowingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityIdentifier("startup.persistenceReset")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("重建會刪除這台裝置上的本機命盤、筆記、收藏與對話。")
                    Text("如果你之前已開啟 iCloud 同步，重建後可到設定重新同步。")
                    Text(PersistenceRecoveryMessage.unavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .accessibilityIdentifier("startup.persistenceUnavailable")
        .confirmationDialog(
            "確定要重建本機資料？",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("重建空白本機資料", role: .destructive) {
                Task {
                    do {
                        try await resetAndReload()
                    } catch {
                        resetErrorMessage = PersistenceRecoveryMessage.resetFailure(for: error)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這只會清除這台裝置的本機資料。已存在 iCloud 的資料不會因這個動作被刪除。")
        }
        .alert("重建失敗", isPresented: resetErrorMessageBinding) {
            Button("好", role: .cancel) {
                resetErrorMessage = nil
            }
        } message: {
            Text(resetErrorMessage ?? "請稍後再試。")
        }
    }

    private var resetErrorMessageBinding: Binding<Bool> {
        Binding(
            get: { resetErrorMessage != nil },
            set: { isPresented in
                if !isPresented { resetErrorMessage = nil }
            }
        )
    }
}

private struct PersistenceUnavailableViewPreview: PreviewProvider {
    static var previews: some View {
        PersistenceUnavailableView(
            retry: {},
            resetAndReload: {}
        )
    }
}
