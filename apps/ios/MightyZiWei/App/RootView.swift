import AVFAudio
import Combine
import Observation
import SwiftData
import SwiftUI

struct AppURLNavigationPolicy: Sendable {
    func tab(for url: URL) -> AppNavigationState.Tab? {
        guard url.scheme == "mightyziwei" else { return nil }
        switch url.host {
        case "saved": return .saved
        case "ai": return .ai
        default: return .home
        }
    }
}

@MainActor
@Observable
final class AppNavigationState {
    enum Tab: Hashable {
        case home
        case saved
        case ai
    }

    enum SavedDestination: Equatable {
        case chart(UUID)
        case journal(UUID)
    }

    var selectedTab: Tab = .home
    var requestedSavedDestination: SavedDestination?
}

protocol ChartConversationAnswering: Sendable {
    func answer(
        question: String,
        history: [ChartConversationTurn],
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartConversationAnswer
}

extension OpenAIResponsesInterpreter: ChartConversationAnswering {}

@MainActor
@Observable
final class ChartAssistantStore {
    nonisolated static let maximumRounds = 10
    nonisolated static let maximumQuestionLength = 500

    enum RequestState: Equatable {
        case idle
        case loading(question: String)
        case failed(message: String)
        case cancelled
    }

    private enum DefaultsKey {
        static let lastSelectedChartID = "ai.assistant.last-selected-chart-id"
    }

    private let answerer: any ChartConversationAnswering
    private let defaults: UserDefaults
    private var requestTask: Task<Void, Never>?
    private var requestID: UUID?
    private var unsavedSelectionFallback: ChartAssistantChart?

    private(set) var selectedChart: ChartAssistantChart?
    private(set) var turns: [ChartConversationTurn] = []
    private(set) var requestState: RequestState = .idle
    private(set) var lastDiagnosticCode: String?
    private(set) var savedConversationID: UUID?
    private(set) var savedTurnCount = 0
    var draft = ""

    init(
        answerer: any ChartConversationAnswering = OpenAIResponsesInterpreter(),
        defaults: UserDefaults = .standard
    ) {
        self.answerer = answerer
        self.defaults = defaults
    }

    var lastSelectedSavedChartID: UUID? {
        defaults.string(forKey: DefaultsKey.lastSelectedChartID).flatMap(UUID.init(uuidString:))
    }

    var isRequesting: Bool {
        if case .loading = requestState { return true }
        return false
    }

    var hasConversation: Bool {
        !turns.isEmpty || isRequesting
    }

    var hasUnsavedWork: Bool {
        !trimmedDraft.isEmpty || hasConversation
    }

    var unsavedTurnCount: Int {
        max(0, turns.count - savedTurnCount)
    }

    var hasUnsavedChanges: Bool {
        !turns.isEmpty && (savedConversationID == nil || unsavedTurnCount > 0)
    }

    var hasReachedRoundLimit: Bool {
        turns.count >= Self.maximumRounds
    }

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func offer(_ chart: ChartAssistantChart) {
        guard let selectedChart else {
            applySelection(chart, clearsConversation: false)
            return
        }
        if selectedChart.id == chart.id {
            self.selectedChart = chart
        } else if !hasUnsavedWork {
            applySelection(chart, clearsConversation: false)
        }
    }

    func requiresConfirmation(toSelect chart: ChartAssistantChart) -> Bool {
        selectedChart?.id != chart.id && hasUnsavedWork
    }

    func select(_ chart: ChartAssistantChart) {
        let shouldClear = selectedChart?.id != chart.id
        applySelection(chart, clearsConversation: shouldClear)
    }

    func migrateSelection(from previousID: UUID, to chart: ChartAssistantChart) {
        guard let previousChart = selectedChart,
              previousChart.id == previousID else { return }
        let fallback = previousChart.savedChartID == nil && chart.savedChartID != nil
            ? previousChart
            : nil
        applySelection(chart, clearsConversation: false)
        unsavedSelectionFallback = fallback
    }

    func reconcileDeletedSavedChart(_ savedChartID: UUID) {
        guard selectedChart?.savedChartID == savedChartID else { return }
        if let fallback = unsavedSelectionFallback {
            applySelection(fallback, clearsConversation: false)
            unsavedSelectionFallback = nil
        } else {
            clearSelection()
        }
    }

    func reconcileSelection(with chart: ChartAssistantChart) {
        guard let selectedChart, selectedChart.id == chart.id else { return }
        let sourceChanged = selectedChart.detail != chart.detail
            || selectedChart.facts != chart.facts
            || selectedChart.seeds != chart.seeds
        applySelection(chart, clearsConversation: sourceChanged)
    }

    func clearSelection() {
        cancelRequest()
        unsavedSelectionFallback = nil
        selectedChart = nil
        resetConversation()
    }

