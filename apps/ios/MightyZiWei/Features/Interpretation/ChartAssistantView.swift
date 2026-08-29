import Accessibility
import SwiftData
import SwiftUI
import UIKit

struct ChartAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIConfigurationStore.self) private var configurationStore
    @Environment(AIUsageStore.self) private var usageStore
    @Environment(ChartAssistantStore.self) private var assistantStore
    @Environment(VoiceCoordinator.self) private var voiceCoordinator
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var savedCharts: [SavedChart]
    @Query private var savedConversations: [SavedConversation]

    @FocusState private var composerIsFocused: Bool
    @State private var showsAPIConfiguration = false
    @State private var pendingTransition: PendingTransition?
    @State private var errorMessage: String?
    @State private var saveMessage: String?

    private let suggestedQuestions = [
        "我的個性有哪些值得留意的地方？",
        "我的工作方式可能有什麼特色？",
        "面對人際關係時，我可以觀察什麼？"
    ]

    private var savedChartSnapshots: [SavedChartAssistantSnapshot] {
        savedCharts.map(SavedChartAssistantSnapshot.init)
    }

    private var savedConversationIDs: Set<UUID> {
        Set(savedConversations.map(\.id))
    }

    var body: some View {
        NavigationStack {
            screenContent
                .navigationTitle("命盤助理")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) {
                    if assistantStore.selectedChart != nil, configurationStore.isConfigured {
                        composer
                    }
                }
                .task { loadDefaultChartIfNeeded() }
                .onChange(of: voiceCoordinator.inputState) { previousState, state in
                    announceVoiceInputChange(from: previousState, to: state)
                }
                .onChange(of: savedChartSnapshots) { previous, current in
                    reconcileSavedCharts(previous: previous, current: current)
                }
                .onChange(of: savedConversationIDs) { _, identifiers in
                    assistantStore.reconcileSavedConversationIDs(identifiers)
                }
                .onChange(of: assistantStore.turns.count) { _, _ in
                    saveMessage = nil
                }
                .onDisappear {
                    voiceCoordinator.stopAll()
                }
                .sheet(isPresented: $showsAPIConfiguration) {
                    APIConfigurationSheet()
                }
                .alert(
                    transitionTitle,
                    isPresented: transitionIsPresented
                ) {
                    transitionActions
                } message: {
                    Text(transitionMessage)
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SavedConversationsView()
            } label: {
                Label("已保存對話", systemImage: "tray.full")
            }
            .accessibilityIdentifier("assistant.savedConversations")
        }

        if assistantStore.hasUnsavedWork {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("清除目前對話", systemImage: "trash", role: .destructive) {
                        requestTransition(.clear)
                    }
                } label: {
                    Label("其他對話操作", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        if let chart = assistantStore.selectedChart {
            conversationContent(chart: chart)
        } else if savedCharts.isEmpty {
            VStack(spacing: 16) {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "還沒有可以詢問的命盤",
                    message: "先建立一張命盤，命盤助理才能根據 App 已驗證的資料回答問題。"
                )
                NavigationLink {
                    BirthInputView()
                } label: {
                    Label("排一張命盤", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assistant.createChart")
            }
            .padding()
        } else if let errorMessage {
            ScrollView {
                operationErrorStatus(message: errorMessage)
                    .padding()
            }
        } else {
            ProgressView("正在準備最近的命盤…")
                .accessibilityIdentifier("assistant.preparingChart")
        }
    }

    private func conversationContent(chart: ChartAssistantChart) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                    chartSelector(chart: chart)

                    if let errorMessage {
                        operationErrorStatus(message: errorMessage)
                            .id("assistant.operationError")
                    }

                    if !configurationStore.isConfigured {
                        apiSetupCard
                    } else {
                        capabilityNotice

                        if assistantStore.turns.isEmpty, !assistantStore.isRequesting {
                            suggestions
                        }

                        let factsByID = Dictionary(
                            uniqueKeysWithValues: chart.facts.map { ($0.id, $0) }
                        )
                        ForEach(assistantStore.turns) { turn in
                            ConversationTurnView(
                                turn: turn,
                                factsByID: factsByID,
                                chartID: chart.savedChartID
                            )
                            .id(turn.id)
                        }

                        if let lastTurn = assistantStore.turns.last,
                           !assistantStore.hasReachedRoundLimit {
                            AssistantFollowUpQuestionsView(
                                status: lastTurn.status,
                                isEnabled: !assistantStore.isRequesting,
                                select: fillDraft
                            )
                        }

                        if !assistantStore.turns.isEmpty {
                            saveStatus
                        }

                        requestStatus
                            .id("assistant.requestStatus")

                        Color.clear
                            .frame(height: 1)
                            .accessibilityHidden(true)
                            .id("assistant.contentEnd")
                    }
                }
                .padding()
            }
            .onChange(of: assistantStore.turns.count) { oldCount, newCount in
                if newCount > oldCount, let lastTurn = assistantStore.turns.last {
                    withAnimation {
                        proxy.scrollTo(lastTurn.id, anchor: .top)
                    }
                    let message = lastTurn.status == .unsupported
                        ? "這個問題目前無法用命盤回答，已提供其他提問方向。"
                        : "命盤助理已完成回答。"
                    AccessibilityNotification.Announcement(message).post()
                }
            }
            .onChange(of: assistantStore.requestState) { _, state in
                if state != .idle {
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo("assistant.contentEnd", anchor: .bottom)
                    }
                }
                announceRequestState(state)
            }
            .onChange(of: errorMessage) { _, message in
                guard let message else { return }
                withAnimation {
                    proxy.scrollTo("assistant.operationError", anchor: .center)
                }
                AccessibilityNotification.Announcement(
                    "操作未完成。\(message)目前內容仍保留。"
                ).post()
            }
        }
    }

    private func chartSelector(chart: ChartAssistantChart) -> some View {
        Menu {
            if savedCharts.isEmpty {
                Button("目前沒有其他已儲存命盤") {}
                    .disabled(true)
            }
            ForEach(savedCharts) { savedChart in
                Button {
                    prepareSelection(savedChart)
                } label: {
                    Label(
                        SavedChartPickerLabelBuilder.make(savedChart: savedChart),
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
                    Text(chart.name)
                        .font(.headline)
                    Text(chart.detail)
                        .font(.caption)
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
        .accessibilityIdentifier("assistant.chartSelector")
        .accessibilityLabel("目前命盤：\(chart.name)，\(chart.detail)")
        .accessibilityHint(savedCharts.isEmpty ? "目前沒有其他已儲存命盤" : "點兩下切換命盤")
    }

    private func operationErrorStatus(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("操作未完成", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.footnote)
            Button("關閉") {
                errorMessage = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("assistant.operationError")
    }

    private var apiSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("設定 AI API 後即可詢問這張命盤", systemImage: "key")
                .font(.headline)
            Text("排盤與完整基本解讀不需要 API，只有你主動送出問題時才會傳送命盤依據。")
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

    private var capabilityNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("根據命盤理解生活傾向", systemImage: "checkmark.bubble")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("assistant.capabilities")
            Text("可詢問個性、工作、財務、感情與人際。")
            Text("送出問題會立即傳送到你設定的第三方 API，第三方服務可能收費。")
                .font(.footnote)

            DisclosureGroup("查看回答限制與傳送內容") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("不提供健康診斷、投資或法律建議，也不預測確定事件。", systemImage: "hand.raised")
                    Text("傳送內容包括你的問題、本次對話與回答所需的命盤依據。")
                }
                .font(.footnote)
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
            .accessibilityIdentifier("assistant.capabilities.details")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你想先了解什麼？")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("選擇後只會填入草稿，不會自動送出或產生費用。")

            ForEach(Array(suggestedQuestions.enumerated()), id: \.offset) { index, question in
                Button {
                    fillDraft(question)
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

    private var saveStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(saveStatusTitle, systemImage: saveStatusSystemImage)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("保存狀態：\(saveStatusTitle)")
                .accessibilityIdentifier("assistant.saveStatus")
            Text(saveStatusDetail)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.primary)
            Button {
                _ = saveConversation()
            } label: {
                Label(saveButtonTitle, systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(
                assistantStore.isRequesting
                    || assistantStore.selectedChart?.savedChartID == nil
            )
            .accessibilityIdentifier("assistant.saveConversation")

            if assistantStore.selectedChart?.savedChartID == nil {
                DisabledReasonView("先儲存命盤才能保存對話。")
            }

            if let saveMessage {
                Label(saveMessage, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .accessibilityIdentifier("assistant.saveConfirmation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var saveStatusTitle: String {
        if assistantStore.savedConversationID == nil {
            return "本次對話尚未保存"
        }
        if assistantStore.unsavedTurnCount == 0 {
            return "已保存到第 \(assistantStore.savedTurnCount) 輪"
        }
        return "另有 \(assistantStore.unsavedTurnCount) 輪尚未保存"
    }

    private var saveStatusDetail: String {
        if assistantStore.hasUnsavedChanges {
            return "未保存內容在關閉 App 或清除對話後無法復原。"
        }
        return "這份本機副本不會自動同步或納入加密備份。"
    }

    private var saveStatusSystemImage: String {
        assistantStore.hasUnsavedChanges ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var saveButtonTitle: String {
        assistantStore.savedConversationID == nil ? "保存對話" : "更新已保存對話"
    }

    @ViewBuilder
    private var requestStatus: some View {
        switch assistantStore.requestState {
        case .idle:
            if assistantStore.hasReachedRoundLimit {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本次對話已達 10 輪", systemImage: "checkmark.circle")
                        .font(.headline)
                    Text("請先保存需要保留的內容，再開始新對話。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("開始新對話") {
                        requestTransition(.clear)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .cardStyle()
                .accessibilityIdentifier("assistant.roundLimit")
            }
        case .loading(let question):
            VStack(alignment: .leading, spacing: 12) {
                Text("正在回答的問題")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("assistant.loading")
                Text(question)
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        ProgressView()
                        Text("正在整理命盤依據，完成驗證前不會加入對話。")
                        Spacer()
                        Button("停止", role: .cancel) {
                            assistantStore.cancelRequest()
                        }
                        .accessibilityIdentifier("assistant.stop")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ProgressView()
                            Text("正在整理命盤依據…")
                        }
                        Text("完成驗證前不會加入對話。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("停止等待", role: .cancel) {
                            assistantStore.cancelRequest()
                        }
                        .accessibilityIdentifier("assistant.stop")
                    }
                }
            }
            .cardStyle()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("回答未完成", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.footnote)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        retryButton
                        if shouldOfferSettingsRecovery { settingsRecoveryButton }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        retryButton
                        if shouldOfferSettingsRecovery { settingsRecoveryButton }
                    }
                }
            }
            .cardStyle()
            .accessibilityIdentifier("assistant.error")
        case .cancelled:
            VStack(alignment: .leading, spacing: 8) {
                Label("已停止等待，問題仍保留", systemImage: "stop.circle")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("第三方服務可能已開始處理這次請求，仍可能產生費用。你可以修改問題或重新送出。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
            .accessibilityIdentifier("assistant.cancelled")
        }
    }

    private var retryButton: some View {
        Button("重新送出") { sendQuestion() }
            .buttonStyle(.borderedProminent)
            .disabled(voiceCoordinator.isInputActive)
    }

    private var settingsRecoveryButton: some View {
        Button("檢查 API 設定") { presentAPIConfiguration() }
            .buttonStyle(.bordered)
    }

    private var shouldOfferSettingsRecovery: Bool {
        ["authorization_failed", "configuration_invalid", "credential_unavailable"]
            .contains(assistantStore.lastDiagnosticCode)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .leading) {
                    if assistantStore.draft.isEmpty {
                        Text("輸入想問的問題…")
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
                    TextField(
                        "",
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
                    .accessibilityLabel("命盤問題")
                    .accessibilityValue(
                        assistantStore.draft.isEmpty ? "尚未輸入" : assistantStore.draft
                    )
                    .accessibilityIdentifier("assistant.composer")
                }

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: voiceCoordinator.inputControl.systemImage)
                        .font(.title)
                        .frame(minWidth: 44, minHeight: 44)
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
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!canSend)
                .accessibilityLabel("送出問題")
                .accessibilityHint(sendAccessibilityHint)
                .accessibilityIdentifier("assistant.send")
            }

            if let statusMessage = voiceCoordinator.inputStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(inputStatusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("voice.input.status")
            } else if let composerStatusMessage {
                Text(composerStatusMessage)
                    .font(.caption)
                    .foregroundStyle(composerStatusIsError ? .red : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("assistant.composerStatus")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
    }

    private var composerBlockReason: AssistantComposerBlockReason? {
        AssistantComposerPolicy().blockReason(
            draft: assistantStore.draft,
            isRequesting: assistantStore.isRequesting,
            hasReachedRoundLimit: assistantStore.hasReachedRoundLimit,
            isVoiceActive: voiceCoordinator.isInputActive
        )
    }

    private var composerStatusMessage: String? {
        if let composerBlockReason {
            return composerBlockReason.message
        }
        if assistantStore.draft.count > 450 {
            return "已輸入 \(assistantStore.draft.count) / \(ChartAssistantStore.maximumQuestionLength) 字"
        }
        return nil
    }

    private var composerStatusIsError: Bool {
        composerBlockReason == .tooLong
    }

    private var sendAccessibilityHint: String {
        composerBlockReason?.message ?? "立即傳送到你設定的第三方 API"
    }

    private var inputStatusColor: Color {
        if case .failed = voiceCoordinator.inputState {
            return .red
        }
        return .secondary
    }

    private var canSend: Bool {
        composerBlockReason == nil
    }

    private func fillDraft(_ question: String) {
        assistantStore.draft = question
        composerIsFocused = true
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
        guard !voiceCoordinator.isInputActive, canSend else { return }
        errorMessage = nil
        do {
            let configuration = try configurationStore.configuration()
            try usageStore.reserve(.conversation)
            assistantStore.send(configuration: configuration)
            composerIsFocused = false
        } catch let error as LocalizedError {
            usageStore.record(error: error, kind: .conversation)
            errorMessage = error.errorDescription ?? "目前無法讀取 API 設定。"
        } catch {
            usageStore.record(error: error, kind: .conversation)
            errorMessage = "目前無法讀取 API 設定。"
        }
    }

    @discardableResult
    private func saveConversation() -> Bool {
        guard let chart = assistantStore.selectedChart,
              !assistantStore.turns.isEmpty else { return false }
        errorMessage = nil
        do {
            let conversation = try AssistantConversationPersistence().save(
                chart: chart,
                turns: assistantStore.turns,
                modelIdentifier: configurationStore.model,
                title: assistantStore.turns.first?.question ?? "命盤助理對話",
                existingID: assistantStore.savedConversationID,
                modelContext: modelContext
            )
            assistantStore.markConversationSaved(id: conversation.id)
            saveMessage = "已保存目前 \(assistantStore.turns.count) 輪對話。"
            AccessibilityNotification.Announcement("對話已保存到本機。")
                .post()
            return true
        } catch {
            errorMessage = "無法保存本機對話，目前內容仍保留。請再試一次。"
            return false
        }
    }

    private func requestTransition(_ transition: PendingTransition) {
        composerIsFocused = false
        voiceCoordinator.stopAll()
        let risk = transitionRisk
        if risk == .none {
            apply(transition)
        } else {
            pendingTransition = transition
        }
    }

    private var transitionRisk: AssistantTransitionRisk {
        AssistantTransitionPolicy().risk(
            hasDraft: !assistantStore.trimmedDraft.isEmpty,
            isRequesting: assistantStore.isRequesting,
            turnCount: assistantStore.turns.count,
            hasUnsavedChanges: assistantStore.hasUnsavedChanges
        )
    }

    private var transitionTitle: String {
        switch pendingTransition {
        case .switchChart:
            "切換命盤並開始新對話？"
        case .clear:
            "開始新對話？"
        case nil:
            "確認操作？"
        }
    }

    private var transitionMessage: String {
        switch transitionRisk {
        case .draft:
            "目前問題草稿尚未送出，繼續後會捨棄這份草稿。"
        case .unsavedConversation:
            if assistantStore.isRequesting {
                "正在回答的問題尚未完成，無法保存。你可以只保存既有回答，或不保存並繼續。"
            } else {
                "尚未保存的問題與回答將無法復原。不同命盤的對話依據不能混用。"
            }
        case .savedConversation:
            "目前對話已保存，繼續後會清除畫面上的本次對話。"
        case .none:
            "確認後才會套用變更。"
        }
    }

    @ViewBuilder
    private var transitionActions: some View {
        if transitionRisk == .unsavedConversation, !assistantStore.turns.isEmpty {
            Button(saveThenTransitionTitle) {
                saveAndApplyPendingTransition()
            }
        }
        Button(destructiveTransitionTitle, role: .destructive) {
            applyPendingTransition()
        }
        Button("取消", role: .cancel) {
            pendingTransition = nil
        }
    }

    private var saveThenTransitionTitle: String {
        let prefix = assistantStore.isRequesting ? "保存既有回答後" : "保存後"
        return switch pendingTransition {
        case .switchChart: "\(prefix)切換"
        case .clear: "\(prefix)開始新對話"
        case nil: assistantStore.isRequesting ? "保存既有回答" : "先保存"
        }
    }

    private var destructiveTransitionTitle: String {
        switch (pendingTransition, transitionRisk) {
        case (.switchChart, .savedConversation): "切換命盤"
        case (.switchChart, _): "不保存，直接切換"
        case (.clear, .savedConversation): "開始新對話"
        case (.clear, _): "不保存，開始新對話"
        case (nil, _): "繼續"
        }
    }

    private var transitionIsPresented: Binding<Bool> {
        Binding(
            get: { pendingTransition != nil },
            set: { if !$0 { pendingTransition = nil } }
        )
    }

    private func saveAndApplyPendingTransition() {
        guard let transition = pendingTransition else { return }
        do {
            try AssistantAtomicTransition().perform(
                save: {
                    guard saveConversation() else {
                        throw TransitionError.saveFailed
                    }
                },
                apply: {
                    apply(transition)
                }
            )
        } catch {
            pendingTransition = nil
        }
    }

    private func applyPendingTransition() {
        guard let transition = pendingTransition else { return }
        apply(transition)
    }

    private func apply(_ transition: PendingTransition) {
        pendingTransition = nil
        saveMessage = nil
        voiceCoordinator.stopAll()
        switch transition {
        case .clear:
            assistantStore.clearConversation()
        case .switchChart(let chart):
            assistantStore.select(chart)
        }
    }

    private func announceVoiceInputChange(
        from previousState: VoiceCoordinator.InputState,
        to state: VoiceCoordinator.InputState
    ) {
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

    private func announceRequestState(_ state: ChartAssistantStore.RequestState) {
        switch state {
        case .failed:
            if let code = assistantStore.lastDiagnosticCode {
                usageStore.record(code: code, kind: .conversation)
            }
            AccessibilityNotification.Announcement("回答未完成，問題仍保留。")
                .post()
        case .cancelled:
            AccessibilityNotification.Announcement("已停止等待，問題仍保留。")
                .post()
        case .idle, .loading:
            break
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

    private func reconcileSavedCharts(
        previous: [SavedChartAssistantSnapshot],
        current: [SavedChartAssistantSnapshot]
    ) {
        guard let selectedID = assistantStore.selectedChart?.savedChartID else { return }
        guard let currentSnapshot = current.first(where: { $0.id == selectedID }) else {
            voiceCoordinator.stopAll()
            assistantStore.reconcileDeletedSavedChart(selectedID)
            loadDefaultChartIfNeeded()
            return
        }
        guard previous.first(where: { $0.id == selectedID }) != currentSnapshot,
              let savedChart = savedCharts.first(where: { $0.id == selectedID }) else {
            return
        }

        do {
            voiceCoordinator.stopAll()
            assistantStore.reconcileSelection(with: try makeAssistantChart(savedChart: savedChart))
        } catch {
            assistantStore.clearSelection()
            errorMessage = "命盤資料已更新，但目前無法重新準備命盤助理。請回到已儲存命盤重新建立。"
            loadDefaultChartIfNeeded()
        }
    }

    private func prepareSelection(_ savedChart: SavedChart) {
        do {
            let chart = try makeAssistantChart(savedChart: savedChart)
            guard assistantStore.selectedChart?.id != chart.id else { return }
            requestTransition(.switchChart(chart))
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

private extension ChartAssistantView {
    enum PendingTransition {
        case clear
        case switchChart(ChartAssistantChart)
    }

    enum TransitionError: Error {
        case saveFailed
    }
}
