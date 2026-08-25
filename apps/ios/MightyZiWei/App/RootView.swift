import AVFAudio
import Combine
import Observation
import SwiftUI

@MainActor
@Observable
final class AppNavigationState {
    enum Tab: Hashable {
        case home
        case saved
        case ai
    }

    var selectedTab: Tab = .home
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
    static let maximumRounds = 10
    static let maximumQuestionLength = 500

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

    private(set) var selectedChart: ChartAssistantChart?
    private(set) var turns: [ChartConversationTurn] = []
    private(set) var requestState: RequestState = .idle
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
        } else if !hasConversation {
            applySelection(chart, clearsConversation: false)
        }
    }

    func requiresConfirmation(toSelect chart: ChartAssistantChart) -> Bool {
        selectedChart?.id != chart.id && hasConversation
    }

    func select(_ chart: ChartAssistantChart) {
        let shouldClear = selectedChart?.id != chart.id
        applySelection(chart, clearsConversation: shouldClear)
    }

    func clearSelection() {
        cancelRequest()
        selectedChart = nil
        turns = []
        draft = ""
        requestState = .idle
    }

    func clearConversation() {
        cancelRequest()
        turns = []
        draft = ""
        requestState = .idle
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
                    evidenceFactIDs: answer.evidenceFactIDs
                ))
                draft = ""
                finishRequest(state: .idle)
            } catch is CancellationError {
                guard requestID == identifier else { return }
                finishRequest(state: .cancelled)
            } catch {
                guard requestID == identifier else { return }
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
            turns = []
            draft = ""
            requestState = .idle
        }
        selectedChart = chart
        if let savedChartID = chart.savedChartID {
            defaults.set(savedChartID.uuidString, forKey: DefaultsKey.lastSelectedChartID)
        }
    }

    private func finishRequest(state: RequestState) {
        requestTask = nil
        requestID = nil
        requestState = state
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
    func answer(
        question: String,
        history: [ChartConversationTurn],
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartConversationAnswer {
        try await Task.sleep(for: .seconds(3))
        return ChartConversationAnswer(
            status: .answered,
            content: "從目前命盤依據來看，你可能傾向先掌握整體方向，再逐步處理細節。",
            evidenceFactIDs: facts.prefix(1).map(\.id)
        )
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VoiceCoordinator.self) private var voiceCoordinator

    @State private var navigation = AppNavigationState()
    @State private var assistantStore: ChartAssistantStore

    init() {
        let isUITestingAI = ProcessInfo.processInfo.arguments.contains("-UITestMockAI")
        let answerer: any ChartConversationAnswering = isUITestingAI
            ? UITestChartConversationAnswerer()
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

            Tab("AI", systemImage: "sparkles", value: .ai) {
                ChartAssistantView()
            }
        }
        .environment(navigation)
        .environment(assistantStore)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                voiceCoordinator.stopAll()
            }
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
}
