import Foundation
import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
enum ObservationTestSupport {
  enum Failure: Error { case simulated }

  static func container() throws -> ModelContainer {
    let schema = AppModelContainerLoader.makeSchema()
    return try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ]
    )
  }

  static func chart() throws -> SavedChart {
    let profile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30), timeZoneIdentifier: "Asia/Taipei"
    )
    return try SavedChart.make(
      name: "合成測試命盤", profile: profile, chart: ZiWeiCalculator().calculate(profile))
  }

  static func snapshot(
    chart: SavedChart, thought: String = "原始想法不可覆寫"
  ) throws -> ObservationSnapshot {
    let facts = ChartFactBuilder().makeFacts(from: try chart.resolvedChart())
    let seed = try XCTUnwrap(InterpretationSeedBuilder().makeSeeds(from: facts).first)
    return try ObservationSnapshot.capture(
      seed: seed, facts: facts, chart: chart, initialThought: thought)
  }

  static func observation(
    chart: SavedChart, id: UUID = UUID(), thought: String = "原始想法不可覆寫"
  ) throws -> SavedObservation {
    try SavedObservation(
      id: id, chartID: chart.id, snapshot: snapshot(chart: chart, thought: thought))
  }

  static func review(
    observation: SavedObservation, id: UUID = UUID(), content: String = "這次有不同的觀察"
  ) -> SavedObservationReview {
    SavedObservationReview(
      id: id, observationID: observation.id, chartID: observation.chartID, content: content,
      outcome: .differs)
  }

  static func payload(
    chart: SavedChart, observations: [SavedObservation], reviews: [SavedObservationReview] = []
  ) throws -> BackupPayload {
    try BackupPayload(
      charts: [BackupChartDTO(savedChart: chart)], insights: [],
      observations: observations.map(ObservationPayload.init),
      reviews: reviews.map(ObservationReviewPayload.init)
    )
  }

  static func changing<Value: Codable>(
    _ value: Value, key: String, to replacement: Any?
  ) throws -> Value {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    object[key] = replacement
    return try JSONDecoder().decode(
      Value.self, from: JSONSerialization.data(withJSONObject: object))
  }
}

@MainActor
final class MockObservationRecordStore: CloudObservationRecordStoring {
  var state = CloudObservationState()
  var fetchCount = 0
  var writes = 0
  var failAfterWrites: Int?

  func fetch() async throws -> CloudObservationState {
    fetchCount += 1
    return state
  }

  func saveObservation(_ payload: ObservationPayload) async throws {
    try checkFailure()
    state.observations.removeAll { $0.id == payload.id }
    state.observations.append(payload)
  }

  func saveReview(_ payload: ObservationReviewPayload) async throws {
    try checkFailure()
    state.reviews.removeAll { $0.id == payload.id }
    state.reviews.append(payload)
  }

  func saveDeletion(_ payload: CloudObservationDeletion) async throws {
    try checkFailure()
    state.deletions.removeAll {
      $0.entityID == payload.entityID && $0.entityType == payload.entityType
    }
    state.deletions.append(payload)
  }

  func deleteRecord(type: String, id: UUID) async throws {
    try checkFailure()
    if type == RecordType.observation { state.observations.removeAll { $0.id == id } }
    if type == RecordType.review { state.reviews.removeAll { $0.id == id } }
  }

  private func checkFailure() throws {
    if let failAfterWrites, writes >= failAfterWrites {
      throw ObservationTestSupport.Failure.simulated
    }
    writes += 1
  }
}
