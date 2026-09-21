import CloudKit
import XCTest

@testable import MightyZiWei

@MainActor
final class CloudObservationRecordStoreTests: XCTestCase {
  func test解碼所有種類且寫入沿用FetchedRecord並在重新Fetch時清空快取() async throws {
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let payload = try ObservationPayload(observation)
    let review = try ObservationReviewPayload(
      ObservationTestSupport.review(observation: observation))
    let deletion = CloudObservationDeletion(
      entityID: UUID(), entityType: RecordType.observation, deletedAt: .now)
    let observationRecord = try record(
      payload, type: RecordType.observation,
      name: CloudObservationRecordStore.recordName(type: RecordType.observation, id: payload.id))
    let reviewRecord = try record(review, type: RecordType.review, name: "回顧")
    let deletionRecord = try record(deletion, type: RecordType.observationDeletion, name: "刪除")
    var types: [String] = []
    let fetchState = RecordFetchState()
    var savedRecords: [CKRecord] = []
    let store = CloudObservationRecordStore(
      fetchRecords: { type, visit in
        types.append(type)
        guard fetchState.returnsRecords else { return }
        let records = [
          RecordType.observation: observationRecord,
          RecordType.review: reviewRecord,
          RecordType.observationDeletion: deletionRecord,
        ]
        try visit(XCTUnwrap(records[type]))
      },
      saveRecord: { record in
        savedRecords.append(record)
        return record
      }, removeRecord: { _ in XCTFail("此流程不應刪除紀錄。") })
    let state = try await store.fetch()
    XCTAssertEqual(
      types, [RecordType.observation, RecordType.review, RecordType.observationDeletion])
    XCTAssertEqual(state.observations, [payload])
    XCTAssertEqual(state.reviews, [review])
    XCTAssertEqual(state.deletions, [deletion])
    try await store.saveObservation(payload)
    try await store.saveObservation(payload)
    XCTAssertTrue(savedRecords[0] === observationRecord)
    XCTAssertTrue(savedRecords[1] === savedRecords[0])
    fetchState.returnsRecords = false
    _ = try await store.fetch()
    try await store.saveObservation(payload)
    XCTAssertFalse(savedRecords[2] === observationRecord)
    XCTAssertEqual(savedRecords[2].recordID, observationRecord.recordID)
  }

  func test缺少Payload與無效JSON立即拒絕且不讀後續種類() async throws {
    for data in [nil, Data("不是 JSON".utf8)] {
      var types: [String] = []
      let store = CloudObservationRecordStore(
        fetchRecords: { type, visit in
          types.append(type)
          let record = CKRecord(recordType: type)
          record["payload"] = data
          try visit(record)
        },
        saveRecord: { record in
          XCTFail("驗證失敗不應寫入遠端。")
          return record
        }, removeRecord: { _ in XCTFail("此流程不應刪除紀錄。") })
      do {
        _ = try await store.fetch()
        XCTFail("無效 payload 不得略過。")
      } catch {
        if data == nil {
          XCTAssertEqual(error as? ICloudSyncService.SyncError, .invalidRemoteData)
        } else {
          XCTAssertTrue(error is DecodingError)
        }
      }
      XCTAssertEqual(types, [RecordType.observation])
    }
  }

  @MainActor
  private final class RecordFetchState {
    var returnsRecords = true
  }

  private func record(_ payload: some Encodable, type: String, name: String) throws -> CKRecord {
    let record = CKRecord(recordType: type, recordID: .init(recordName: name))
    record["payload"] = try JSONEncoder().encode(payload)
    return record
  }
}
