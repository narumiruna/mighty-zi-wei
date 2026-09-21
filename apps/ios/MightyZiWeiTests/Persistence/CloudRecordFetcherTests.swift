import CloudKit
import XCTest

@testable import MightyZiWei

@MainActor
final class CloudRecordFetcherTests: XCTestCase {
  func test多頁含空頁依Cursor與Record順序讀取() async throws {
    let records = (0..<3).map {
      CKRecord(recordType: RecordType.chart, recordID: .init(recordName: "\($0)"))
    }
    var requested: [Int?] = []
    var received: [CKRecord.ID] = []
    try await CloudRecordFetcher.walkPages(
      page: { (cursor: Int?) in
        requested.append(cursor)
        switch cursor {
        case nil: return ([(records[0].recordID, .success(records[0]))], 1)
        case 1: return ([], 2)
        default: return (records.dropFirst().map { ($0.recordID, .success($0)) }, nil)
        }
      }, visit: { received.append($0.recordID) })
    XCTAssertEqual(requested, [nil, 1, 2])
    XCTAssertEqual(received, records.map(\.recordID))
  }

  func test單筆失敗不略過且不再要求下一頁() async throws {
    let first = CKRecord(recordType: RecordType.chart)
    var requests = 0
    var received = 0
    do {
      try await CloudRecordFetcher.walkPages(
        page: { (_: Int?) in
          requests += 1
          return (
            [(first.recordID, .success(first)), (CKRecord.ID(), .failure(FetchError.record))], 1
          )
        }, visit: { _ in received += 1 })
      XCTFail("單筆錯誤必須停止同步。")
    } catch { XCTAssertEqual(error as? FetchError, .record) }
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(received, 1)
  }

  func test呼叫端解碼失敗優先於同頁後續Record錯誤() async throws {
    let first = CKRecord(recordType: RecordType.chart)
    do {
      try await CloudRecordFetcher.walkPages(
        page: { (_: Int?) in
          ([(first.recordID, .success(first)), (CKRecord.ID(), .failure(FetchError.record))], nil)
        }, visit: { _ in throw FetchError.payload })
      XCTFail("必須保留先出現的解碼錯誤。")
    } catch { XCTAssertEqual(error as? FetchError, .payload) }
  }

  func test後續頁請求失敗或取消均向呼叫端傳遞() async throws {
    for error: any Error in [FetchError.page, CancellationError()] {
      var requests = 0
      do {
        try await CloudRecordFetcher.walkPages(
          page: { (cursor: Int?) in
            requests += 1
            if cursor != nil { throw error }
            return ([], 1)
          }, visit: { _ in XCTFail("空頁不應產生 record。") })
        XCTFail("頁面錯誤必須傳遞。")
      } catch {
        XCTAssertTrue(error is FetchError || error is CancellationError)
      }
      XCTAssertEqual(requests, 2)
    }
  }
}

private enum FetchError: Error { case record, payload, page }
