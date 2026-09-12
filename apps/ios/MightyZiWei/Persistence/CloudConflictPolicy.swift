import Foundation

enum CloudConflictWinner: Equatable, Sendable {
  case local
  case remote
}

struct CloudConflictResolver: Sendable {
  func isDeleted(contentUpdatedAt: Date, deletedAt: Date?) -> Bool {
    guard let deletedAt else { return false }
    return deletedAt >= contentUpdatedAt
  }

  func winner(localUpdatedAt: Date, remoteUpdatedAt: Date) -> CloudConflictWinner {
    remoteUpdatedAt > localUpdatedAt ? .remote : .local
  }
}

struct CloudLocalTombstonePlan: Equatable, Sendable {
  let chartIDs: Set<UUID>
  let insightIDs: Set<UUID>
}

struct CloudTombstoneUploadPolicy: Sendable {
  func shouldUpload(localDeletedAt: Date, remoteDeletedAt: Date?) -> Bool {
    guard let remoteDeletedAt else { return true }
    return localDeletedAt > remoteDeletedAt
  }
}

struct CloudBookmarkRevision: Equatable, Sendable {
  let id: UUID
  let chartID: UUID
  let locationID: String
  let updatedAt: Date
}

struct CloudBookmarkDeduplicationPlan: Equatable, Sendable {
  let duplicateIDs: Set<UUID>
}

struct CloudBookmarkDeduplicator: Sendable {
  func makePlan(
    localInsights: [SavedInsight],
    remoteInsights: [CloudInsightPayload]
  ) -> CloudBookmarkDeduplicationPlan {
    let localRevisions = localInsights.compactMap { insight -> CloudBookmarkRevision? in
      guard insight.kind == .bookmark else { return nil }
      return CloudBookmarkRevision(
        id: insight.id,
        chartID: insight.chartID,
        locationID: insight.locationID,
        updatedAt: insight.updatedAt
      )
    }
    let remoteRevisions = remoteInsights.compactMap { insight -> CloudBookmarkRevision? in
      guard insight.kind == SavedInsight.Kind.bookmark.rawValue else { return nil }
      return CloudBookmarkRevision(
        id: insight.id,
        chartID: insight.chartID,
        locationID: insight.locationID,
        updatedAt: insight.updatedAt
      )
    }
    return makePlan(revisions: localRevisions + remoteRevisions)
  }

  func makePlan(revisions: [CloudBookmarkRevision]) -> CloudBookmarkDeduplicationPlan {
    let groups = Dictionary(grouping: revisions) {
      CloudBookmarkLocation(chartID: $0.chartID, locationID: $0.locationID)
    }
    var duplicateIDs = Set<UUID>()
    for group in groups.values {
      let uniqueRevisions = Dictionary(grouping: group, by: \.id).values.compactMap {
        $0.max { first, second in first.updatedAt < second.updatedAt }
      }
      guard uniqueRevisions.count > 1 else { continue }
      let ordered = uniqueRevisions.sorted {
        if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
        return $0.id.uuidString < $1.id.uuidString
      }
      duplicateIDs.formUnion(ordered.dropFirst().map(\.id))
    }
    return CloudBookmarkDeduplicationPlan(duplicateIDs: duplicateIDs)
  }
}

private struct CloudBookmarkLocation: Hashable {
  let chartID: UUID
  let locationID: String
}

struct CloudLocalTombstonePlanner {
  func makePlan(
    charts: [SavedChart],
    insights: [SavedInsight],
    deletions: [CloudDeletion],
    remoteChartUpdatedAt: [UUID: Date] = [:],
    remoteInsightUpdatedAt: [UUID: Date] = [:]
  ) -> CloudLocalTombstonePlan {
    var latestDeletionDates: [CloudEntityKey: Date] = [:]
    for deletion in deletions {
      let key = CloudEntityKey(type: deletion.entityType, id: deletion.entityID)
      latestDeletionDates[key] = max(
        latestDeletionDates[key] ?? .distantPast,
        deletion.deletedAt
      )
    }
    let resolver = CloudConflictResolver()
    let chartIDs: Set<UUID> = Set(
      charts.compactMap { chart -> UUID? in
        let deletedAt = latestDeletionDates[
          CloudEntityKey(type: RecordType.chart, id: chart.id)
        ]
        guard let deletedAt,
          resolver.isDeleted(
            contentUpdatedAt: chart.updatedAt,
            deletedAt: deletedAt
          ),
          remoteChartUpdatedAt[chart.id].map({ $0 <= deletedAt }) ?? true
        else {
          return nil
        }
        return chart.id
      })
    let insightIDs: Set<UUID> = Set(
      insights.compactMap { insight -> UUID? in
        if chartIDs.contains(insight.chartID) { return insight.id }
        let deletedAt = latestDeletionDates[
          CloudEntityKey(type: RecordType.insight, id: insight.id)
        ]
        guard let deletedAt,
          resolver.isDeleted(
            contentUpdatedAt: insight.updatedAt,
            deletedAt: deletedAt
          ),
          remoteInsightUpdatedAt[insight.id].map({ $0 <= deletedAt }) ?? true
        else {
          return nil
        }
        return insight.id
      })
    return CloudLocalTombstonePlan(chartIDs: chartIDs, insightIDs: insightIDs)
  }
}
