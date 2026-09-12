import Foundation
import SwiftData

struct BackupRestoreResult: Equatable, Sendable {
  let chartCount: Int
  let insightCount: Int
  var observationCount: Int = 0
  var reviewCount: Int = 0
}

@MainActor
enum BackupRestoreService {
  static func restore(
    _ payload: ValidatedBackupPayload,
    existingCharts: [SavedChart],
    existingInsights: [SavedInsight],
    modelContext: ModelContext,
    restoredAt: Date = .now,
    shortcutDefaults: UserDefaults? = UserDefaults(
      suiteName: ReviewReminderScheduler.sharedDefaultsSuite
    ),
    cancelReminder: (String?) -> Void = {
      ReviewReminderScheduler().cancel(identifier: $0)
    },
    save: (ModelContext) throws -> Void = { try $0.save() }
  ) throws -> BackupRestoreResult {
    let observationPlan = try ObservationRestorePlan(payload: payload, modelContext: modelContext)
    let validatedCharts = try payload.makeSavedCharts()
    let validatedChartsByID = Dictionary(
      uniqueKeysWithValues: validatedCharts.map { ($0.id, $0) }
    )

    let chartIDs = Set(payload.charts.map(\.id))
    let restoredInsightIDs = Set(payload.insights.map(\.id))
    let restoredKeys = Set(
      chartIDs.map { RestoredEntityKey(entityID: $0, entityType: "SavedChart") }
        + restoredInsightIDs.map {
          RestoredEntityKey(entityID: $0, entityType: "SavedInsight")
        }
        + payload.observations.map {
          RestoredEntityKey(entityID: $0.id, entityType: "SavedObservation")
        }
        + payload.reviews.map {
          RestoredEntityKey(entityID: $0.id, entityType: "SavedObservationReview")
        }
    )
    let matchingDeletions = try modelContext.fetch(FetchDescriptor<CloudDeletion>())
      .filter {
        restoredKeys.contains(
          RestoredEntityKey(entityID: $0.entityID, entityType: $0.entityType)
        )
      }
    let restorationRevision = matchingDeletions.reduce(restoredAt) { revision, deletion in
      deletion.deletedAt >= revision
        ? deletion.deletedAt.addingTimeInterval(0.001)
        : revision
    }
    var chartsByID = Dictionary(uniqueKeysWithValues: existingCharts.map { ($0.id, $0) })
    var insightsByID = Dictionary(uniqueKeysWithValues: existingInsights.map { ($0.id, $0) })
    var reminderIdentifiersToCancel: [String] = []

    do {
      for insight in existingInsights
      where
        chartIDs.contains(insight.chartID) && !restoredInsightIDs.contains(insight.id)
      {
        ICloudSyncService.recordDeletion(
          entityID: insight.id,
          entityType: "SavedInsight",
          modelContext: modelContext
        )
        if let identifier = insight.reminderIdentifier {
          reminderIdentifiersToCancel.append(identifier)
        }
        modelContext.delete(insight)
        insightsByID.removeValue(forKey: insight.id)
      }

      for chartDTO in payload.charts {
        let chart: SavedChart
        if let existing = chartsByID[chartDTO.id] {
          try chartDTO.apply(to: existing)
          chart = existing
        } else {
          chart = validatedChartsByID[chartDTO.id]!
          modelContext.insert(chart)
          chartsByID[chart.id] = chart
        }
        chart.updatedAt = restorationRevision
      }

      for insightDTO in payload.insights {
        let restoredInsight: SavedInsight
        if let existing = insightsByID[insightDTO.id] {
          if let identifier = existing.reminderIdentifier {
            reminderIdentifiersToCancel.append(identifier)
          }
          insightDTO.apply(to: existing)
          restoredInsight = existing
        } else {
          restoredInsight = insightDTO.makeSavedInsight()
          modelContext.insert(restoredInsight)
          insightsByID[restoredInsight.id] = restoredInsight
        }
        restoredInsight.updatedAt = restorationRevision
      }

      matchingDeletions.forEach(modelContext.delete)
      observationPlan.apply(modelContext: modelContext, revision: restorationRevision)
      try save(modelContext)
    } catch {
      modelContext.rollback()
      throw error
    }

    for identifier in reminderIdentifiersToCancel { cancelReminder(identifier) }
    PinnedChartShortcut.reconcile(
      charts: Array(chartsByID.values),
      defaults: shortcutDefaults
    )

    return BackupRestoreResult(
      chartCount: payload.charts.count,
      insightCount: payload.insights.count,
      observationCount: payload.observations.count,
      reviewCount: payload.reviews.count
    )
  }
}

private struct RestoredEntityKey: Hashable {
  let entityID: UUID
  let entityType: String
}
