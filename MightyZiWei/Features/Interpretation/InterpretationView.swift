import SwiftUI

struct InterpretationView: View {
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]

    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
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
                sourceHeader
                DisclaimerView()

                ForEach(interpretation.sections) { section in
                    InterpretationSectionView(
                        section: section,
                        factsByID: Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
                    )
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
        }
        .sheet(isPresented: $showsAPIConfiguration) {
            APIConfigurationSheet()
        }
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
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

private struct InterpretationSectionView: View {
    let section: InterpretationSection
    let factsByID: [String: ChartFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title3.weight(.semibold))

            Text(section.content)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)

            Divider()

            DisclosureGroup("解讀依據") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.evidenceFactIDs, id: \.self) { identifier in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
