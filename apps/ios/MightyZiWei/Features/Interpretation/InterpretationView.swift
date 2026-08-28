import Accessibility
import SwiftData
import SwiftUI

struct InterpretationDisplayState: Equatable, Sendable {
    let basic: ChartInterpretation
    private(set) var ai: ChartInterpretation?
    private(set) var selectedSource: ChartInterpretation.Source = .deterministic

    var selected: ChartInterpretation {
        guard selectedSource == .remoteAI, let ai else { return basic }
        return ai
    }

    mutating func select(_ source: ChartInterpretation.Source) {
        guard source == .deterministic || ai != nil else { return }
        selectedSource = source
    }

    mutating func acceptAI(_ interpretation: ChartInterpretation) {
        let isFirstResult = ai == nil
        ai = interpretation
        if isFirstResult {
            selectedSource = .remoteAI
        }
    }
}

struct InterpretationView: View {
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]
    let chartID: UUID?

    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
    @Environment(AIUsageStore.self) private var usageStore
    @Environment(VoiceCoordinator.self) private var voiceCoordinator
    @State private var displayState: InterpretationDisplayState
    @State private var isGenerating = false
    @State private var statusMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var showsAPIConfiguration = false
    @State private var showsTransmissionPreview = false

    private let modelInterpreter = OpenAIResponsesInterpreter()

    init(
        facts: [ChartFact],
        seeds: [InterpretationSeed],
        chartID: UUID? = nil
    ) {
        self.facts = facts
        self.seeds = seeds
        self.chartID = chartID
        _displayState = State(initialValue: InterpretationDisplayState(
            basic: RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                sourceHeader

                if let overview = selectedInterpretation.sections.first(
                    where: { $0.category == .overview }
                ) {
                    InterpretationOverviewView(
                        section: overview,
                        factsByID: factsByID,
                        chartID: chartID
                    )
                }

                DisclaimerView()

                VStack(alignment: .leading, spacing: 12) {
                    Text("接著想了解什麼？")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(
                        selectedInterpretation.sections.filter { $0.category != .overview }
                    ) { section in
                        InterpretationCategoryDisclosure(
                            section: section,
                            factsByID: factsByID,
                            chartID: chartID
                        )
                    }
                }
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
        .sheet(isPresented: $showsTransmissionPreview) {
            AIInterpretationPreviewView(
                factCount: facts.count,
                seedCount: seeds.count,
                model: aiConfigurationStore.model,
                remainingRequests: usageStore.remainingRequests
            ) {
                showsTransmissionPreview = false
                generateWithAI()
            }
        }
    }

    private var factsByID: [String: ChartFact] {
        Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
    }

    private var selectedInterpretation: ChartInterpretation {
        displayState.selected
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("解讀版本")
                .font(.headline)
                .accessibilityIdentifier("interpretation.source")

            HStack(spacing: 10) {
                Image(
                    systemName: displayState.selectedSource == .remoteAI
                        ? "cloud"
                        : "text.book.closed"
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedInterpretation.source.title)
                        .font(.headline)
                    Text(displayState.selectedSource == .remoteAI ? "第三方整理版本" : "本機基本版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isGenerating {
                    ProgressView()
                        .accessibilityLabel("正在產生命盤解讀")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                displayState.selectedSource == .remoteAI
                    ? "目前版本：雲端 AI 整理，第三方整理版本"
                    : "目前版本：基本解讀，本機基本版本"
            )
            .accessibilityIdentifier("interpretation.source.current")

            if displayState.ai != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sourceChoices
                    }
                    VStack(spacing: 10) {
                        sourceChoices
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("interpretation.status")
            }

            Text("基本解讀會一直保留。App 會要求 AI 只整理既有內容，並驗證格式、安全與命盤依據，但無法保證 AI 不會改變語意。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if aiConfigurationStore.isConfigured {
                Button {
                    showsTransmissionPreview = true
                } label: {
                    Label(
                        displayState.ai == nil ? "用 AI 整理文字" : "重新整理文字",
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                .accessibilityIdentifier("interpretation.organizeWithAI")
            } else {
                Text("完成 API 設定後，才會在你主動要求時傳送命盤事實與基礎解讀。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    presentAPIConfiguration()
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

    @ViewBuilder
    private var sourceChoices: some View {
        sourceChoice(
            source: .deterministic,
            title: "基本解讀",
            detail: "本機",
            systemImage: "text.book.closed"
        )
        sourceChoice(
            source: .remoteAI,
            title: "AI 整理",
            detail: "第三方",
            systemImage: "sparkles"
        )
    }

    private func sourceChoice(
        source: ChartInterpretation.Source,
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        Button {
            selectSource(source)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: displayState.selectedSource == source ? "checkmark.circle.fill" : systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(displayState.selectedSource == source ? .accentColor : .secondary)
        .accessibilityValue(displayState.selectedSource == source ? "目前版本" : "可切換")
        .accessibilityIdentifier(
            source == .remoteAI
                ? "interpretation.source.ai"
                : "interpretation.source.basic"
        )
    }

    private func selectSource(_ source: ChartInterpretation.Source) {
        guard displayState.selectedSource != source else { return }
        let previousSource = displayState.selectedSource
        displayState.select(source)
        guard displayState.selectedSource != previousSource else { return }
        voiceCoordinator.stopOutput()
    }

    private func presentAPIConfiguration() {
        voiceCoordinator.stopAll {
            showsAPIConfiguration = true
        }
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
                try usageStore.reserve(.interpretation)
                let result = try await generateInterpretation(configuration: configuration)
                let validatedSections = try InterpretationValidator().validate(
                    sections: result.sections,
                    facts: facts
                )
                try Task.checkCancellation()
                guard generationID == identifier else { return }
                voiceCoordinator.stopOutput()
                displayState.acceptAI(ChartInterpretation(
                    sections: validatedSections,
                    source: .remoteAI
                ))
                statusMessage = "已確認回傳格式、內容安全與引用的命盤依據。"
                AccessibilityNotification.Announcement(
                    displayState.selectedSource == .remoteAI
                        ? "AI 整理完成，目前顯示 AI 整理版本。"
                        : "AI 整理完成，目前繼續顯示基本解讀。"
                ).post()
            } catch is CancellationError {
                guard generationID == identifier else { return }
                statusMessage = "已停止整理，保留目前內容。"
            } catch {
                guard generationID == identifier else { return }
                usageStore.record(error: error, kind: .interpretation)
                statusMessage = generationFailureMessage(for: error)
            }
            guard generationID == identifier else { return }
            isGenerating = false
            generationTask = nil
            generationID = nil
        }
    }

    private func generateInterpretation(
        configuration: OpenAIResponsesConfiguration
    ) async throws -> ChartInterpretation {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestMockAI") else {
            return try await modelInterpreter.generate(
                facts: facts,
                seeds: seeds,
                configuration: configuration
            )
        }

        try await Task.sleep(for: .seconds(3))
        if arguments.contains("-UITestMockAIInterpretationFailure") {
            throw OpenAIResponsesInterpreter.InterpreterError.timedOut
        }
        let fallback = RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
        let sections = fallback.sections.map { section in
            InterpretationSection(
                id: "ai.\(section.category.rawValue)",
                category: section.category,
                title: section.title,
                content: section.content,
                evidenceFactIDs: section.evidenceFactIDs
            )
        }
        return ChartInterpretation(sections: sections, source: .remoteAI)
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
                return "API 授權失敗，請檢查 API key；目前版本與既有內容保持不變。"
            case .rateLimited:
                return "API 已達速率或額度限制；目前版本與既有內容保持不變。"
            case .timedOut:
                return "API 回應逾時；目前版本與既有內容保持不變。"
            default:
                break
            }
        }
        if error is OpenAIResponsesConfiguration.ValidationError {
            return "API 設定不完整；目前版本與既有內容保持不變。"
        }
        if error is KeychainAPICredentialStore.CredentialError {
            return "目前無法讀取 API key；請回到 API 設定確認，既有內容仍可正常使用。"
        }
        return "雲端整理未完成，目前版本與既有內容保持不變。"
    }
}

private struct AIInterpretationPreviewView: View {
    let factCount: Int
    let seedCount: Int
    let model: String
    let remainingRequests: Int?
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsDetails = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 會做什麼") {
                    Text("把目前完整基本解讀整理成更自然、好讀的版本，不會改變命盤或加入新的命理含義。")
                    Label("完成本機命盤依據驗證後才會顯示", systemImage: "checkmark.seal")
                }

                Section("這次會使用") {
                    Label("目前命盤的必要解讀依據", systemImage: "text.book.closed")
                    LabeledContent("本機請求紀錄", value: "增加 1 次")
                    if let remainingRequests {
                        LabeledContent("整理後本月剩餘", value: "\(max(0, remainingRequests - 1)) 次")
                    } else {
                        LabeledContent("每月請求上限", value: "未設定")
                    }
                }

                Section {
                    DisclosureGroup("查看傳送詳細資料", isExpanded: $showsDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("已驗證命盤事實", value: "\(factCount) 項")
                            LabeledContent("基礎解讀種子", value: "\(seedCount) 項")
                            LabeledContent("模型", value: model)
                            Divider()
                            Label("不傳送命盤名稱與原始出生資料", systemImage: "xmark.shield")
                            Label("不傳送 API key、筆記或收藏", systemImage: "xmark.shield")
                        }
                        .padding(.top, 8)
                    }
                    .accessibilityIdentifier("interpretation.preview.details")
                } footer: {
                    Text("第三方服務可能依其費率收費。")
                }

                Section {
                    Button {
                        confirm()
                    } label: {
                        Label("開始整理", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("interpretation.confirmOrganize")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .navigationTitle("確認 AI 整理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回閱讀") { dismiss() }
                }
            }
        }
    }
}

