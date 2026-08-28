import SwiftUI
import UIKit

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
