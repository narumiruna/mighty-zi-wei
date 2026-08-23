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
            if blockedPhrases.contains(where: section.content.contains) {
                throw ValidationError.unsafeContent(category)
            }
            validated.append(section)
        }

        return validated
    }
}
