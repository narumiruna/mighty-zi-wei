import Foundation

struct PersistedInterpretationEvidenceValidator: Sendable {
  enum ReadingStatus: Equatable, Sendable {
    case currentReferences
    case archivedWithoutVersion
    case unavailableVersion(String)
    case invalidReferences

    var limitation: String? {
      switch self {
      case .currentReferences: nil
      case .archivedWithoutVersion:
        "來源版本未保存。原文與引用僅供歷史閱讀，不回填目前規則或審閱認證。"
      case .unavailableVersion(let version):
        "這台裝置沒有內容版本 \(version) 的歷史契約。保留原文，但不能核對當時引用。"
      case .invalidReferences:
        "原有引用無法完整核對。保留原文供回顧，不作為目前已驗證的解讀依據。"
      }
    }
  }

  /// 只判定引用是否可核對；即使目前引用有效，也不證明封存文字的逐句語意。
  func readingStatus(
    contentVersion: String?,
    seedIDs: [String],
    factIDs: [String],
    seeds: [InterpretationSeed],
    validFactIDs: Set<String>
  ) -> ReadingStatus {
    guard let contentVersion else { return .archivedWithoutVersion }
    guard contentVersion == InterpretationContentVersion.current.rawValue else {
      return .unavailableVersion(contentVersion)
    }
    guard !seedIDs.isEmpty, !factIDs.isEmpty,
      isValid(seedIDs: seedIDs, factIDs: factIDs, seeds: seeds, validFactIDs: validFactIDs)
    else { return .invalidReferences }
    return .currentReferences
  }

  func isValid(
    seedIDs: [String],
    factIDs: [String],
    seeds: [InterpretationSeed],
    validFactIDs: Set<String>
  ) -> Bool {
    guard Set(factIDs).count == factIDs.count,
      Set(seeds.map(\.id)).count == seeds.count,
      factIDs.allSatisfy(validFactIDs.contains)
    else {
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
        Set(seed.evidenceFactIDs).count == seed.evidenceFactIDs.count,
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
