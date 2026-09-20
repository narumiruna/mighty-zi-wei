import Foundation

enum ConversationAnswerContentPolicy {
  static let internalLabels = [
    "使用到的解讀",
    "使用到的 seed",
    "evidenceSeedIDs",
    "evidenceFactIDs",
  ]

  static let markdownMarkers = ["**", "__", "`"]

  static func containsInternalDetails(_ content: String, identifiers: [String]) -> Bool {
    (internalLabels + identifiers).contains(where: content.contains)
  }

  static func containsMarkdown(_ content: String) -> Bool {
    markdownMarkers.contains(where: content.contains)
  }

  static func displayText(_ content: String, hiding identifiers: [String]) -> String {
    let cutoff =
      (internalLabels + identifiers)
      .compactMap { content.range(of: $0)?.lowerBound }
      .min() ?? content.endIndex
    let visibleContent = String(content[..<cutoff])
    let plainText = markdownMarkers.reduce(visibleContent) { result, marker in
      result.replacingOccurrences(of: marker, with: "")
    }
    .replacingOccurrences(of: " ：", with: "：")
    .replacingOccurrences(of: " :", with: "：")
    .trimmingCharacters(in: .whitespacesAndNewlines)

    return plainText.isEmpty ? "這則回答無法完整顯示，請重新提問。" : plainText
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
    case internalDetails
    case markdownContent
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
      case .internalDetails:
        "回答包含不應顯示的內部依據識別碼。"
      case .markdownContent:
        "回答包含不支援的 Markdown 標記。"
      case .unsafeContent:
        "回答包含不允許的確定式或專業建議。"
      }
    }

    init(_ error: InterpretationEvidenceResolver.ResolutionError) {
      switch error {
      case .duplicateFact(let id): self = .duplicateEvidence(id)
      case .unknownFact(let id): self = .unknownEvidence(id)
      case .duplicateSeed(let id): self = .duplicateSeed(id)
      case .unknownSeed(let id): self = .unknownSeed(id)
      case .seedCategoryMismatch(let id), .invalidSeedEvidence(let id):
        self = .invalidSeedEvidence(id)
      }
    }
  }

  func validate(
    _ answer: ChartConversationAnswer, facts: [ChartFact], seeds: [InterpretationSeed]
  ) throws -> ChartConversationAnswer {
    let content = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { throw ValidationError.emptyContent }
    guard content.count <= 2_000 else { throw ValidationError.contentTooLong }

    if answer.status == .unsupported {
      guard answer.evidenceSeedIDs.isEmpty, answer.evidenceFactIDs.isEmpty else {
        throw ValidationError.unexpectedEvidence
      }
      return ChartConversationAnswer(
        status: answer.status, content: Self.unsupportedContent,
        evidenceSeedIDs: [], evidenceFactIDs: [])
    }

    let internalIdentifiers = facts.map(\.id) + seeds.map(\.id)
    guard
      !ConversationAnswerContentPolicy.containsInternalDetails(
        content, identifiers: internalIdentifiers)
    else { throw ValidationError.internalDetails }
    guard !ConversationAnswerContentPolicy.containsMarkdown(content) else {
      throw ValidationError.markdownContent
    }
    guard !GeneratedContentSafetyPolicy().isUnsafe(content, context: .conversation) else {
      throw ValidationError.unsafeContent
    }
    guard !answer.evidenceSeedIDs.isEmpty, !answer.evidenceFactIDs.isEmpty else {
      throw ValidationError.emptyEvidence
    }
    do {
      let resolver = try InterpretationEvidenceResolver(factIDs: facts.map(\.id), seeds: seeds)
      let expected = try resolver.resolve(seedIDs: answer.evidenceSeedIDs)
      try resolver.validate(factIDs: answer.evidenceFactIDs)
      guard answer.evidenceFactIDs == expected else { throw ValidationError.evidenceMismatch }
    } catch let error as InterpretationEvidenceResolver.ResolutionError {
      throw ValidationError(error)
    }
    return ChartConversationAnswer(
      status: answer.status, content: content,
      evidenceSeedIDs: answer.evidenceSeedIDs, evidenceFactIDs: answer.evidenceFactIDs)
  }
}
