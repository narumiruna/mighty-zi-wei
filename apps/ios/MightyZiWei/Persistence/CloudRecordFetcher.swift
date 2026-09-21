import CloudKit

/// 逐筆傳遞成功結果，保留 record 錯誤與呼叫端解碼錯誤的先後順序。
@MainActor
enum CloudRecordFetcher {
  typealias Visitor = @MainActor (CKRecord) throws -> Void
  typealias Fetch = @MainActor (String, Visitor) async throws -> Void

  static func fetch(
    type: String, database: CKDatabase, visit: Visitor
  ) async throws {
    try await walkPages(
      page: { (cursor: CKQueryOperation.Cursor?) in
        if let cursor {
          return try await database.records(continuingMatchFrom: cursor)
        }
        return try await database.records(
          matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)))
      }, visit: visit)
  }

  static func walkPages<Cursor>(
    page:
      @MainActor (Cursor?) async throws -> ([(CKRecord.ID, Result<CKRecord, any Error>)], Cursor?),
    visit: Visitor
  ) async throws {
    var cursor: Cursor?
    repeat {
      let (matches, nextCursor) = try await page(cursor)
      for (_, result) in matches { try visit(result.get()) }
      cursor = nextCursor
    } while cursor != nil
  }
}
