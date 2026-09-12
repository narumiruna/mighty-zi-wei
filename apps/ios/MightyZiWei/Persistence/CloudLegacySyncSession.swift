import CloudKit
import Foundation
import SwiftData

/// 一次同步的可回復本機變更；遠端部分寫入由固定 ID 安全重試。
@MainActor
final class CloudLegacySyncSession {
  private let database: CKDatabase
  private let modelContext: ModelContext
  private let remote: CloudLegacySnapshot
  private var chartsByID: [UUID: SavedChart]
  private var insightsByID: [UUID: SavedInsight]
  private var allDeletions: [CloudEntityKey: CloudDeletion] = [:]
  private var uploaded = 0
  private var downloaded = 0
  private var conflicts = 0
  private var deletedChartIDs = Set<UUID>()
  private var remindersToCancel = Set<String>()
  private var newlyScheduledReminders = Set<String>()
  private var insightIDsToReconcileReminders = Set<UUID>()

  init(
    database: CKDatabase, modelContext: ModelContext, remote: CloudLegacySnapshot,
    charts: [SavedChart], insights: [SavedInsight], deletions: [CloudDeletion]
  ) {
    self.database = database
    self.modelContext = modelContext
    self.remote = remote
    chartsByID = Dictionary(uniqueKeysWithValues: charts.map { ($0.id, $0) })
    insightsByID = Dictionary(uniqueKeysWithValues: insights.map { ($0.id, $0) })
    for deletion in deletions {
      let key = CloudEntityKey(type: deletion.entityType, id: deletion.entityID)
      if allDeletions[key]?.deletedAt ?? .distantPast < deletion.deletedAt {
        allDeletions[key] = deletion
      }
    }
  }

  func run() async throws -> ICloudSyncResult {
    do {
      mergeDeletions()
      try applyLocalTombstones()
      try await reconcileCharts()
      var insights = try validatedRemoteInsights()
      try await deduplicateBookmarks(remoteInsights: &insights)
      try await reconcileInsights(insights)
      try await uploadTombstones()
      try await reconcileObservations()
      try await reconcileReminders()
      try modelContext.save()
      for chartID in deletedChartIDs { ChartReadingGuideProgressStore.remove(chartID: chartID) }
      for identifier in remindersToCancel {
        ReviewReminderScheduler().cancel(identifier: identifier)
      }
      return ICloudSyncResult(
        uploadedCount: uploaded, downloadedCount: downloaded, conflictCount: conflicts)
    } catch {
      modelContext.rollback()
      for identifier in newlyScheduledReminders {
        ReviewReminderScheduler().cancel(identifier: identifier)
      }
      throw error
    }
  }

  private func mergeDeletions() {
    for payload in remote.deletions {
      let key = CloudEntityKey(type: payload.entityType, id: payload.entityID)
      if let existing = allDeletions[key] {
        if payload.deletedAt > existing.deletedAt {
          existing.deletedAt = payload.deletedAt
          downloaded += 1
        }
      } else {
        let deletion = payload.makeModel()
        modelContext.insert(deletion)
        allDeletions[key] = deletion
        downloaded += 1
      }
    }
  }

  private func applyLocalTombstones() throws {
    let plan = CloudLocalTombstonePlanner().makePlan(
      charts: Array(chartsByID.values), insights: Array(insightsByID.values),
      deletions: Array(allDeletions.values),
      remoteChartUpdatedAt: Dictionary(
        uniqueKeysWithValues: remote.charts.map { ($0.id, $0.updatedAt) }),
      remoteInsightUpdatedAt: Dictionary(
        uniqueKeysWithValues: remote.insights.map { ($0.id, $0.updatedAt) })
    )
    for insightID in plan.insightIDs {
      guard let insight = insightsByID.removeValue(forKey: insightID) else { continue }
      if let identifier = insight.reminderIdentifier { remindersToCancel.insert(identifier) }
      modelContext.delete(insight)
      downloaded += 1
    }
    for chartID in plan.chartIDs {
      guard let chart = chartsByID.removeValue(forKey: chartID) else { continue }
      remindersToCancel.formUnion(
        try ObservationStore.removeChartChildren(chartID: chartID, modelContext: modelContext))
      modelContext.delete(chart)
      deletedChartIDs.insert(chartID)
      downloaded += 1
    }
  }

