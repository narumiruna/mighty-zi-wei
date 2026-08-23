import Foundation

struct InterpretationValidator: Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case missingCategory(InterpretationCategory)
        case duplicateCategory(InterpretationCategory)
        case unknownEvidence(String)
        case duplicateEvidence(String)
        case emptyEvidence(InterpretationCategory)
        case emptyContent(InterpretationCategory)
        case unsafeContent(InterpretationCategory)

        var errorDescription: String? {
            switch self {
            case .missingCategory(let category):
                "缺少「\(category.title)」解讀。"
            case .duplicateCategory(let category):
                "「\(category.title)」出現重複解讀。"
            case .unknownEvidence(let identifier):
                "解讀引用了未知依據：\(identifier)"
            case .duplicateEvidence(let identifier):
                "解讀重複引用依據：\(identifier)"
            case .emptyEvidence(let category):
                "「\(category.title)」沒有可驗證依據。"
            case .emptyContent(let category):
                "「\(category.title)」沒有可顯示內容。"
            case .unsafeContent(let category):
                "「\(category.title)」包含不允許的確定式或專業建議。"
            }
        }
    }

    private let blockedPhrases = [
        "一定會",
        "必定會",
        "保證",
        "診斷",
        "治療",
        "買進",
        "賣出",
        "投資建議",
        "法律建議",
        "訴訟策略"
    ]

    private let allowedDisclaimerPhrases = [
        "不構成任何投資建議",
        "不構成投資建議",
        "不是投資建議",
        "並非投資建議",
        "不可視為投資建議",
        "不構成任何法律建議",
        "不構成法律建議",
        "不是法律建議",
        "並非法律建議",
        "不可視為法律建議"
    ]

    func validate(
        sections: [InterpretationSection],
        facts: [ChartFact]
    ) throws -> [InterpretationSection] {
        let factIDs = Set(facts.map(\.id))
        var validated: [InterpretationSection] = []

        for category in InterpretationCategory.allCases {
            let matchingSections = sections.filter { $0.category == category }
            guard let section = matchingSections.first else {
                throw ValidationError.missingCategory(category)
            }
            guard matchingSections.count == 1 else {
                throw ValidationError.duplicateCategory(category)
            }
            guard !section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyContent(category)
            }
            guard !section.evidenceFactIDs.isEmpty else {
                throw ValidationError.emptyEvidence(category)
            }
            var seenEvidence: Set<String> = []
            for identifier in section.evidenceFactIDs {
                guard seenEvidence.insert(identifier).inserted else {
                    throw ValidationError.duplicateEvidence(identifier)
                }
                guard factIDs.contains(identifier) else {
                    throw ValidationError.unknownEvidence(identifier)
                }
            }
            let contentForSafetyCheck = allowedDisclaimerPhrases.reduce(section.content) {
                content, disclaimer in
                content.replacingOccurrences(of: disclaimer, with: "")
            }
            if blockedPhrases.contains(where: contentForSafetyCheck.contains) {
                throw ValidationError.unsafeContent(category)
            }
            validated.append(section)
        }

        return validated
    }
}

struct ConversationAnswerValidator: Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case emptyContent
        case contentTooLong
        case emptyEvidence
        case unexpectedEvidence
        case unknownEvidence(String)
        case duplicateEvidence(String)
        case unsafeContent

        var errorDescription: String? {
            switch self {
            case .emptyContent:
                "回答沒有可顯示內容。"
            case .contentTooLong:
                "回答超過可接受的長度。"
            case .emptyEvidence:
                "回答沒有可驗證的命盤依據。"
            case .unexpectedEvidence:
                "無法回答時不應附加命盤依據。"
            case .unknownEvidence(let identifier):
                "回答引用了未知依據：\(identifier)"
            case .duplicateEvidence(let identifier):
                "回答重複引用依據：\(identifier)"
            case .unsafeContent:
                "回答包含不允許的確定式或專業建議。"
            }
        }
    }

    private let blockedPhrases = [
        "一定會",
        "必定會",
        "保證",
        "診斷",
        "治療",
        "買進",
        "賣出",
        "投資建議",
        "法律建議",
        "訴訟策略"
    ]

    private let allowedDisclaimerPhrases = [
        "無法提供健康診斷",
        "不能提供健康診斷",
        "不提供健康診斷",
        "無法提供投資建議",
        "不能提供投資建議",
        "不提供投資建議",
        "無法提供法律建議",
        "不能提供法律建議",
        "不提供法律建議",
        "不構成任何投資建議",
        "不構成投資建議",
        "不是投資建議",
        "並非投資建議",
        "不可視為投資建議",
        "不構成任何法律建議",
        "不構成法律建議",
        "不是法律建議",
        "並非法律建議",
        "不可視為法律建議"
    ]

    func validate(
        _ answer: ChartConversationAnswer,
        facts: [ChartFact]
    ) throws -> ChartConversationAnswer {
        let content = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ValidationError.emptyContent
        }
        guard content.count <= 2_000 else {
            throw ValidationError.contentTooLong
        }

        if answer.status == .unsupported {
            guard answer.evidenceFactIDs.isEmpty else {
                throw ValidationError.unexpectedEvidence
            }
            return ChartConversationAnswer(
                status: answer.status,
                content: "這個問題超出目前命盤資料可安全回答的範圍。你可以改問個性、工作、財務傾向或感情與人際。",
                evidenceFactIDs: []
            )
        }

        let contentForSafetyCheck = allowedDisclaimerPhrases.reduce(content) {
            result, disclaimer in
            result.replacingOccurrences(of: disclaimer, with: "")
        }
        guard !blockedPhrases.contains(where: contentForSafetyCheck.contains) else {
            throw ValidationError.unsafeContent
        }

        guard !answer.evidenceFactIDs.isEmpty else {
            throw ValidationError.emptyEvidence
        }
        let factIDs = Set(facts.map(\.id))
        var seen: Set<String> = []
        for identifier in answer.evidenceFactIDs {
            guard seen.insert(identifier).inserted else {
                throw ValidationError.duplicateEvidence(identifier)
            }
            guard factIDs.contains(identifier) else {
                throw ValidationError.unknownEvidence(identifier)
            }
        }

        return ChartConversationAnswer(
            status: answer.status,
            content: content,
            evidenceFactIDs: answer.evidenceFactIDs
        )
    }
}
