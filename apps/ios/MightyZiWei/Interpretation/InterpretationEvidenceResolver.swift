import Foundation

/// 只管理 seed 與 fact 引用；內容、分類需求與封存狀態由各驗證器決定。
struct InterpretationEvidenceResolver: Sendable {
  enum ResolutionError: Error, Equatable {
    case duplicateFact(String)
    case unknownFact(String)
    case duplicateSeed(String)
    case unknownSeed(String)
    case seedCategoryMismatch(String)
    case invalidSeedEvidence(String)
  }

  private let factIDs: Set<String>
  private let seedsByID: [String: InterpretationSeed]

  init(factIDs: [String], seeds: [InterpretationSeed]) throws(ResolutionError) {
    var uniqueFacts: Set<String> = []
    for identifier in factIDs where !uniqueFacts.insert(identifier).inserted {
      throw .duplicateFact(identifier)
    }
    var uniqueSeeds: [String: InterpretationSeed] = [:]
    for seed in seeds {
      guard uniqueSeeds.updateValue(seed, forKey: seed.id) == nil else {
        throw .duplicateSeed(seed.id)
      }
    }
    self.factIDs = uniqueFacts
    seedsByID = uniqueSeeds
  }

  func resolve(
    seedIDs: [String], category: InterpretationCategory? = nil
  ) throws(ResolutionError) -> [String] {
    var seenSeeds: Set<String> = []
    var seenFacts: Set<String> = []
    var evidence: [String] = []
    for identifier in seedIDs {
      guard seenSeeds.insert(identifier).inserted else { throw .duplicateSeed(identifier) }
      guard let seed = seedsByID[identifier] else { throw .unknownSeed(identifier) }
      if let category, seed.category != category { throw .seedCategoryMismatch(identifier) }
      guard !seed.evidenceFactIDs.isEmpty,
        Set(seed.evidenceFactIDs).count == seed.evidenceFactIDs.count,
        seed.evidenceFactIDs.allSatisfy(factIDs.contains)
      else { throw .invalidSeedEvidence(identifier) }
      for factID in seed.evidenceFactIDs where seenFacts.insert(factID).inserted {
        evidence.append(factID)
      }
    }
    return evidence
  }

  func validate(factIDs selectedIDs: [String]) throws(ResolutionError) {
    var seen: Set<String> = []
    for identifier in selectedIDs {
      guard seen.insert(identifier).inserted else { throw .duplicateFact(identifier) }
      guard factIDs.contains(identifier) else { throw .unknownFact(identifier) }
    }
  }
}
