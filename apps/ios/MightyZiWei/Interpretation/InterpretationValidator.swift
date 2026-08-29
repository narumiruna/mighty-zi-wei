import Foundation

struct InterpretationValidator: Sendable {
  enum ValidationError: LocalizedError, Equatable {
    case missingCategory(InterpretationCategory)
    case duplicateCategory(InterpretationCategory)
    case unknownSeed(String)
    case duplicateSeed(String)
    case seedCategoryMismatch(String)
    case invalidSeedEvidence(String)
    case unknownEvidence(String)
    case duplicateEvidence(String)
    case emptyEvidence(InterpretationCategory)
    case evidenceMismatch(InterpretationCategory)
    case emptyContent(InterpretationCategory)
    case unsafeContent(InterpretationCategory)

    var errorDescription: String? {
      switch self {
      case .missingCategory(let category):
        "缺少「\(category.title)」解讀。"
      case .duplicateCategory(let category):
        "「\(category.title)」出現重複解讀。"
      case .unknownSeed(let identifier):
        "解讀引用了未知線索：\(identifier)"
      case .duplicateSeed(let identifier):
        "解讀重複引用線索：\(identifier)"
      case .seedCategoryMismatch(let identifier):
        "解讀線索與分類不符：\(identifier)"
      case .invalidSeedEvidence(let identifier):
        "解讀線索缺少完整命盤依據：\(identifier)"
      case .unknownEvidence(let identifier):
        "解讀引用了未知依據：\(identifier)"
      case .duplicateEvidence(let identifier):
        "解讀重複引用依據：\(identifier)"
      case .emptyEvidence(let category):
        "「\(category.title)」沒有可驗證依據。"
      case .evidenceMismatch(let category):
        "「\(category.title)」的解讀線索與命盤依據不一致。"
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
    "替你診斷",
    "診斷結果是",
    "治療方案",
    "建議你買進",
    "建議你賣出",
    "應該買進",
    "應該賣出",
    "適合你的投資建議",
    "適合你的法律建議",
    "建議採取的訴訟策略",
  ]

  private let allowedDisclaimerPhrases = [
    "未必一定會",
    "不一定會",
    "不是一定會",
    "並非一定會",
    "不代表一定會",
    "不表示一定會",
    "無法保證",
    "不是保證",
    "並非保證",
    "不代表保證",
    "不等於保證",
    "不能視為保證",
    "不能保證",
    "不應保證",
    "不保證",
    "無法替你診斷",
    "不能替你診斷",
    "不會替你診斷",
    "無法判定診斷結果是",
    "不能判定診斷結果是",
    "不會宣稱診斷結果是",
    "無法提供治療方案",
    "不能提供治療方案",
    "不提供治療方案",
    "不構成任何投資建議",
    "不構成投資建議",
    "不是投資建議",
    "並非投資建議",
    "不可視為投資建議",
    "不構成任何法律建議",
    "不構成法律建議",
    "不是法律建議",
    "並非法律建議",
    "不可視為法律建議",
  ]

  func validate(
    sections: [InterpretationSection],
    facts: [ChartFact],
    seeds: [InterpretationSeed]
  ) throws -> [InterpretationSection] {
    let factIDs = Set(facts.map(\.id))
    let seedsByID = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })
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
      guard !section.evidenceSeedIDs.isEmpty,
        !section.evidenceFactIDs.isEmpty
      else {
        throw ValidationError.emptyEvidence(category)
      }

      var seenSeeds: Set<String> = []
      var expectedEvidence: [String] = []
      for identifier in section.evidenceSeedIDs {
        guard seenSeeds.insert(identifier).inserted else {
          throw ValidationError.duplicateSeed(identifier)
        }
        guard let seed = seedsByID[identifier] else {
          throw ValidationError.unknownSeed(identifier)
        }
        guard seed.category == category else {
          throw ValidationError.seedCategoryMismatch(identifier)
        }
        guard !seed.evidenceFactIDs.isEmpty,
          Set(seed.evidenceFactIDs).count == seed.evidenceFactIDs.count,
          seed.evidenceFactIDs.allSatisfy(factIDs.contains)
        else {
          throw ValidationError.invalidSeedEvidence(identifier)
        }
        for factID in seed.evidenceFactIDs where !expectedEvidence.contains(factID) {
          expectedEvidence.append(factID)
        }
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
      guard section.evidenceFactIDs == expectedEvidence else {
        throw ValidationError.evidenceMismatch(category)
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
  private static let unsupportedContent = "目前命盤資料不足以直接回答。你可以改問個性、工作方式、財務傾向、感情或人際互動。"

  enum ValidationError: LocalizedError, Equatable {
    case emptyContent
    case contentTooLong
    case emptyEvidence
    case unexpectedEvidence
    case unknownSeed(String)
    case duplicateSeed(String)
    case invalidSeedEvidence(String)
    case unknownEvidence(String)
    case duplicateEvidence(String)
    case evidenceMismatch
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
        "無法回答時不應附加解讀線索或命盤依據。"
      case .unknownSeed(let identifier):
        "回答引用了未知線索：\(identifier)"
      case .duplicateSeed(let identifier):
        "回答重複引用線索：\(identifier)"
      case .invalidSeedEvidence(let identifier):
        "回答線索缺少完整命盤依據：\(identifier)"
      case .unknownEvidence(let identifier):
        "回答引用了未知依據：\(identifier)"
      case .duplicateEvidence(let identifier):
        "回答重複引用依據：\(identifier)"
      case .evidenceMismatch:
        "回答線索與命盤依據不一致。"
      case .unsafeContent:
        "回答包含不允許的確定式或專業建議。"
      }
    }
  }

