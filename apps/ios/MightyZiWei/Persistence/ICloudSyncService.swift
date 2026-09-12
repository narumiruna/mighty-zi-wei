import CloudKit
import Foundation
import SwiftData

@MainActor
final class ICloudSyncService: ICloudSynchronizing {
  static let enabledKey = "icloud.sync.enabled"

  enum SyncError: LocalizedError, Equatable {
    case iCloudUnavailable
    case invalidRemoteData

    var errorDescription: String? {
      switch self {
      case .iCloudUnavailable:
        "目前無法使用私人 iCloud 資料庫。請確認已登入 iCloud 並允許此 App 使用 iCloud。"
      case .invalidRemoteData:
        "iCloud 中有無法驗證的同步資料，因此未套用該筆內容。"
      }
    }
  }

  private let providedContainer: CKContainer?
  private var container: CKContainer { providedContainer ?? .default() }
  private var database: CKDatabase { container.privateCloudDatabase }

  init(container: CKContainer? = nil) { providedContainer = container }

  func sync(
    charts: [SavedChart], insights: [SavedInsight], deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> ICloudSyncResult {
    guard try await container.accountStatus() == .available else {
      throw SyncError.iCloudUnavailable
    }
    let remote = try await CloudLegacySnapshot(
      deletionRecords: fetchRecords(type: RecordType.deletion),
      chartRecords: fetchRecords(type: RecordType.chart),
      insightRecords: fetchRecords(type: RecordType.insight)
    )
    return try await CloudLegacySyncSession(
      database: database, modelContext: modelContext, remote: remote,
      charts: charts, insights: insights, deletions: deletions
    ).run()
  }

  static func recordDeletion(entityID: UUID, entityType: String, modelContext: ModelContext) {
    modelContext.insert(CloudDeletion(entityID: entityID, entityType: entityType))
  }

  private func fetchRecords(type: String) async throws -> [CKRecord] {
    var records: [CKRecord] = []
    var cursor: CKQueryOperation.Cursor?
    repeat {
      let result: ([(CKRecord.ID, Result<CKRecord, any Error>)], CKQueryOperation.Cursor?)
      if let cursor {
        result = try await database.records(continuingMatchFrom: cursor)
      } else {
        result = try await database.records(
          matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)))
      }
      for (_, recordResult) in result.0 { records.append(try recordResult.get()) }
      cursor = result.1
    } while cursor != nil
    return records
  }
}
