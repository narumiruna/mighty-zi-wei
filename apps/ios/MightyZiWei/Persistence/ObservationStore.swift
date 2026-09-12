import Foundation
import SwiftData

@MainActor
enum ObservationStore {
  struct SaveResult {
    let observation: SavedObservation
    let reminderWarning: String?
  }

  static func saveObservation(
    chartID: UUID,
    snapshot: ObservationSnapshot,
    reviewDate: Date?,
    modelContext: ModelContext,
    schedule: (UUID, Date) async throws -> String = {
      try await ReviewReminderScheduler().scheduleObservation(observationID: $0, date: $1)
    },
    cancel: (String?) -> Void = { ReviewReminderScheduler().cancel(identifier: $0) },
    save: (ModelContext) throws -> Void = { try $0.save() }
  ) async throws -> SaveResult {
    let observation = try SavedObservation(
      chartID: chartID, snapshot: snapshot, reviewDate: reviewDate
    )
    var warning: String?
    if let reviewDate {
      do {
        observation.reminderIdentifier = try await schedule(observation.id, reviewDate)
      } catch {
        warning = "觀察已儲存，但提醒未設定。你仍可隨時開啟觀察新增回顧。"
      }
    }
    let scheduledIdentifier = observation.reminderIdentifier
    do {
      // 通知授權等待期間父命盤可能已由同步刪除。
      guard
        try modelContext.fetch(FetchDescriptor<SavedChart>()).contains(where: { $0.id == chartID })
      else {
        throw ObservationError.missingParent
      }
      modelContext.insert(observation)
      try save(modelContext)
      return SaveResult(observation: observation, reminderWarning: warning)
    } catch {
      modelContext.rollback()
      cancel(scheduledIdentifier)
      throw error
    }
  }

  static func addReview(
    observation: SavedObservation,
    content: String,
    outcome: SavedObservationReview.Outcome,
    modelContext: ModelContext
  ) throws {
    let parentID = observation.id
    let chartID = observation.chartID
    guard
      try modelContext.fetch(FetchDescriptor<SavedObservation>()).contains(where: {
        $0.id == parentID
      }),
      try modelContext.fetch(FetchDescriptor<SavedChart>()).contains(where: { $0.id == chartID })
    else { throw ObservationError.missingParent }
    let review = SavedObservationReview(
      observationID: parentID, chartID: chartID,
      content: content.trimmingCharacters(in: .whitespacesAndNewlines), outcome: outcome
    )
    _ = try ObservationReviewPayload(review)
    do {
      modelContext.insert(review)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  /// 只暫存刪除；呼叫端成功 save 後才取消提醒與清除導覽。
  static func removeChartChildren(
    chartID: UUID, modelContext: ModelContext, recordsTombstones: Bool = true
  ) throws -> [String] {
    let observations = try modelContext.fetch(FetchDescriptor<SavedObservation>())
      .filter { $0.chartID == chartID }
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
      .filter { $0.chartID == chartID }
    for review in reviews {
      removeReview(review, modelContext: modelContext, recordsTombstones: recordsTombstones)
    }
    for observation in observations {
      if recordsTombstones {
        ICloudSyncService.recordDeletion(
          entityID: observation.id, entityType: "SavedObservation", modelContext: modelContext
        )
      }
      modelContext.delete(observation)
    }
    return observations.compactMap(\.reminderIdentifier)
  }

  static func removeObservation(
    _ observation: SavedObservation, modelContext: ModelContext,
    recordsTombstones: Bool = true
  ) throws -> String? {
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
      .filter { $0.observationID == observation.id }
    for review in reviews {
      removeReview(review, modelContext: modelContext, recordsTombstones: recordsTombstones)
    }
    if recordsTombstones {
      ICloudSyncService.recordDeletion(
        entityID: observation.id, entityType: "SavedObservation", modelContext: modelContext
      )
    }
    let reminder = observation.reminderIdentifier
    modelContext.delete(observation)
    return reminder
  }

  static func removeAll(modelContext: ModelContext) throws -> [String] {
    let observations = try modelContext.fetch(FetchDescriptor<SavedObservation>())
    let reviews = try modelContext.fetch(FetchDescriptor<SavedObservationReview>())
    for review in reviews { removeReview(review, modelContext: modelContext) }
    for observation in observations {
      ICloudSyncService.recordDeletion(
        entityID: observation.id, entityType: "SavedObservation", modelContext: modelContext
      )
      modelContext.delete(observation)
    }
    return observations.compactMap(\.reminderIdentifier)
  }

  static func removeReview(
    _ review: SavedObservationReview, modelContext: ModelContext,
    recordsTombstones: Bool = true
  ) {
    if recordsTombstones {
      ICloudSyncService.recordDeletion(
        entityID: review.id, entityType: "SavedObservationReview", modelContext: modelContext
      )
    }
    modelContext.delete(review)
  }
}