  private let blockedPhrases = [
    "一定會",
    "必定會",
    "保證",
    "替你診斷",
    "診斷結果是",
    "治療方案",
    "建議你買進",
    "建議你賣出",
    "應該買進",
    "應該賣出",
    "適合你的投資建議",
    "適合你的法律建議",
    "建議採取的訴訟策略",
  ]

  private let allowedDisclaimerPhrases = [
    "未必一定會",
    "不一定會",
    "不是一定會",
    "並非一定會",
    "不代表一定會",
    "不表示一定會",
    "無法保證",
    "不是保證",
    "並非保證",
    "不代表保證",
    "不等於保證",
    "不能視為保證",
    "不能保證",
    "不應保證",
    "不保證",
    "無法替你診斷",
    "不能替你診斷",
    "不會替你診斷",
    "無法判定診斷結果是",
    "不能判定診斷結果是",
    "不會宣稱診斷結果是",
    "無法提供治療方案",
    "不能提供治療方案",
    "不提供治療方案",
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
    "不可視為法律建議",
  ]

  func validate(
    _ answer: ChartConversationAnswer,
    facts: [ChartFact],
    seeds: [InterpretationSeed]
  ) throws -> ChartConversationAnswer {
    let content = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      throw ValidationError.emptyContent
    }
    guard content.count <= 2_000 else {
      throw ValidationError.contentTooLong
    }

    if answer.status == .unsupported {
      guard answer.evidenceSeedIDs.isEmpty,
        answer.evidenceFactIDs.isEmpty
      else {
        throw ValidationError.unexpectedEvidence
      }
      return ChartConversationAnswer(
        status: answer.status,
        content: Self.unsupportedContent,
        evidenceSeedIDs: [],
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

    guard !answer.evidenceSeedIDs.isEmpty,
      !answer.evidenceFactIDs.isEmpty
    else {
      throw ValidationError.emptyEvidence
    }
    let factIDs = Set(facts.map(\.id))
    let seedsByID = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })
    var seenSeeds: Set<String> = []
    var expectedEvidence: [String] = []
    for identifier in answer.evidenceSeedIDs {
      guard seenSeeds.insert(identifier).inserted else {
        throw ValidationError.duplicateSeed(identifier)
      }
      guard let seed = seedsByID[identifier] else {
        throw ValidationError.unknownSeed(identifier)
      }
      guard !seed.evidenceFactIDs.isEmpty,
        Set(seed.evidenceFactIDs).count == seed.evidenceFactIDs.count,
        seed.evidenceFactIDs.allSatisfy(factIDs.contains)
      else {
        throw ValidationError.invalidSeedEvidence(identifier)
      }
      for factID in seed.evidenceFactIDs where !expectedEvidence.contains(factID) {
        expectedEvidence.append(factID)
      }
    }

    var seenFacts: Set<String> = []
    for identifier in answer.evidenceFactIDs {
      guard seenFacts.insert(identifier).inserted else {
        throw ValidationError.duplicateEvidence(identifier)
      }
      guard factIDs.contains(identifier) else {
        throw ValidationError.unknownEvidence(identifier)
      }
    }
    guard answer.evidenceFactIDs == expectedEvidence else {
      throw ValidationError.evidenceMismatch
    }

    return ChartConversationAnswer(
      status: answer.status,
      content: content,
      evidenceSeedIDs: answer.evidenceSeedIDs,
      evidenceFactIDs: answer.evidenceFactIDs
    )
  }
}
