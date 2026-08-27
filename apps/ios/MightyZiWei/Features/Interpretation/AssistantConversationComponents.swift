import SwiftUI
import UIKit

struct AITransmissionPreviewView: View {
    let chart: ChartAssistantChart
    let question: String
    let historyCount: Int
    let model: String
    let remainingRequests: Int?
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsTechnicalDetails = false

    var body: some View {
        NavigationStack {
            Form {
                Section("即將送出的問題") {
                    Text(question)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("assistant.preview.question")
                }

                Section("這次會使用") {
                    Label("目前命盤的必要解讀依據", systemImage: "checkmark.seal")
                    LabeledContent("本次對話", value: "\(historyCount) 輪")
                    LabeledContent("本機請求紀錄", value: "增加 1 次")
                    if let remainingRequests {
                        LabeledContent("送出後本月剩餘", value: "\(max(0, remainingRequests - 1)) 次")
                    } else {
                        LabeledContent("每月請求上限", value: "未設定")
                    }
                }

                Section {
                    DisclosureGroup(
                        "查看傳送詳細資料",
                        isExpanded: $showsTechnicalDetails
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("已驗證命盤事實", value: "\(chart.facts.count) 項")
                            LabeledContent("基礎解讀種子", value: "\(chart.seeds.count) 項")
                            LabeledContent("模型", value: model)
                            Divider()
                            Label("不加入命盤名稱", systemImage: "xmark.shield")
                            Label("不加入原始出生日期、時間與時區", systemImage: "xmark.shield")
                            Label("不加入 API key、筆記、收藏與已保存對話", systemImage: "xmark.shield")
                        }
                        .padding(.top, 8)
                    }
                    .accessibilityIdentifier("assistant.preview.details")
                } footer: {
                    Text("你自行輸入在問題中的個人資料仍會原樣傳送，第三方服務也可能依其費率收費。")
                }

                Section {
                    Button {
                        confirm()
                    } label: {
                        Label("送出問題", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistant.confirmSend")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .navigationTitle("確認傳送內容")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回修改") { dismiss() }
                }
            }
        }
    }
}

struct ConversationTurnView: View {
    let turn: ChartConversationTurn
    let factsByID: [String: ChartFact]
    let chartID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("你的問題")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                Text(turn.question)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("你的問題：\(turn.question)")

            if turn.status == .unsupported {
                unsupportedAnswer
            } else {
                verifiedAnswer
            }
        }
        .accessibilityIdentifier("assistant.answer")
    }

    private var verifiedAnswer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("命盤助理", systemImage: "sparkles")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Label("已確認引用命盤依據", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("assistant.answer.verified")
            Text(turn.answer)
                .lineSpacing(5)
                .textSelection(.enabled)

            ViewThatFits(in: .horizontal) {
                HStack {
                    VoicePlaybackControls(
                        contentID: "assistant.\(turn.id.uuidString)",
                        text: turn.answer
                    )
                    Spacer()
                    bookmark
                }
                VStack(alignment: .leading, spacing: 8) {
                    VoicePlaybackControls(
                        contentID: "assistant.\(turn.id.uuidString)",
                        text: turn.answer
                    )
                    bookmark
                }
            }

            Divider()
            DisclosureGroup("回答依據") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(turn.evidenceFactIDs, id: \.self) { identifier in
                        if let fact = factsByID[identifier] {
                            Label(fact.displayText, systemImage: "checkmark.seal")
                                .font(.footnote)
                                .accessibilityLabel("已驗證依據：\(fact.displayText)")
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private var bookmark: some View {
        InsightBookmarkButton(
            chartID: chartID,
            locationID: "assistant.\(turn.id.uuidString)",
            title: "命盤助理：\(turn.question)",
            content: turn.answer,
            evidenceFactIDs: turn.evidenceFactIDs
        )
    }

    private var unsupportedAnswer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("目前無法用命盤回答", systemImage: "questionmark.bubble")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(turn.answer)
                .lineSpacing(5)
            Text("可以改問個性、工作方式、財務傾向、感情或人際互動。")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("assistant.answer.unsupported")
        .accessibilityElement(children: .combine)
    }
}

struct AssistantFollowUpQuestionsView: View {
    let status: ChartConversationAnswer.Status
    let isEnabled: Bool
    let select: (String) -> Void

    private var questions: [String] {
        AssistantFollowUpSuggestionBuilder().make(for: status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("接著可以問")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                Button {
                    select(question)
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
                .disabled(!isEnabled)
                .accessibilityHint("將問題填入輸入框，不會立即送出")
                .accessibilityIdentifier("assistant.followUp.\(index)")
            }
        }
        .cardStyle()
    }
}
