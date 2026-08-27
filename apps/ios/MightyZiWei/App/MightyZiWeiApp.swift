import SwiftData
import SwiftUI

private struct UITestCredentialStore: APICredentialStoring {
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ apiKey: String?) throws {}
}

enum AppModelContainerLoader {
    static func makeConfiguration(arguments: [String]) -> ModelConfiguration {
        // App Group 只供小工具共享設定，iCloud 同步則由 ICloudSyncService 主動執行。
        ModelConfiguration(
            schema: makeSchema(),
            isStoredInMemoryOnly: arguments.contains("-UITestResetData"),
            groupContainer: .none,
            cloudKitDatabase: .none
        )
    }

    static func load(arguments: [String]) -> Result<ModelContainer, any Error> {
        let configuration = makeConfiguration(arguments: arguments)
        return load {
            if !configuration.isStoredInMemoryOnly {
                let legacyConfiguration = ModelConfiguration(schema: makeSchema())
                try AppModelStoreMigrator(
                    sourceURL: legacyConfiguration.url,
                    destinationURL: configuration.url
                ).migrateIfNeeded()
            }
            return try ModelContainer(
                for: makeSchema(),
                configurations: [configuration]
            )
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
        let configuration = makeConfiguration(arguments: arguments)
        try AppModelStoreResetter(storeURL: configuration.url).resetStoreFiles()
    }

    private static func makeSchema() -> Schema {
        Schema([
            SavedChart.self,
            SavedInsight.self,
            SavedConversation.self,
            CloudDeletion.self
        ])
    }
}

struct AppModelStoreMigrator {
    private static let storeSuffixes = ["", "-journal", "-shm", "-wal"]

    var fileManager = FileManager.default
    var sourceURL: URL
    var destinationURL: URL

    func migrateIfNeeded() throws {
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        guard sourceURL != destinationURL,
              !fileManager.fileExists(atPath: destinationURL.path),
              fileManager.fileExists(atPath: sourceURL.path) else { return }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try cleanupTemporaryFiles(destinationURL: destinationURL)
        for suffix in Self.storeSuffixes.dropFirst() {
            let incompleteSidecar = storeFile(baseURL: destinationURL, suffix: suffix)
            if fileManager.fileExists(atPath: incompleteSidecar.path) {
                try fileManager.removeItem(at: incompleteSidecar)
            }
        }
        do {
            for suffix in Self.storeSuffixes {
                let source = storeFile(baseURL: sourceURL, suffix: suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: temporaryStoreFile(baseURL: destinationURL, suffix: suffix)
                )
            }

            for suffix in Self.storeSuffixes.dropFirst() {
                let temporary = temporaryStoreFile(baseURL: destinationURL, suffix: suffix)
                guard fileManager.fileExists(atPath: temporary.path) else { continue }
                let destination = storeFile(baseURL: destinationURL, suffix: suffix)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: temporary, to: destination)
            }
            try fileManager.moveItem(
                at: temporaryStoreFile(baseURL: destinationURL, suffix: ""),
                to: destinationURL
            )
        } catch {
            try? cleanupTemporaryFiles(destinationURL: destinationURL)
            throw error
        }
    }

    private func cleanupTemporaryFiles(destinationURL: URL) throws {
        for suffix in Self.storeSuffixes {
            let temporary = temporaryStoreFile(baseURL: destinationURL, suffix: suffix)
            if fileManager.fileExists(atPath: temporary.path) {
                try fileManager.removeItem(at: temporary)
            }
        }
    }

    private func storeFile(baseURL: URL, suffix: String) -> URL {
        URL(filePath: baseURL.path + suffix)
    }

    private func temporaryStoreFile(baseURL: URL, suffix: String) -> URL {
        URL(filePath: baseURL.path + suffix + ".migration")
    }
}

struct AppModelStoreResetter {
    var fileManager = FileManager.default
    var storeURL: URL

