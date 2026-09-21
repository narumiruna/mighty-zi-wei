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

    init(_ error: InterpretationEvidenceResolver.ResolutionError) {
      switch error {
      case .duplicateFact(let id): self = .duplicateEvidence(id)
      case .unknownFact(let id): self = .unknownEvidence(id)
      case .duplicateSeed(let id): self = .duplicateSeed(id)
      case .unknownSeed(let id): self = .unknownSeed(id)
      case .seedCategoryMismatch(let id): self = .seedCategoryMismatch(id)
      case .invalidSeedEvidence(let id): self = .invalidSeedEvidence(id)
      }
    }
  }

  func validate(
    sections: [InterpretationSection], facts: [ChartFact], seeds: [InterpretationSeed]
  ) throws -> [InterpretationSection] {
    do {
      let resolver = try InterpretationEvidenceResolver(factIDs: facts.map(\.id), seeds: seeds)
      return try InterpretationCategory.allCases.map { category in
        try validate(sections: sections, category: category, resolver: resolver)
      }
    } catch let error as InterpretationEvidenceResolver.ResolutionError {
      throw ValidationError(error)
    }
  }

  private func validate(
    sections: [InterpretationSection], category: InterpretationCategory,
    resolver: InterpretationEvidenceResolver
  ) throws -> InterpretationSection {
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
    guard !section.evidenceSeedIDs.isEmpty, !section.evidenceFactIDs.isEmpty else {
      throw ValidationError.emptyEvidence(category)
    }
    let expected = try resolver.resolve(seedIDs: section.evidenceSeedIDs, category: category)
    try resolver.validate(factIDs: section.evidenceFactIDs)
    guard section.evidenceFactIDs == expected else {
      throw ValidationError.evidenceMismatch(category)
    }
    if GeneratedContentSafetyPolicy().isUnsafe(section.content, context: .interpretation) {
      throw ValidationError.unsafeContent(category)
    }
    return section
  }
}