struct APIConfigurationSheet: View {
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

private struct InterpretationOverviewView: View {
    let section: InterpretationSection
    let factsByID: [String: ChartFact]
    let chartID: UUID?

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

            HStack {
                VoicePlaybackControls(
                    contentID: "interpretation.\(section.id)",
                    text: "\(section.title)。\(section.content)"
                )
                Spacer()
                InsightBookmarkButton(
                    chartID: chartID,
                    locationID: "interpretation.\(section.id)",
                    title: section.title,
                    content: section.content,
                    evidenceFactIDs: section.evidenceFactIDs
                )
            }

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
    let chartID: UUID?

    @Environment(VoiceCoordinator.self) private var voiceCoordinator
    @State private var isExpanded = false

    private var playbackContentID: String {
        "interpretation.\(section.id)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.content)
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    HStack {
                        VoicePlaybackControls(
                            contentID: playbackContentID,
                            text: "\(section.title)。\(section.content)"
                        )
                        Spacer()
                        InsightBookmarkButton(
                            chartID: chartID,
                            locationID: "interpretation.\(section.id)",
                            title: section.title,
                            content: section.content,
                            evidenceFactIDs: section.evidenceFactIDs
                        )
                    }

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
            .accessibilityIdentifier("interpretation.category.\(section.category.rawValue)")

            if !isExpanded, voiceCoordinator.outputStatusContentID == playbackContentID {
                VoicePlaybackControls(
                    contentID: playbackContentID,
                    text: "\(section.title)。\(section.content)"
                )
            }
        }
        .cardStyle()
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
