import Foundation
import SwiftData

@Model
final class SavedObservationReview {
  enum Outcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case matches
    case differs
    case uncertain

    var id: String { rawValue }
    var title: String {
      switch self {
      case .matches: "符合"
      case .differs: "不符合"
      case .uncertain: "尚無法判斷"
      }
    }
  }

  @Attribute(.unique) private(set) var id: UUID
  private(set) var observationID: UUID
  private(set) var chartID: UUID
  private(set) var content: String
  private(set) var outcomeRawValue: String
  private(set) var createdAt: Date
  var modifiedAt: Date

  var outcome: Outcome? { Outcome(rawValue: outcomeRawValue) }

  init(
    id: UUID = UUID(),
    observationID: UUID,
    chartID: UUID,
    content: String,
    outcome: Outcome,
    createdAt: Date = .now,
    modifiedAt: Date? = nil
  ) {
    self.id = id
    self.observationID = observationID
    self.chartID = chartID
    self.content = content
    self.outcomeRawValue = outcome.rawValue
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt ?? createdAt
  }
}
