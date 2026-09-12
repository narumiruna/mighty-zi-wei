import CloudKit
import Foundation

/// 先驗證舊 record types，保留舊 App 可讀取的 payload 與刪除種類。
struct CloudLegacySnapshot {
  let deletions: [CloudDeletionPayload]
  let charts: [CloudChartPayload]
  let insights: [CloudInsightPayload]
  let chartRecordsByID: [UUID: CKRecord]
  let insightRecordsByID: [UUID: CKRecord]
  let deletionRecordsByKey: [CloudEntityKey: CKRecord]
  let deletionsByKey: [CloudEntityKey: CloudDeletionPayload]

  init(deletionRecords: [CKRecord], chartRecords: [CKRecord], insightRecords: [CKRecord]) throws {
    deletions = deletionRecords.compactMap(CloudDeletionPayload.init(record:))
    charts = chartRecords.compactMap(CloudChartPayload.init(record:))
    insights = insightRecords.compactMap(CloudInsightPayload.init(record:))
    guard deletions.count == deletionRecords.count,
      charts.count == chartRecords.count, insights.count == insightRecords.count,
      Set(charts.map(\.id)).count == charts.count,
      Set(insights.map(\.id)).count == insights.count,
      Set(deletions.map { CloudEntityKey(type: $0.entityType, id: $0.entityID) }).count
        == deletions.count,
      deletions.allSatisfy(\.isValid)
    else { throw ICloudSyncService.SyncError.invalidRemoteData }
    for chart in charts { try chart.validate() }
    chartRecordsByID = Dictionary(
      uniqueKeysWithValues: zip(charts, chartRecords).map { ($0.id, $1) })
    insightRecordsByID = Dictionary(
      uniqueKeysWithValues: zip(insights, insightRecords).map { ($0.id, $1) })
    deletionRecordsByKey = Dictionary(
      uniqueKeysWithValues: zip(deletions, deletionRecords).map {
        (CloudEntityKey(type: $0.entityType, id: $0.entityID), $1)
      })
    deletionsByKey = Dictionary(
      uniqueKeysWithValues: deletions.map {
        (CloudEntityKey(type: $0.entityType, id: $0.entityID), $0)
      })
  }
}
