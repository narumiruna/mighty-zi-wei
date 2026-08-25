import Accessibility
import SwiftData
import SwiftUI

struct InterpretationView: View {
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]

    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
    @Environment(VoiceCoordinator.self) private var voiceCoordinator
    @State private var interpretation: ChartInterpretation
    @State private var isGenerating = false
    @State private var statusMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var showsAPIConfiguration = false

    private let modelInterpreter = OpenAIResponsesInterpreter()

    init(facts: [ChartFact], seeds: [InterpretationSeed]) {
        self.facts = facts
        self.seeds = seeds
        _interpretation = State(
            initialValue: RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                if let overview = interpretation.sections.first(where: { $0.category == .overview }) {
                    InterpretationOverviewView(
                        section: overview,
                        factsByID: factsByID
                    )
                }

                DisclaimerView()

                VStack(alignment: .leading, spacing: 12) {
                    Text("接著想了解什麼？")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(
                        interpretation.sections.filter { $0.category != .overview }
                    ) { section in
                        InterpretationCategoryDisclosure(
                            section: section,
                            factsByID: factsByID
                        )
                    }
                }

                sourceHeader
            }
            .padding()
        }
        .navigationTitle("命盤解讀")
        .accessibilityIdentifier("interpretation.screen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isGenerating {
                Button("停止", role: .cancel) {
                    cancelGeneration()
                }
            }
        }
        .onDisappear {
            generationTask?.cancel()
            voiceCoordinator.stopAll()
        }
        .sheet(isPresented: $showsAPIConfiguration) {
            APIConfigurationSheet()
        }
    }

    private var factsByID: [String: ChartFact] {
        Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("解讀方式")
                .font(.headline)

            HStack {
                Label(
                    interpretation.source.title,
                    systemImage: interpretation.source == .remoteAI ? "cloud" : "text.book.closed"
                )
                .font(.headline)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .accessibilityLabel("正在產生命盤解讀")
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if aiConfigurationStore.isConfigured {
                Button {
                    generateWithAI()
                } label: {
                    Label(
                        interpretation.source == .remoteAI ? "重新整理" : "使用雲端 AI 整理",
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            } else {
                Text("完成 API 設定後，才會在你主動要求時傳送命盤事實與基礎解讀。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    showsAPIConfiguration = true
                } label: {
                    Label("設定 AI API", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("interpretation.configureAI")
            }
        }
        .cardStyle()
    }

    private func generateWithAI() {
        guard !isGenerating else { return }
        let identifier = UUID()
        generationID = identifier
        statusMessage = "雲端模型正在整理，完成驗證前不會顯示內容。"
        isGenerating = true
        generationTask = Task {
            do {
                let configuration = try aiConfigurationStore.configuration()
                let result = try await modelInterpreter.generate(
                    facts: facts,
                    seeds: seeds,
                    configuration: configuration
                )
                try Task.checkCancellation()
                guard generationID == identifier else { return }
                interpretation = result
                statusMessage = "內容已通過命盤依據驗證。"
            } catch is CancellationError {
                guard generationID == identifier else { return }
                statusMessage = "已停止整理，保留目前內容。"
            } catch {
                guard generationID == identifier else { return }
                interpretation = RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
                statusMessage = generationFailureMessage(for: error)
            }
            guard generationID == identifier else { return }
            isGenerating = false
            generationTask = nil
            generationID = nil
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
        isGenerating = false
        statusMessage = "已停止整理，保留目前內容。"
    }

    private func generationFailureMessage(for error: Error) -> String {
        if let interpreterError = error as? OpenAIResponsesInterpreter.InterpreterError {
            switch interpreterError {
            case .unauthorized:
                return "API 授權失敗，請檢查 API key；目前繼續顯示完整的基本解讀。"
            case .rateLimited:
                return "API 已達速率或額度限制；目前繼續顯示完整的基本解讀。"
            case .timedOut:
                return "API 回應逾時；目前繼續顯示完整的基本解讀。"
            default:
                break
            }
        }
        if error is OpenAIResponsesConfiguration.ValidationError {
            return "API 設定不完整；目前繼續顯示完整的基本解讀。"
        }
        if error is KeychainAPICredentialStore.CredentialError {
            return "目前無法讀取 API key；請回到 API 設定確認，基本解讀仍可正常使用。"
        }
        return "雲端整理未完成，繼續顯示完整的基本解讀。"
    }
}

private struct APIConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AIConfigurationView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
    }
}

struct ChartAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIConfigurationStore.self) private var configurationStore
    @Environment(ChartAssistantStore.self) private var assistantStore
    @Environment(VoiceCoordinator.self) private var voiceCoordinator
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var savedCharts: [SavedChart]

    @FocusState private var composerIsFocused: Bool
    @State private var showsAPIConfiguration = false
    @State private var showsClearConfirmation = false
    @State private var pendingChart: ChartAssistantChart?
    @State private var errorMessage: String?

    private let suggestedQuestions = [
        "我的工作性格有什麼特色？",
        "面對人際關係時，我可能要注意什麼？",
        "這張命盤有哪些值得自我觀察的傾向？"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let chart = assistantStore.selectedChart {
                    conversationContent(chart: chart)
                } else if savedCharts.isEmpty {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "還沒有可以詢問的命盤",
                        message: "先建立一張命盤，AI 才能根據 App 已驗證的命盤資料回答問題。"
                    )
                    .overlay(alignment: .bottom) {
                        NavigationLink {
                            BirthInputView()
                        } label: {
                            Label("排一張命盤", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 80)
                        .accessibilityIdentifier("assistant.createChart")
                    }
                } else {
                    ProgressView("正在準備最近的命盤…")
                }
            }
            .navigationTitle("命盤 AI")
            .toolbar {
                if !assistantStore.turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("清除本次對話", systemImage: "trash", role: .destructive) {
                                showsClearConfirmation = true
                            }
                        } label: {
                            Label("對話操作", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if assistantStore.selectedChart != nil, configurationStore.isConfigured {
                    composer
                }
            }
            .task {
                loadDefaultChartIfNeeded()
            }
            .onChange(of: voiceCoordinator.inputState) { previousState, state in
                switch state {
                case .recording:
                    AccessibilityNotification.Announcement("已開始語音輸入。")
                        .post()
                case .finalizing:
                    AccessibilityNotification.Announcement("正在完成語音辨識。")
                        .post()
                case .failed(let message):
                    AccessibilityNotification.Announcement(message)
                        .post()
                case .idle where previousState == .finalizing:
                    AccessibilityNotification.Announcement("語音輸入已完成，文字仍可編輯。")
                        .post()
                case .idle, .preparing:
                    break
                }
            }
            .onChange(of: savedCharts.map(\.id)) { _, identifiers in
                guard let selectedID = assistantStore.selectedChart?.savedChartID,
                      !identifiers.contains(selectedID)
                else { return }
                voiceCoordinator.stopAll()
                assistantStore.clearSelection()
                loadDefaultChartIfNeeded()
            }
            .onDisappear {
                assistantStore.cancelRequest()
                voiceCoordinator.stopAll()
            }
            .sheet(isPresented: $showsAPIConfiguration) {
                APIConfigurationSheet()
            }
            .confirmationDialog(
                "切換命盤並清除本次對話？",
                isPresented: switchConfirmationIsPresented,
                titleVisibility: .visible
            ) {
                Button("切換並清除本次對話", role: .destructive) {
                    guard let pendingChart else { return }
                    voiceCoordinator.stopAll()
                    assistantStore.select(pendingChart)
                    self.pendingChart = nil
                }
                Button("取消", role: .cancel) {
                    pendingChart = nil
                }
            } message: {
                Text("不同命盤的對話依據不能混用。已完成的本次對話不會永久保存。")
            }
            .confirmationDialog(
                "清除本次對話？",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除對話", role: .destructive) {
                    voiceCoordinator.stopAll()
                    assistantStore.clearConversation()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只會清除目前對話，不會刪除命盤或 API 設定。")
            }
            .alert("操作未完成", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    private var switchConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingChart != nil },
            set: { if !$0 { pendingChart = nil } }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func conversationContent(chart: ChartAssistantChart) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                    chartSelector(chart: chart)

                    if !configurationStore.isConfigured {
                        apiSetupCard
                    } else {
                        privacyNotice

                        if assistantStore.turns.isEmpty, !assistantStore.isRequesting {
                            suggestions
                        }

                        ForEach(assistantStore.turns) { turn in
                            ConversationTurnView(
                                turn: turn,
                                factsByID: Dictionary(
                                    uniqueKeysWithValues: chart.facts.map { ($0.id, $0) }
                                )
                            )
                            .id(turn.id)
                        }

                        requestStatus
                            .id("assistant.requestStatus")
                    }
                }
                .padding()
            }
            .onChange(of: assistantStore.turns.count) { oldCount, newCount in
                withAnimation {
                    proxy.scrollTo("assistant.requestStatus", anchor: .bottom)
                }
                if newCount > oldCount {
                    AccessibilityNotification.Announcement("命盤助理已完成回答。")
                        .post()
                }
            }
            .onChange(of: assistantStore.requestState) { _, state in
                withAnimation {
                    proxy.scrollTo("assistant.requestStatus", anchor: .bottom)
                }
                switch state {
                case .failed:
                    AccessibilityNotification.Announcement("回答未完成，問題仍保留。")
                        .post()
                case .cancelled:
                    AccessibilityNotification.Announcement("已停止回答，問題仍保留。")
                        .post()
                case .idle, .loading:
                    break
                }
            }
        }
    }

    private func chartSelector(chart: ChartAssistantChart) -> some View {
        Menu {
            ForEach(savedCharts) { savedChart in
                Button {
                    prepareSelection(savedChart)
                } label: {
                    Label(
                        savedChart.name,
                        systemImage: savedChart.id == chart.savedChartID
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.text.rectangle")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("目前命盤")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(chart.name)
                        .font(.headline)
                    Text(chart.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !savedCharts.isEmpty {
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .disabled(savedCharts.isEmpty)
        .accessibilityIdentifier("assistant.chartSelector")
        .accessibilityHint(savedCharts.isEmpty ? "目前沒有其他已儲存命盤" : "點兩下切換命盤")
    }

    private var apiSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("設定 AI API 後即可詢問這張命盤", systemImage: "key")
                .font(.headline)
            Text("基本排盤與基本解讀不需要 API；只有主動提問時才會傳送命盤依據。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showsAPIConfiguration = true
            } label: {
                Text("設定 AI API")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("assistant.configureAPI")
        }
        .cardStyle()
    }

    private var privacyNotice: some View {
        Label {
            Text("問題、本次對話與已驗證命盤依據會傳送到你設定的第三方 API。請勿輸入敏感個資，每次提問都可能產生 token 費用。")
                .font(.footnote)
        } icon: {
            Image(systemName: "hand.raised")
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你想了解什麼？")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("選一個問題開始，或在下方輸入自己的疑問。")
                .foregroundStyle(.secondary)

            ForEach(Array(suggestedQuestions.enumerated()), id: \.offset) { index, question in
                Button {
                    assistantStore.draft = question
                    composerIsFocused = true
                } label: {
                    HStack {
                        Text(question)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.down.to.line")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("將問題填入輸入框，不會立即送出")
                .accessibilityIdentifier("assistant.suggestion.\(index)")
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var requestStatus: some View {
        switch assistantStore.requestState {
        case .idle:
            if assistantStore.hasReachedRoundLimit {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本次對話已達 10 輪", systemImage: "checkmark.circle")
                        .font(.headline)
                    Text("開始新對話後才能繼續提問，舊對話不會永久保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("開始新對話") {
                        showsClearConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .cardStyle()
            }
        case .loading(let question):
            VStack(alignment: .leading, spacing: 12) {
                Text("你的問題")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(question)
                Divider()
                HStack {
                    ProgressView()
                    Text("正在查看命盤依據…")
                    Spacer()
                    Button("停止", role: .cancel) {
                        assistantStore.cancelRequest()
                    }
                }
            }
            .cardStyle()
            .accessibilityIdentifier("assistant.loading")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("回答未完成", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                HStack {
                    Button("再試一次") { sendQuestion() }
                        .buttonStyle(.borderedProminent)
                    Button("檢查 API 設定") {
                        showsAPIConfiguration = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .cardStyle()
            .accessibilityIdentifier("assistant.error")
        case .cancelled:
            Label("已停止回答，問題仍保留在輸入框中。", systemImage: "stop.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .cardStyle()
                .accessibilityIdentifier("assistant.cancelled")
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "輸入想問的問題…",
                    text: Binding(
                        get: { assistantStore.draft },
                        set: { assistantStore.draft = $0 }
                    ),
                    axis: .vertical
                )
                    .lineLimit(1...5)
                    .focused($composerIsFocused)
                    .disabled(assistantStore.isRequesting || assistantStore.hasReachedRoundLimit)
                    .accessibilityIdentifier("assistant.composer")

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(
                        systemName: voiceCoordinator.isInputActive
                            ? "stop.circle.fill"
                            : "mic.circle.fill"
                    )
                    .font(.title)
                }
                .disabled(
                    !voiceCoordinator.isInputActive
                        && (assistantStore.isRequesting || assistantStore.hasReachedRoundLimit)
                )
                .accessibilityLabel(
                    voiceCoordinator.isInputActive ? "停止語音輸入" : "開始語音輸入"
                )
                .accessibilityHint(
                    voiceCoordinator.isInputActive
                        ? "停止聆聽並保留已辨識文字"
                        : "將說出的問題填入草稿，不會自動送出"
                )
                .accessibilityValue(voiceCoordinator.isInputActive ? "正在收音" : "未收音")
                .accessibilityIdentifier("voice.input.toggle")

                Button {
                    sendQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(!canSend)
                .accessibilityLabel("送出問題")
                .accessibilityIdentifier("assistant.send")
            }

            if let statusMessage = voiceCoordinator.inputStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(inputStatusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("voice.input.status")
            }

            if assistantStore.draft.count > 450 {
                Text("\(assistantStore.draft.count) / \(ChartAssistantStore.maximumQuestionLength)")
                    .font(.caption2)
                    .foregroundStyle(
                        assistantStore.draft.count > ChartAssistantStore.maximumQuestionLength
                            ? .red
                            : .secondary
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("已輸入 \(assistantStore.draft.count) 字，上限 \(ChartAssistantStore.maximumQuestionLength) 字")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var inputStatusColor: Color {
        if case .failed = voiceCoordinator.inputState {
            return .red
        }
        return .secondary
    }

    private var canSend: Bool {
        !assistantStore.trimmedDraft.isEmpty
            && assistantStore.draft.count <= ChartAssistantStore.maximumQuestionLength
            && !assistantStore.isRequesting
            && !assistantStore.hasReachedRoundLimit
    }

    private func toggleVoiceInput() {
        if voiceCoordinator.isInputActive {
            voiceCoordinator.finishInput()
        } else {
            composerIsFocused = false
            voiceCoordinator.startInput(
                initialDraft: assistantStore.draft,
                limit: ChartAssistantStore.maximumQuestionLength
            ) { draft in
                assistantStore.draft = draft
            }
        }
    }

    private func sendQuestion() {
        voiceCoordinator.cancelInput(restoresInitialDraft: false)
        do {
            assistantStore.send(configuration: try configurationStore.configuration())
            composerIsFocused = false
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "目前無法讀取 API 設定。"
        } catch {
            errorMessage = "目前無法讀取 API 設定。"
        }
    }

    private func loadDefaultChartIfNeeded() {
        guard assistantStore.selectedChart == nil, !savedCharts.isEmpty else { return }
        let preferred = assistantStore.lastSelectedSavedChartID.flatMap { identifier in
            savedCharts.first { $0.id == identifier }
        } ?? savedCharts.first
        if let preferred {
            select(savedChart: preferred)
        }
    }

    private func prepareSelection(_ savedChart: SavedChart) {
        do {
            let chart = try makeAssistantChart(savedChart: savedChart)
            if assistantStore.requiresConfirmation(toSelect: chart) {
                pendingChart = chart
            } else {
                voiceCoordinator.stopAll()
                assistantStore.select(chart)
            }
        } catch {
            errorMessage = "目前無法準備這張命盤，請回到已儲存命盤重新建立。"
        }
    }

    private func select(savedChart: SavedChart) {
        do {
            voiceCoordinator.stopAll()
            assistantStore.select(try makeAssistantChart(savedChart: savedChart))
        } catch {
            errorMessage = "目前無法準備最近的命盤，請回到已儲存命盤重新建立。"
        }
    }

    private func makeAssistantChart(savedChart: SavedChart) throws -> ChartAssistantChart {
        let chart = try savedChart.resolvedChart()
        try modelContext.save()
        return ChartAssistantChart.make(
            id: savedChart.id,
            savedChartID: savedChart.id,
            name: savedChart.name,
            chart: chart
        )
    }
}

private struct ConversationTurnView: View {
    let turn: ChartConversationTurn
    let factsByID: [String: ChartFact]

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("你的問題")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(turn.question)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("你的問題：\(turn.question)")

            VStack(alignment: .leading, spacing: 12) {
                Label("命盤助理", systemImage: "sparkles")
                    .font(.headline)
                Text(turn.answer)
                    .lineSpacing(5)
                    .textSelection(.enabled)

                VoicePlaybackControls(
                    contentID: "assistant.\(turn.id.uuidString)",
                    text: turn.answer
                )

                if !turn.evidenceFactIDs.isEmpty {
                    Divider()
                    DisclosureGroup("回答依據") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(turn.evidenceFactIDs, id: \.self) { identifier in
                                if let fact = factsByID[identifier] {
                                    Label(fact.displayText, systemImage: "checkmark.seal")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .cardStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("assistant.answer")
        }
    }
}

extension ChartAssistantChart {
    static func make(
        id: UUID,
        savedChartID: UUID?,
        name: String,
        chart: ZiWeiChart
    ) -> ChartAssistantChart {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "未命名命盤" : trimmedName
        let date = chart.birthProfile.localDate
        let time = chart.birthProfile.localTime
        let detail = String(
            format: "%04d/%02d/%02d　%02d:%02d",
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute
        )
        let facts = ChartFactBuilder().makeFacts(from: chart)
        return ChartAssistantChart(
            id: id,
            savedChartID: savedChartID,
            name: displayName,
            detail: detail,
            facts: facts,
            seeds: InterpretationSeedBuilder().makeSeeds(from: facts)
        )
    }
}

private struct InterpretationOverviewView: View {
    let section: InterpretationSection
    let factsByID: [String: ChartFact]

    private var leadingSummary: String {
        section.content
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? section.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(leadingSummary)
                .font(.title3.weight(.semibold))
                .lineSpacing(5)
                .textSelection(.enabled)

            if leadingSummary != section.content {
                DisclosureGroup("閱讀完整總覽") {
                    Text(section.content)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("interpretation.overview.details")
            }

            VoicePlaybackControls(
                contentID: "interpretation.\(section.id)",
                text: "\(section.title)。\(section.content)"
            )

            InterpretationEvidenceDisclosure(
                evidenceFactIDs: section.evidenceFactIDs,
                factsByID: factsByID
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("interpretation.overview")
    }
}

private struct InterpretationCategoryDisclosure: View {
    let section: InterpretationSection
    let factsByID: [String: ChartFact]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Text(section.content)
                    .lineSpacing(5)
                    .textSelection(.enabled)

                VoicePlaybackControls(
                    contentID: "interpretation.\(section.id)",
                    text: "\(section.title)。\(section.content)"
                )

                InterpretationEvidenceDisclosure(
                    evidenceFactIDs: section.evidenceFactIDs,
                    factsByID: factsByID
                )
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.headline)
                Text(section.category.learningPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .accessibilityIdentifier("interpretation.category.\(section.category.rawValue)")
    }
}

private struct InterpretationEvidenceDisclosure: View {
    let evidenceFactIDs: [String]
    let factsByID: [String: ChartFact]

    var body: some View {
        DisclosureGroup("解讀依據") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(evidenceFactIDs, id: \.self) { identifier in
                    if let fact = factsByID[identifier] {
                        Label(fact.displayText, systemImage: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("已驗證依據：\(fact.displayText)")
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.medium))
    }
}

private extension InterpretationCategory {
    var learningPrompt: String {
        switch self {
        case .overview: "先認識這張命盤的整體方向"
        case .personality: "了解你習慣如何感受與做決定"
        case .career: "看看你可能偏好的工作方式"
        case .wealth: "認識你安排資源時的傾向"
        case .relationships: "看看你重視怎樣的互動"
        }
    }
}