    func clearConversation() {
        cancelRequest()
        resetConversation()
    }

    func markConversationSaved(id: UUID) {
        guard !turns.isEmpty else { return }
        savedConversationID = id
        savedTurnCount = turns.count
    }

    func reconcileSavedConversationIDs(_ identifiers: Set<UUID>) {
        guard let savedConversationID,
              !identifiers.contains(savedConversationID) else { return }
        self.savedConversationID = nil
        savedTurnCount = 0
    }

    func send(configuration: OpenAIResponsesConfiguration) {
        guard !isRequesting,
              !hasReachedRoundLimit,
              let chart = selectedChart
        else { return }

        let question = trimmedDraft
        guard !question.isEmpty, question.count <= Self.maximumQuestionLength else { return }

        let identifier = UUID()
        requestID = identifier
        requestState = .loading(question: question)
        lastDiagnosticCode = nil
        let history = turns
        requestTask = Task {
            do {
                let answer = try await answerer.answer(
                    question: question,
                    history: history,
                    facts: chart.facts,
                    seeds: chart.seeds,
                    configuration: configuration
                )
                try Task.checkCancellation()
                guard requestID == identifier else { return }
                turns.append(ChartConversationTurn(
                    question: question,
                    answer: answer.content,
                    evidenceFactIDs: answer.evidenceFactIDs,
                    status: answer.status
                ))
                draft = ""
                finishRequest(state: .idle)
            } catch is CancellationError {
                guard requestID == identifier else { return }
                lastDiagnosticCode = "cancelled"
                finishRequest(state: .cancelled)
            } catch {
                guard requestID == identifier else { return }
                lastDiagnosticCode = diagnosticCode(for: error)
                finishRequest(state: .failed(message: safeMessage(for: error)))
            }
        }
    }

    func cancelRequest() {
        guard isRequesting else { return }
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
        requestState = .cancelled
    }

    private func applySelection(
        _ chart: ChartAssistantChart,
        clearsConversation: Bool
    ) {
        if clearsConversation {
            cancelRequest()
            unsavedSelectionFallback = nil
            resetConversation()
        } else if selectedChart?.id != chart.id {
            unsavedSelectionFallback = nil
        }
        selectedChart = chart
        if let savedChartID = chart.savedChartID {
            defaults.set(savedChartID.uuidString, forKey: DefaultsKey.lastSelectedChartID)
        }
    }

    private func resetConversation() {
        turns = []
        draft = ""
        requestState = .idle
        lastDiagnosticCode = nil
        savedConversationID = nil
        savedTurnCount = 0
    }

    private func finishRequest(state: RequestState) {
        requestTask = nil
        requestID = nil
        requestState = state
    }

    private func diagnosticCode(for error: Error) -> String {
        if let interpreterError = error as? OpenAIResponsesInterpreter.InterpreterError {
            return interpreterError.diagnosticCode
        }
        if error is ConversationAnswerValidator.ValidationError {
            return "answer_validation_failed"
        }
        return "unexpected_error"
    }

    private func safeMessage(for error: Error) -> String {
        if let interpreterError = error as? OpenAIResponsesInterpreter.InterpreterError {
            return interpreterError.errorDescription ?? "AI API 暫時無法完成回答。"
        }
        if let validationError = error as? ConversationAnswerValidator.ValidationError {
            switch validationError {
            case .unsafeContent:
                return "AI 回答包含不允許的確定式或專業建議，請再試一次。"
            default:
                return "AI 回答格式或命盤依據不完整，請再試一次。"
            }
        }
        return "AI API 暫時無法完成回答，請稍後再試。"
    }
}

private struct UITestChartConversationAnswerer: ChartConversationAnswering {
    let arguments: [String]

