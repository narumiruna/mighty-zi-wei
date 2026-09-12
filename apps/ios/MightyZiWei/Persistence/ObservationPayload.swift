import Foundation

/// 備份與獨立 CloudKit record 共用的版本化格式，不含通知識別碼或完整對話。
struct ObservationPayload: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let id: UUID
  let chartID: UUID
  let snapshot: ObservationSnapshot
  let createdAt: Date
  let reviewDate: Date?
  var modifiedAt: Date

  init(_ model: SavedObservation) throws {
    guard let snapshot = model.snapshot else { throw ObservationError.invalidSnapshot }
    schemaVersion = 1
    id = model.id
    chartID = model.chartID
    self.snapshot = snapshot
    createdAt = model.createdAt
    reviewDate = model.reviewDate
    modifiedAt = model.modifiedAt
    try validate()
  }

  func validate() throws {
    guard schemaVersion == 1 else { throw ObservationError.unsupportedSchema(schemaVersion) }
    try snapshot.validate()
    guard modifiedAt >= createdAt else { throw ObservationError.invalidSnapshot }
  }

  func hasSameContent(as other: Self) -> Bool {
    id == other.id && chartID == other.chartID && snapshot == other.snapshot
      && createdAt == other.createdAt && reviewDate == other.reviewDate
  }

  func makeModel() throws -> SavedObservation {
    try validate()
    return try SavedObservation(
      id: id, chartID: chartID, snapshot: snapshot, createdAt: createdAt,
      reviewDate: reviewDate, modifiedAt: modifiedAt
    )
  }
}

struct ObservationReviewPayload: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let id: UUID
  let observationID: UUID
  let chartID: UUID
  let content: String
  let outcome: SavedObservationReview.Outcome
  let createdAt: Date
  var modifiedAt: Date

  init(_ model: SavedObservationReview) throws {
    guard let outcome = model.outcome else { throw ObservationError.invalidReview }
    schemaVersion = 1
    id = model.id
    observationID = model.observationID
    chartID = model.chartID
    content = model.content
    self.outcome = outcome
    createdAt = model.createdAt
    modifiedAt = model.modifiedAt
    try validate()
  }

  func validate() throws {
    guard schemaVersion == 1 else { throw ObservationError.unsupportedSchema(schemaVersion) }
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      modifiedAt >= createdAt
    else { throw ObservationError.invalidReview }
  }

  func hasSameContent(as other: Self) -> Bool {
    id == other.id && observationID == other.observationID && chartID == other.chartID
      && content == other.content && outcome == other.outcome && createdAt == other.createdAt
  }

  func makeModel() throws -> SavedObservationReview {
    try validate()
    return SavedObservationReview(
      id: id, observationID: observationID, chartID: chartID,
      content: content, outcome: outcome, createdAt: createdAt, modifiedAt: modifiedAt
    )
  }
}

struct ObservationParentChartEvidence: Sendable {
  let ruleSetID: String
  let ruleSetVersion: Int
  let factsByID: [String: ChartFact]

  init(ruleSetID: String, ruleSetVersion: Int, facts: [ChartFact]) {
    self.ruleSetID = ruleSetID
    self.ruleSetVersion = ruleSetVersion
    factsByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
  }

  func matches(_ snapshot: ObservationSnapshot) -> Bool {
    snapshot.ruleSetID == ruleSetID
      && snapshot.ruleSetVersion == ruleSetVersion
      && snapshot.facts.allSatisfy { factsByID[$0.id] == $0 }
  }
}

struct ObservationGraphValidator {
  func validate(
    observations: [ObservationPayload],
    reviews: [ObservationReviewPayload],
    parentCharts: [UUID: ObservationParentChartEvidence]
  ) throws {
    guard Set(observations.map(\.id)).count == observations.count,
      Set(reviews.map(\.id)).count == reviews.count
    else { throw ObservationError.duplicateID }
    let observationsByID = Dictionary(uniqueKeysWithValues: observations.map { ($0.id, $0) })
    for observation in observations {
      try observation.validate()
      guard let parentChart = parentCharts[observation.chartID] else {
        throw ObservationError.missingParent
      }
      guard parentChart.matches(observation.snapshot) else {
        throw ObservationError.invalidSnapshot
      }
    }
    for review in reviews {
      try review.validate()
      guard observationsByID[review.observationID]?.chartID == review.chartID else {
        throw ObservationError.missingParent
      }
    }
  }
}