    func resetStoreFiles() throws {
        let storeFiles = [
            storeURL,
            URL(filePath: storeURL.path + "-journal"),
            URL(filePath: storeURL.path + "-shm"),
            URL(filePath: storeURL.path + "-wal")
        ]
        for file in storeFiles where fileManager.fileExists(atPath: file.path) {
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
    static let retryFailure = "仍無法讀取本機資料。你可以再次重試，或重建本機資料。"
    static let iCloudRestoration = "如果先前已開啟 iCloud 同步，重建成功後會自動同步已存在 iCloud 的命盤、筆記與收藏。對話只儲存在本機，不會復原。"

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

enum PersistenceRecoveryOperation {
    case retry
    case reset

    var statusMessage: String {
        switch self {
        case .retry:
            return "正在重新載入本機資料…"
        case .reset:
            return "正在重建本機資料…"
        }
    }
}

struct PersistenceRecoveryGate {
    private(set) var operation: PersistenceRecoveryOperation?

    var isRunning: Bool { operation != nil }

    mutating func begin(_ newOperation: PersistenceRecoveryOperation) -> Bool {
        guard operation == nil else { return false }
        operation = newOperation
        return true
    }

    mutating func finish() {
        operation = nil
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
        if arguments.contains("-UITestMockAI") {
            let defaults = UserDefaults(suiteName: "MightyZiWei.UITesting.AIUsage")!
            defaults.removePersistentDomain(forName: "MightyZiWei.UITesting.AIUsage")
            _aiUsageStore = State(initialValue: AIUsageStore(defaults: defaults))
        } else {
            _aiUsageStore = State(initialValue: AIUsageStore())
        }
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

    private func reloadModelContainer() -> Bool {
        let reloadResult = AppModelContainerLoader.load(
            arguments: ProcessInfo.processInfo.arguments
        )
        modelContainerResult = reloadResult
        guard case .success = reloadResult else { return false }
        return true
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
    let retry: () -> Bool
    let resetAndReload: () async throws -> Void

    @State private var isShowingResetConfirmation = false
    @State private var recoveryGate = PersistenceRecoveryGate()
    @State private var recoveryErrorTitle = ""
    @State private var recoveryErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label("無法載入本機資料", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("你可以先重試。若仍無法開啟，可重建空白本機資料庫讓 App 立即恢復使用。")
                } actions: {
                    VStack(spacing: 12) {
                        Button("再試一次", action: performRetry)
                            .buttonStyle(.borderedProminent)
                            .disabled(recoveryGate.isRunning)
                            .accessibilityIdentifier("startup.persistenceRetry")

                        Button("重建空白本機資料") {
                            isShowingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(recoveryGate.isRunning)
                        .accessibilityIdentifier("startup.persistenceReset")
                    }
                }

                if let operation = recoveryGate.operation {
                    ProgressView(operation.statusMessage)
                        .accessibilityIdentifier("startup.persistenceRecoveryProgress")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("重建會刪除這台裝置上的本機命盤、筆記、收藏與對話。")
                    Text(PersistenceRecoveryMessage.iCloudRestoration)
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
                Task { await performReset() }
            }
            .disabled(recoveryGate.isRunning)
            Button("取消", role: .cancel) {}
        } message: {
            Text("這只會清除這台裝置的本機資料。\(PersistenceRecoveryMessage.iCloudRestoration)")
        }
        .alert(recoveryErrorTitle, isPresented: recoveryErrorMessageBinding) {
            Button("好", role: .cancel) {
                recoveryErrorMessage = nil
            }
        } message: {
            Text(recoveryErrorMessage ?? "請稍後再試。")
        }
    }

    private var recoveryErrorMessageBinding: Binding<Bool> {
        Binding(
            get: { recoveryErrorMessage != nil },
            set: { isPresented in
                if !isPresented { recoveryErrorMessage = nil }
            }
        )
    }

    private func performRetry() {
        Task {
            guard recoveryGate.begin(.retry) else { return }
            defer { recoveryGate.finish() }
            await Task.yield()
            guard retry() else {
                presentRecoveryError(
                    title: "重試失敗",
                    message: PersistenceRecoveryMessage.retryFailure
                )
                return
            }
        }
    }

    private func performReset() async {
        guard recoveryGate.begin(.reset) else { return }
        defer { recoveryGate.finish() }
        do {
            try await resetAndReload()
        } catch {
            presentRecoveryError(
                title: "重建失敗",
                message: PersistenceRecoveryMessage.resetFailure(for: error)
            )
        }
    }

    private func presentRecoveryError(title: String, message: String) {
        recoveryErrorTitle = title
        recoveryErrorMessage = message
    }
}

private struct PersistenceUnavailableViewPreview: PreviewProvider {
    static var previews: some View {
        PersistenceUnavailableView(
            retry: { false },
            resetAndReload: {}
        )
    }
}
