import Foundation
import SwiftData

enum AssistantTransitionRisk: Equatable, Sendable {
    case none
    case draft
    case savedConversation
    case unsavedConversation
}

struct AssistantTransitionPolicy: Sendable {
    func risk(
        hasDraft: Bool,
        isRequesting: Bool,
        turnCount: Int,
        hasUnsavedChanges: Bool
    ) -> AssistantTransitionRisk {
        if isRequesting || hasUnsavedChanges {
            return .unsavedConversation
        }
        if hasDraft {
            return .draft
        }
        if turnCount > 0 {
            return .savedConversation
        }
        return .none
    }
}

@MainActor
struct AssistantConversationPersistence {
    func save(
        chart: ChartAssistantChart,
        turns: [ChartConversationTurn],
        modelIdentifier: String,
        title: String,
        existingID: UUID?,
        modelContext: ModelContext
    ) throws -> SavedConversation {
        guard !turns.isEmpty else {
            throw SaveError.emptyConversation
        }

        if let existingID,
           let existing = try fetch(id: existingID, modelContext: modelContext) {
            existing.update(turns: turns, modelIdentifier: modelIdentifier)
            do {
                try modelContext.save()
                return existing
            } catch {
                modelContext.rollback()
                throw error
            }
        }

        let conversation = SavedConversation(
            chartID: chart.savedChartID,
            chartName: chart.name,
            chartDetail: chart.detail,
            modelIdentifier: modelIdentifier,
            title: title,
            turns: turns
        )
        modelContext.insert(conversation)
        do {
            try modelContext.save()
            return conversation
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func fetch(
        id: UUID,
        modelContext: ModelContext
    ) throws -> SavedConversation? {
        var descriptor = FetchDescriptor<SavedConversation>(
            predicate: #Predicate { conversation in
                conversation.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    enum SaveError: Error, Equatable {
        case emptyConversation
    }
}

struct AssistantAtomicTransition {
    func perform(
        save: () throws -> Void,
        apply: () -> Void
    ) throws {
        try save()
        apply()
    }
}

enum AssistantComposerBlockReason: Equatable, Sendable {
    case empty
    case tooLong
    case requesting
    case roundLimit
    case voiceActive

    var message: String {
        switch self {
        case .empty:
            "輸入或選擇一個問題後即可送出。"
        case .tooLong:
            "問題超過 500 字，請刪減後再送出。"
        case .requesting:
            "正在等待回答，完成前不能再送出。"
        case .roundLimit:
            "本次對話已達 10 輪，請開始新對話。"
        case .voiceActive:
            "請先完成語音輸入，再確認問題。"
        }
    }
}

struct AssistantComposerPolicy: Sendable {
    func blockReason(
        draft: String,
        isRequesting: Bool,
        hasReachedRoundLimit: Bool,
        isVoiceActive: Bool
    ) -> AssistantComposerBlockReason? {
        if isRequesting { return .requesting }
        if hasReachedRoundLimit { return .roundLimit }
        if isVoiceActive { return .voiceActive }
        if draft.count > ChartAssistantStore.maximumQuestionLength { return .tooLong }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        return nil
    }
}

struct AssistantFollowUpSuggestionBuilder: Sendable {
    func make(for status: ChartConversationAnswer.Status) -> [String] {
        switch status {
        case .answered:
            [
                "有哪些值得留意的地方？",
                "可以再說明回答依據嗎？"
            ]
        case .unsupported:
            [
                "我的個性有哪些值得留意的地方？",
                "我的工作方式可能有什麼特色？"
            ]
        }
    }
}
