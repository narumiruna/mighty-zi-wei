import Foundation
import SwiftData

enum ObservationSyncConsent {
  static let enabledKey = "icloud.sync.observations.consent.v1"

  @MainActor
  static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: ICloudSyncService.enabledKey) && defaults.bool(forKey: enabledKey)
  }
}

@MainActor
struct CloudObservationSynchronizer {
  let store: any CloudObservationRecordStoring

  struct Result {
    let counts: ICloudSyncResult
    let reminderIdentifiersToCancel: [String]
  }

  /// 呼叫端負責與命盤及筆記共用 transaction，成功 save 後才取消提醒。
  func reconcile(
    consentGranted: Bool,
    charts: [SavedChart],
    deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> Result {
    guard consentGranted else {
      return Result(
        counts: ICloudSyncResult(uploadedCount: 0, downloadedCount: 0, conflictCount: 0),
        reminderIdentifiersToCancel: [])
    }
    let observations = try modelContext.fetch(FetchDescriptor<SavedObservation>())
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
    let local = try CloudObservationState(
      observations: observations.map(ObservationPayload.init),
      reviews: reviews.map(ObservationReviewPayload.init),
      deletions: latestObservationDeletions(deletions)
    )
    let remote = try await store.fetch()
    let parentCharts = try Dictionary(
      uniqueKeysWithValues: charts.map { chart in
        let facts = ChartFactBuilder().makeFacts(from: try chart.resolvedChart())
        return (
          chart.id,
          ObservationParentChartEvidence(
            ruleSetID: chart.ruleSetID,
            ruleSetVersion: chart.ruleSetVersion,
            facts: facts
          )
        )
      }
    )
    let chartDeletions = Dictionary(
      deletions.filter { $0.entityType == RecordType.chart }.map { ($0.entityID, $0.deletedAt) },
      uniquingKeysWith: max
    )
    let plan = try CloudObservationMergePlan(
      local: local,
      remote: remote,
      chartRevisions: Dictionary(uniqueKeysWithValues: charts.map { ($0.id, $0.updatedAt) }),
      chartDeletions: chartDeletions,
      parentCharts: parentCharts
    )
    // 所有遠端操作完成前，不改動任何本機觀察資料。
    let uploaded = try await upload(plan: plan, remote: remote)
    let reminders = try apply(
      plan: plan, observations: observations, reviews: reviews, deletions: deletions,
      modelContext: modelContext)
    let changes =
      Set(plan.observations.map(\.id)).symmetricDifference(Set(local.observations.map(\.id))).count
      + Set(plan.reviews.map(\.id)).symmetricDifference(Set(local.reviews.map(\.id))).count
    return Result(
      counts: ICloudSyncResult(uploadedCount: uploaded, downloadedCount: changes, conflictCount: 0),
      reminderIdentifiersToCancel: reminders
    )
  }

  private func latestObservationDeletions(
    _ deletions: [CloudDeletion]
  ) -> [CloudObservationDeletion] {
    let selected = deletions.filter {
      $0.entityType == RecordType.observation || $0.entityType == RecordType.review
    }
    let grouped = Dictionary(grouping: selected) {
      CloudEntityKey(type: $0.entityType, id: $0.entityID)
    }
    return grouped.compactMap { key, values in
      guard let date = values.map(\.deletedAt).max() else { return nil }
      return CloudObservationDeletion(entityID: key.id, entityType: key.type, deletedAt: date)
    }
  }

  private func upload(
    plan: CloudObservationMergePlan, remote: CloudObservationState
  ) async throws -> Int {
    var uploaded = 0
    let remoteObservations = Dictionary(
      uniqueKeysWithValues: remote.observations.map { ($0.id, $0) })
    let remoteReviews = Dictionary(uniqueKeysWithValues: remote.reviews.map { ($0.id, $0) })
    for deletion in plan.deletions where !remote.deletions.contains(deletion) {
      try await store.saveDeletion(deletion)
      uploaded += 1
    }
    for observation in plan.observations where remoteObservations[observation.id] != observation {
      try await store.saveObservation(observation)
      uploaded += 1
    }
    for review in plan.reviews where remoteReviews[review.id] != review {
      try await store.saveReview(review)
      uploaded += 1
    }
    let observationIDs = Set(plan.observations.map(\.id))
    let reviewIDs = Set(plan.reviews.map(\.id))
    for review in remote.reviews where !reviewIDs.contains(review.id) {
      try await store.deleteRecord(type: RecordType.review, id: review.id)
      uploaded += 1
    }
    for observation in remote.observations where !observationIDs.contains(observation.id) {
      try await store.deleteRecord(type: RecordType.observation, id: observation.id)
      uploaded += 1
    }
    return uploaded
  }

  private func apply(
    plan: CloudObservationMergePlan,
    observations: [SavedObservation], reviews: [SavedObservationReview],
    deletions: [CloudDeletion], modelContext: ModelContext
  ) throws -> [String] {
    let observationsByID = Dictionary(uniqueKeysWithValues: observations.map { ($0.id, $0) })
    let reviewsByID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
    let observationIDs = Set(plan.observations.map(\.id))
    let reviewIDs = Set(plan.reviews.map(\.id))
    var reminders: [String] = []
    for review in reviews where !reviewIDs.contains(review.id) { modelContext.delete(review) }
    for observation in observations where !observationIDs.contains(observation.id) {
      if let identifier = observation.reminderIdentifier { reminders.append(identifier) }
      modelContext.delete(observation)
    }
    for incoming in plan.observations {
      if let existing = observationsByID[incoming.id] {
        existing.modifiedAt = incoming.modifiedAt
      } else {
        modelContext.insert(try incoming.makeModel())
      }
    }
    for incoming in plan.reviews {
      if let existing = reviewsByID[incoming.id] {
        existing.modifiedAt = incoming.modifiedAt
      } else {
        modelContext.insert(try incoming.makeModel())
      }
    }
    for incoming in plan.deletions {
      if let existing = deletions.first(where: {
        $0.entityType == incoming.entityType && $0.entityID == incoming.entityID
      }) {
        existing.deletedAt = max(existing.deletedAt, incoming.deletedAt)
      } else {
        modelContext.insert(
          CloudDeletion(
            entityID: incoming.entityID, entityType: incoming.entityType,
            deletedAt: incoming.deletedAt))
      }
    }
    return reminders
  }
}
