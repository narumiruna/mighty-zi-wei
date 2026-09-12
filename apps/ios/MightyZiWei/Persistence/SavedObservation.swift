import Foundation
import SwiftData

/// 只供歷史回顧的單段快照，不得作為目前 builder 或 AI 的輸入依據。
struct ObservationSnapshot: Codable, Equatable, Sendable {
  enum Source: String, Codable, Sendable {
    case localInterpretation
    case selectedAIParagraph

    var title: String {
      switch self {
      case .localInterpretation: "本機基本解讀"
      case .selectedAIParagraph: "使用者選取的 AI 單段文字"
      }
    }
  }

  static let currentSchemaVersion = 1
  let schemaVersion: Int
  let selectedText: String
  let initialThought: String
  let source: Source
  let locationID: String
  let contentVersion: String?
  let ruleSetID: String
  let ruleSetVersion: Int
  let facts: [ChartFact]
  let seeds: [InterpretationSeed]

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    selectedText: String,
    initialThought: String,
    source: Source,
    locationID: String,
    contentVersion: String?,
    ruleSetID: String,
    ruleSetVersion: Int,
    facts: [ChartFact],
    seeds: [InterpretationSeed]
  ) {
    self.schemaVersion = schemaVersion
    self.selectedText = selectedText
    self.initialThought = initialThought
    self.source = source
    self.locationID = locationID
    self.contentVersion = contentVersion
    self.ruleSetID = ruleSetID
    self.ruleSetVersion = ruleSetVersion
    self.facts = facts
    self.seeds = seeds
  }

  var versionDescription: String {
    guard let contentVersion else { return "來源版本未保存" }
    return "當時內容版本：\(contentVersion)；僅供歷史回顧，不代表目前已審閱"
  }

  func validate() throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw ObservationError.unsupportedSchema(schemaVersion)
    }
    guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      selectedText.rangeOfCharacter(from: .newlines) == nil,
      !locationID.isEmpty, !ruleSetID.isEmpty, ruleSetVersion > 0,
      contentVersion.map({ !$0.isEmpty }) ?? true,
      !seeds.isEmpty,
      Set(facts.map(\.id)).count == facts.count,
      Set(seeds.map(\.id)).count == seeds.count,
      facts.allSatisfy({ !$0.id.isEmpty && !$0.displayText.isEmpty }),
      seeds.allSatisfy({ !$0.id.isEmpty && !$0.meaning.isEmpty }),
      PersistedInterpretationEvidenceValidator().isValid(
        seedIDs: seeds.map(\.id),
        factIDs: facts.map(\.id),
        seeds: seeds,
        validFactIDs: Set(facts.map(\.id))
      )
    else { throw ObservationError.invalidSnapshot }
  }

  static func capture(
    seed: InterpretationSeed,
    facts: [ChartFact],
    chart: SavedChart,
    initialThought: String
  ) throws -> Self {
    let currentSeeds = InterpretationSeedBuilder().makeSeeds(from: facts)
    guard currentSeeds.contains(seed) else { throw ObservationError.invalidSnapshot }
    let factsByID = Dictionary(facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let snapshot = Self(
      selectedText: seed.meaning,
      initialThought: initialThought,
      source: .localInterpretation,
      locationID: "interpretation.\(seed.id)",
      contentVersion: "1",
      ruleSetID: chart.ruleSetID,
      ruleSetVersion: chart.ruleSetVersion,
      facts: seed.evidenceFactIDs.compactMap { factsByID[$0] },
      seeds: [seed]
    )
    try snapshot.validate()
    return snapshot
  }
}

@Model
final class SavedObservation {
  @Attribute(.unique) private(set) var id: UUID
  private(set) var chartID: UUID
  private(set) var snapshotData: Data
  private(set) var createdAt: Date
  private(set) var reviewDate: Date?
  // 只有同步／明確還原的版本資訊可變更，快照原文不可覆寫。
  var modifiedAt: Date
  var reminderIdentifier: String?

  var snapshot: ObservationSnapshot? {
    try? JSONDecoder().decode(ObservationSnapshot.self, from: snapshotData)
  }

  init(
    id: UUID = UUID(),
    chartID: UUID,
    snapshot: ObservationSnapshot,
    createdAt: Date = .now,
    reviewDate: Date? = nil,
    modifiedAt: Date? = nil
  ) throws {
    try snapshot.validate()
    self.id = id
    self.chartID = chartID
    self.snapshotData = try JSONEncoder().encode(snapshot)
    self.createdAt = createdAt
    self.reviewDate = reviewDate
    self.modifiedAt = modifiedAt ?? createdAt
  }
}

enum ObservationError: LocalizedError, Equatable {
  case unsupportedSchema(Int)
  case invalidSnapshot
  case invalidReview
  case missingParent
  case duplicateID
  case immutableConflict

  var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version): "不支援觀察資料版本 \(version)，未套用資料。"
    case .invalidSnapshot: "觀察快照或當時引用資料不完整，未套用資料。"
    case .invalidReview: "回顧內容或標記無法辨識，未套用資料。"
    case .missingParent: "觀察或回顧找不到所屬命盤與原始觀察。"
    case .duplicateID: "觀察資料包含重複識別碼，未套用資料。"
    case .immutableConflict: "相同識別碼的原始觀察或回顧內容不同，為保留原文而停止操作。"
    }
  }
}
