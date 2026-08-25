import Accessibility
import SwiftData
import SwiftUI

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
                    AccessibilityNotification.Announcement("正在結束語音輸入。")
                        .post()
                case .failed(let message):
                    AccessibilityNotification.Announcement(message)
                        .post()
                case .idle where previousState == .finalizing:
                    AccessibilityNotification.Announcement("語音輸入已結束，文字仍可編輯。")
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
                                ),
                                chartID: chart.savedChartID
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
                presentAPIConfiguration()
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
                .disabled(voiceCoordinator.isInputActive)
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
                        .disabled(voiceCoordinator.isInputActive)
                    Button("檢查 API 設定") {
                        presentAPIConfiguration()
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
                    .disabled(
                        assistantStore.isRequesting
                            || assistantStore.hasReachedRoundLimit
                            || voiceCoordinator.isInputActive
                    )
                    .accessibilityIdentifier("assistant.composer")

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: voiceCoordinator.inputControl.systemImage)
                        .font(.title)
                }
                .disabled(
                    !voiceCoordinator.inputControl.isEnabled
                        || (!voiceCoordinator.isInputActive
                            && (assistantStore.isRequesting
                                || assistantStore.hasReachedRoundLimit))
                )
                .accessibilityLabel(voiceCoordinator.inputControl.label)
                .accessibilityHint(voiceCoordinator.inputControl.hint)
                .accessibilityValue(voiceCoordinator.inputControl.value)
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
            && !voiceCoordinator.isInputActive
    }

    private func toggleVoiceInput() {
        switch voiceCoordinator.inputState {
        case .idle, .failed:
            composerIsFocused = false
            voiceCoordinator.startInput(
                initialDraft: assistantStore.draft,
                limit: ChartAssistantStore.maximumQuestionLength
            ) { draft in
                assistantStore.draft = draft
            }
        case .preparing:
            voiceCoordinator.cancelInput(restoresInitialDraft: true)
        case .recording:
            voiceCoordinator.finishInput()
        case .finalizing:
            break
        }
    }

    private func presentAPIConfiguration() {
        voiceCoordinator.stopAll {
            showsAPIConfiguration = true
        }
    }

    private func sendQuestion() {
        guard !voiceCoordinator.isInputActive else { return }
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
    let chartID: UUID?

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

                HStack {
                    VoicePlaybackControls(
                        contentID: "assistant.\(turn.id.uuidString)",
                        text: turn.answer
                    )
                    Spacer()
                    InsightBookmarkButton(
                        chartID: chartID,
                        locationID: "assistant.\(turn.id.uuidString)",
                        title: "命盤 AI：\(turn.question)",
                        content: turn.answer,
                        evidenceFactIDs: turn.evidenceFactIDs
                    )
                }

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