    func answer(
        question: String,
        history: [ChartConversationTurn],
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartConversationAnswer {
        let delay: Duration = arguments.contains("-UITestMockAISlow")
            ? .seconds(30)
            : .seconds(3)
        try await Task.sleep(for: delay)
        if arguments.contains("-UITestMockAIFailure") {
            throw OpenAIResponsesInterpreter.InterpreterError.timedOut
        }
        if arguments.contains("-UITestMockAIUnsupported") {
            return ChartConversationAnswer(
                status: .unsupported,
                content: "目前命盤資料不足以直接回答。",
                evidenceFactIDs: []
            )
        }
        return ChartConversationAnswer(
            status: .answered,
            content: "從目前命盤依據來看，你可能傾向先掌握整體方向，再逐步處理細節。",
            evidenceFactIDs: facts.prefix(1).map(\.id)
        )
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
    @Environment(AppLockStore.self) private var appLockStore
    @Environment(ICloudSyncCoordinator.self) private var iCloudSyncCoordinator
    @Environment(ICloudSynchronizer.self) private var iCloudSynchronizer
    @Environment(VoiceCoordinator.self) private var voiceCoordinator

    @Query private var savedCharts: [SavedChart]
    @Query private var savedInsights: [SavedInsight]
    @Query private var cloudDeletions: [CloudDeletion]
    @AppStorage(ICloudSyncService.enabledKey) private var iCloudSyncEnabled = false
    @State private var navigation = AppNavigationState()
    @State private var assistantStore: ChartAssistantStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITestingAI = arguments.contains("-UITestMockAI")
        let answerer: any ChartConversationAnswering = isUITestingAI
            ? UITestChartConversationAnswerer(arguments: arguments)
            : OpenAIResponsesInterpreter()
        _assistantStore = State(initialValue: ChartAssistantStore(answerer: answerer))
    }

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("首頁", systemImage: "house", value: .home) {
                HomeView()
            }

            Tab("已儲存", systemImage: "rectangle.stack", value: .saved) {
                SavedChartsView()
            }

            Tab("問命盤", systemImage: "sparkles", value: .ai) {
                ChartAssistantView()
            }
        }
        .environment(navigation)
        .environment(assistantStore)
        .preferredColorScheme(
            ProcessInfo.processInfo.arguments.contains("-UITestForceDarkMode")
                ? .dark
                : nil
        )
        .task {
            updatePrivacyShieldWindow()
            handlePendingShortcut()
            await synchronizeICloudIfNeeded()
        }
        .onOpenURL { url in
            handle(url: url)
        }
        .onChange(of: scenePhase) { _, phase in
            appLockStore.handleScenePhase(phase)
            updatePrivacyShieldWindow()
            if phase == .active {
                handlePendingShortcut()
                Task { await synchronizeICloudIfNeeded() }
            }
            if shouldStopVoice(for: phase) {
                voiceCoordinator.stopAll()
            }
        }
        .onChange(of: appLockStore.isLocked) { _, _ in
            updatePrivacyShieldWindow()
        }
        .onChange(of: aiConfigurationStore.isConfigured) { wasConfigured, isConfigured in
            if wasConfigured, !isConfigured {
                assistantStore.cancelRequest()
            }
        }
        .onChange(of: appLockStore.showsPrivacyShield) { _, _ in
            updatePrivacyShieldWindow()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVAudioSession.interruptionNotification
            )
        ) { _ in
            voiceCoordinator.stopAll()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVAudioSession.routeChangeNotification
            )
        ) { notification in
            guard let rawReason = notification.userInfo?[
                AVAudioSessionRouteChangeReasonKey
            ] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                  reason != .categoryChange
            else { return }
            voiceCoordinator.stopAll()
        }
    }

    private func updatePrivacyShieldWindow() {
        let shouldPresent = AppPrivacyShieldPolicy().shouldPresent(
            showsPrivacyShield: appLockStore.showsPrivacyShield,
            isLocked: appLockStore.isLocked
        )
        PrivacyShieldWindowPresenter.shared.setPresented(
            shouldPresent,
            lockStore: appLockStore
        )
    }

    private func synchronizeICloudIfNeeded() async {
        guard iCloudSyncEnabled else { return }
        do {
            _ = try await iCloudSyncCoordinator.synchronize {
                let result = try await iCloudSynchronizer.sync(
                    charts: savedCharts,
                    insights: savedInsights,
                    deletions: cloudDeletions,
                    modelContext: modelContext
                )
                let currentCharts = try modelContext.fetch(FetchDescriptor<SavedChart>())
                PinnedChartShortcut.reconcile(charts: currentCharts)
                return result
            }
        } catch {
            // 保持啟用與安全的可重試狀態，等下次進入前景或由使用者手動重試。
        }
    }

    private func handle(url: URL) {
        guard let tab = AppURLNavigationPolicy().tab(for: url) else { return }
        navigation.selectedTab = tab
    }

    private func handlePendingShortcut() {
        let defaults = UserDefaults(suiteName: ReviewReminderScheduler.sharedDefaultsSuite)
        guard let action = defaults?.string(forKey: "shortcuts.pending-action") else { return }
        defaults?.removeObject(forKey: "shortcuts.pending-action")
        switch action {
        case "open-pinned", "new-note":
            navigation.selectedTab = .saved
            guard let value = defaults?.string(forKey: "shortcuts.pinned-chart-id"),
                  let id = UUID(uuidString: value) else { return }
            navigation.requestedSavedDestination = action == "new-note"
                ? .journal(id)
                : .chart(id)
        case "ai-draft":
            assistantStore.draft = defaults?.string(forKey: "shortcuts.pending-ai-draft") ?? ""
            defaults?.removeObject(forKey: "shortcuts.pending-ai-draft")
            navigation.selectedTab = .ai
        default:
            break
        }
    }
}

func shouldStopVoice(for phase: ScenePhase) -> Bool {
    phase == .background
}