  private func reconcileCharts() async throws {
    for incoming in remote.charts {
      let tombstone = allDeletions[CloudEntityKey(type: RecordType.chart, id: incoming.id)]
      if CloudConflictResolver().isDeleted(
        contentUpdatedAt: incoming.updatedAt, deletedAt: tombstone?.deletedAt),
        chartsByID[incoming.id] == nil
      {
        continue
      }
      if let local = chartsByID[incoming.id] {
        try await reconcileChart(incoming, local: local)
      } else {
        let local = try incoming.makeModel()
        modelContext.insert(local)
        chartsByID[local.id] = local
        downloaded += 1
      }
    }
    let remoteIDs = Set(remote.charts.map(\.id))
    for chart in chartsByID.values where !remoteIDs.contains(chart.id) {
      try await database.save(try CloudChartPayload(chart).record())
      uploaded += 1
    }
  }

  private func reconcileChart(_ incoming: CloudChartPayload, local: SavedChart) async throws {
    if CloudConflictResolver().winner(
      localUpdatedAt: local.updatedAt, remoteUpdatedAt: incoming.updatedAt) == .remote
    {
      try incoming.apply(to: local)
      for insight in insightsByID.values
      where insight.chartID == local.id && insight.reviewDate != nil {
        insightIDsToReconcileReminders.insert(insight.id)
      }
      downloaded += 1
      conflicts += 1
    } else if local.updatedAt > incoming.updatedAt {
      try await database.save(
        try CloudChartPayload(local).record(existing: remote.chartRecordsByID[incoming.id]))
      uploaded += 1
      conflicts += 1
    }
  }

