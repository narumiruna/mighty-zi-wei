import CloudKit
import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class CloudLegacySyncSessionTests: XCTestCase {
  func test同步驗證失敗回復已合併命盤刪除紀錄與子資料() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let chart = try ObservationTestSupport.chart()
    let deletedChart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: deletedChart)
    let review = ObservationTestSupport.review(observation: observation)
    chart.name = "同步前"
    context.insert(chart)
    context.insert(deletedChart)
    context.insert(observation)
    context.insert(review)
    try context.save()
    let incoming = try CloudChartPayload(chart).makeModel()
    incoming.name = "尚未完成的遠端內容"
    incoming.updatedAt = chart.updatedAt.addingTimeInterval(10)
    let invalid = SavedInsight(
      chartID: chart.id, kind: .note, locationID: "chart.general", title: "無效筆記",
      content: "內容", evidenceFactIDs: ["不存在的依據"])
    let deletion = CloudDeletion(
      entityID: deletedChart.id, entityType: RecordType.chart,
      deletedAt: deletedChart.updatedAt.addingTimeInterval(10))
    let remote = try CloudLegacySnapshot(
      deletionRecords: [CloudDeletionPayload(deletion).record()],
      chartRecords: [CloudChartPayload(incoming).record()],
      insightRecords: [CloudInsightPayload(invalid).record()])
    let session = CloudLegacySyncSession(
      database: {
        XCTFail("無效資料應在任何 CloudKit 存取前回復。")
        throw CocoaError(.featureUnsupported)
      },
      modelContext: context, remote: remote, charts: [chart, deletedChart],
      insights: [], deletions: [])
    do {
      _ = try await session.run()
      XCTFail("應在任何遠端寫入前拒絕無效依據。")
    } catch {
      XCTAssertEqual(error as? ICloudSyncService.SyncError, .invalidRemoteData)
    }
    let persisted = try ModelContext(container).fetch(FetchDescriptor<SavedChart>())
    XCTAssertEqual(persisted.first { $0.id == chart.id }?.name, "同步前")
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedChart>()), 2)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [observation.id])
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.id), [review.id])
    XCTAssertTrue(try context.fetch(FetchDescriptor<CloudDeletion>()).isEmpty)
    XCTAssertFalse(context.hasChanges)
  }
}
