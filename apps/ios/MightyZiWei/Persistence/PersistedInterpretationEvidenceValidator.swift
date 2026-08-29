import Foundation

struct PersistedInterpretationEvidenceValidator: Sendable {
  func isValid(
    seedIDs: [String],
    factIDs: [String],
    seeds: [InterpretationSeed],
    validFactIDs: Set<String>
  ) -> Bool {
    guard factIDs.allSatisfy(validFactIDs.contains) else {
      return false
    }
    guard !seedIDs.isEmpty else {
      return true
    }
    guard Set(seedIDs).count == seedIDs.count else {
      return false
    }

    let seedsByID = Dictionary(
      seeds.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var seenFactIDs: Set<String> = []
    var expectedFactIDs: [String] = []
    for seedID in seedIDs {
      guard let seed = seedsByID[seedID],
        !seed.evidenceFactIDs.isEmpty,
        seed.evidenceFactIDs.allSatisfy(validFactIDs.contains)
      else {
        return false
      }
      for factID in seed.evidenceFactIDs where seenFactIDs.insert(factID).inserted {
        expectedFactIDs.append(factID)
      }
    }
    return factIDs == expectedFactIDs
  }
}