  private func validatedRemoteInsights() throws -> [CloudInsightPayload] {
    let candidates = remote.insights.filter { incoming in
      guard chartsByID[incoming.chartID] != nil else { return false }
      let tombstone = allDeletions[CloudEntityKey(type: RecordType.insight, id: incoming.id)]
      return !CloudConflictResolver().isDeleted(
        contentUpdatedAt: incoming.updatedAt, deletedAt: tombstone?.deletedAt)
        || insightsByID[incoming.id] != nil
    }
    for incoming in candidates {
      guard incoming.isStructurallyValid, let chart = chartsByID[incoming.chartID] else {
        throw ICloudSyncService.SyncError.invalidRemoteData
      }
      let facts = ChartFactBuilder().makeFacts(from: try chart.resolvedChart())
      let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)
      guard incoming.hasValidEvidence(seeds: seeds, validFactIDs: Set(facts.map(\.id))) else {
        throw ICloudSyncService.SyncError.invalidRemoteData
      }
    }
    return candidates
  }

  private func deduplicateBookmarks(remoteInsights: inout [CloudInsightPayload]) async throws {
    let plan = CloudBookmarkDeduplicator().makePlan(
      localInsights: Array(insightsByID.values), remoteInsights: remoteInsights)
    conflicts += plan.duplicateIDs.count
    for duplicateID in plan.duplicateIDs {
      if let duplicate = insightsByID.removeValue(forKey: duplicateID) {
        if let identifier = duplicate.reminderIdentifier { remindersToCancel.insert(identifier) }
        modelContext.delete(duplicate)
        downloaded += 1
      }
      if remote.insightRecordsByID[duplicateID] != nil {
        try await deleteContentRecord(
          for: CloudEntityKey(type: RecordType.insight, id: duplicateID))
        uploaded += 1
      }
    }
    remoteInsights.removeAll { plan.duplicateIDs.contains($0.id) }
  }

  private func reconcileInsights(_ remoteInsights: [CloudInsightPayload]) async throws {
    for incoming in remoteInsights {
      if let local = insightsByID[incoming.id] {
        if CloudConflictResolver().winner(
          localUpdatedAt: local.updatedAt, remoteUpdatedAt: incoming.updatedAt) == .remote
        {
          incoming.apply(to: local)
          insightIDsToReconcileReminders.insert(local.id)
          downloaded += 1
          conflicts += 1
        } else if local.updatedAt > incoming.updatedAt {
          try await database.save(
            CloudInsightPayload(local).record(existing: remote.insightRecordsByID[incoming.id]))
          uploaded += 1
          conflicts += 1
        }
      } else {
        let local = incoming.makeModel()
        modelContext.insert(local)
        insightsByID[local.id] = local
        insightIDsToReconcileReminders.insert(local.id)
        downloaded += 1
      }
    }
    let remoteIDs = Set(remoteInsights.map(\.id))
    for insight in insightsByID.values
    where !remoteIDs.contains(insight.id) && chartsByID[insight.chartID] != nil {
      try await database.save(CloudInsightPayload(insight).record())
      uploaded += 1
    }
  }

  private func uploadTombstones() async throws {
    for (key, deletion) in allDeletions
    where key.type == RecordType.chart || key.type == RecordType.insight {
      if CloudTombstoneUploadPolicy().shouldUpload(
        localDeletedAt: deletion.deletedAt, remoteDeletedAt: remote.deletionsByKey[key]?.deletedAt)
      {
        try await database.save(
          CloudDeletionPayload(deletion).record(existing: remote.deletionRecordsByKey[key]))
        uploaded += 1
      }
      let contentUpdatedAt =
        key.type == RecordType.chart
        ? chartsByID[key.id]?.updatedAt : insightsByID[key.id]?.updatedAt
      let recordExists =
        key.type == RecordType.chart
        ? remote.chartRecordsByID[key.id] != nil : remote.insightRecordsByID[key.id] != nil
      if recordExists && (contentUpdatedAt.map { $0 <= deletion.deletedAt } ?? true) {
        try await deleteContentRecord(for: key)
      }
    }
  }

  private func reconcileObservations() async throws {
    let result = try await CloudObservationSynchronizer(
      store: CloudObservationRecordStore(database: database)
    ).reconcile(
      consentGranted: ObservationSyncConsent.isEnabled(), charts: Array(chartsByID.values),
      deletions: try modelContext.fetch(FetchDescriptor<CloudDeletion>()),
      modelContext: modelContext
    )
    uploaded += result.counts.uploadedCount
    downloaded += result.counts.downloadedCount
    conflicts += result.counts.conflictCount
    remindersToCancel.formUnion(result.reminderIdentifiersToCancel)
  }

  private func reconcileReminders() async throws {
    for insightID in insightIDsToReconcileReminders {
      guard let insight = insightsByID[insightID], let chartName = chartsByID[insight.chartID]?.name
      else { continue }
      let oldIdentifier = insight.reminderIdentifier
      let newIdentifier: String?
      if let reviewDate = insight.reviewDate {
        newIdentifier = try await ReviewReminderScheduler().scheduleSyncedReminder(
          insightID: insight.id, chartName: chartName, title: insight.title, date: reviewDate)
      } else {
        newIdentifier = nil
      }
      insight.reminderIdentifier = newIdentifier
      if let oldIdentifier, oldIdentifier != newIdentifier {
        remindersToCancel.insert(oldIdentifier)
      }
      if let newIdentifier, newIdentifier != oldIdentifier {
        newlyScheduledReminders.insert(newIdentifier)
      }
    }
  }

  private func deleteContentRecord(for key: CloudEntityKey) async throws {
    guard let reference = CloudContentRecordReference(entityType: key.type, entityID: key.id) else {
      throw ICloudSyncService.SyncError.invalidRemoteData
    }
    do {
      try await database.deleteRecord(withID: CKRecord.ID(recordName: reference.recordName))
    } catch let error as CKError where error.code == .unknownItem {
      // 已刪除的內容視為成功，保留 tombstone 供其他裝置同步。
    }
  }
}
