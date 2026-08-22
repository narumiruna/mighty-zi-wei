import SwiftUI

struct InterpretationView: View {
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]

    @State private var interpretation: ChartInterpretation
    @State private var isGenerating = false
    @State private var statusMessage: String?
    @State private var generationTask: Task<Void, Never>?

    private let modelInterpreter = FoundationModelInterpreter()

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
    }

    private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    interpretation.source.title,
                    systemImage: interpretation.source == .onDeviceAI ? "apple.intelligence" : "text.book.closed"
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

            switch modelInterpreter.availability {
            case .available:
                Button {
                    generateWithAI()
                } label: {
                    Label(
                        interpretation.source == .onDeviceAI ? "重新整理" : "使用裝置端 AI 整理",
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            case .unavailable(let reason):
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func generateWithAI() {
        guard !isGenerating else { return }
        statusMessage = "正在根據已驗證的命盤依據整理文字…"
        isGenerating = true
        generationTask = Task {
            do {
                let result = try await modelInterpreter.generate(
                    facts: facts,
                    seeds: seeds
                ) { _ in
                    statusMessage = "裝置端模型正在整理，完成驗證前不會顯示內容。"
                }
                guard !Task.isCancelled else { return }
                interpretation = result
                statusMessage = "內容已通過命盤依據驗證。"
            } catch is CancellationError {
                statusMessage = "已停止整理，保留目前內容。"
            } catch {
                interpretation = RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
                statusMessage = "裝置端整理未完成，繼續顯示完整的基本解讀。"
            }
            isGenerating = false
            generationTask = nil
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        statusMessage = "已停止整理，保留目前內容。"
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
