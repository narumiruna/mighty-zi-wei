import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class ObservationSyncTests: XCTestCase {
  func test未另行同意不查詢或寫入任何新RecordType() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    context.insert(chart)
    context.insert(try ObservationTestSupport.observation(chart: chart))
    try context.save()
    let remote = MockObservationRecordStore()
    let result = try await CloudObservationSynchronizer(store: remote).reconcile(
      consentGranted: false, charts: [chart], deletions: [], modelContext: context
    )
    XCTAssertEqual(remote.fetchCount, 0)
    XCTAssertEqual(remote.writes, 0)
    XCTAssertEqual(result.counts.uploadedCount, 0)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservation>()).count, 1)
    let suite = "ObservationConsentTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: ICloudSyncService.enabledKey)
    XCTAssertFalse(ObservationSyncConsent.isEnabled(defaults: defaults))
    defaults.set(true, forKey: ObservationSyncConsent.enabledKey)
    XCTAssertTrue(ObservationSyncConsent.isEnabled(defaults: defaults))
    defaults.set(false, forKey: ICloudSyncService.enabledKey)
    XCTAssertFalse(ObservationSyncConsent.isEnabled(defaults: defaults))
  }

  func test部分遠端失敗保留本機而固定ID重試不重複() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let review = ObservationTestSupport.review(observation: observation)
    context.insert(chart)
    context.insert(observation)
    context.insert(review)
    try context.save()
    let remote = MockObservationRecordStore()
    remote.failAfterWrites = 1
    let synchronizer = CloudObservationSynchronizer(store: remote)
    do {
      _ = try await CloudSyncMutationTransaction.run(modelContext: context) {
        try await synchronizer.reconcile(
          consentGranted: true, charts: [chart], deletions: [], modelContext: context)
      }
      XCTFail("應回報部分遠端失敗")
    } catch {
      XCTAssertEqual(remote.state.observations.count, 1)
      XCTAssertTrue(remote.state.reviews.isEmpty)
      XCTAssertEqual(
        try context.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [observation.id])
      XCTAssertEqual(
        try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.id), [review.id])
    }
    remote.failAfterWrites = nil
    for _ in 0..<2 {
      _ = try await synchronizer.reconcile(
        consentGranted: true, charts: [chart], deletions: [], modelContext: context)
      try context.save()
    }
    XCTAssertEqual(remote.state.observations.count, 1)
    XCTAssertEqual(remote.state.reviews.count, 1)
  }

  func test舊裝置父命盤Tombstone清除本機與遠端子資料() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "有效觀察提醒"
    let review = ObservationTestSupport.review(observation: observation)
    context.insert(chart)
    context.insert(observation)
    context.insert(review)
    try context.save()
    let remote = MockObservationRecordStore()
    remote.state = try CloudObservationState(
      observations: [ObservationPayload(observation)], reviews: [ObservationReviewPayload(review)])
    let deletion = CloudDeletion(
      entityID: chart.id, entityType: "SavedChart", deletedAt: .now.addingTimeInterval(1))
    context.insert(deletion)
    context.delete(chart)
    let result = try await CloudObservationSynchronizer(store: remote).reconcile(
      consentGranted: true, charts: [], deletions: [deletion], modelContext: context
    )
    try context.save()
    XCTAssertEqual(result.reminderIdentifiersToCancel, ["有效觀察提醒"])
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservation>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservationReview>()).isEmpty)
    XCTAssertTrue(remote.state.observations.isEmpty)
    XCTAssertTrue(remote.state.reviews.isEmpty)
    XCTAssertEqual(
      Set(remote.state.deletions.map(\.entityType)), ["SavedObservation", "SavedObservationReview"])
  }

  func test不同裝置回顧並存而舊筆記修改不更動快照() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let localReview = ObservationTestSupport.review(observation: observation, content: "裝置一")
    let remoteReview = ObservationTestSupport.review(observation: observation, content: "裝置二")
    let note = SavedInsight(
      chartID: chart.id, kind: .note, locationID: "chart.general", title: "舊筆記", content: "修改前")
    context.insert(chart)
    context.insert(observation)
    context.insert(localReview)
    context.insert(note)
    try context.save()
    let original = observation.snapshotData
    note.updateNote(title: "舊裝置修改", content: "修改後", marker: .observe)
    try context.save()
    let remote = MockObservationRecordStore()
    remote.state = try CloudObservationState(
      observations: [ObservationPayload(observation)],
      reviews: [ObservationReviewPayload(remoteReview)])
    _ = try await CloudObservationSynchronizer(store: remote).reconcile(
      consentGranted: true, charts: [chart], deletions: [], modelContext: context)
    try context.save()
    XCTAssertEqual(
      Set(try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.content)),
      ["裝置一", "裝置二"])
    XCTAssertEqual(observation.snapshotData, original)
    XCTAssertEqual(remote.state.reviews.count, 2)
  }

  func test未知Schema或不可變原文衝突不做遠端寫入() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    context.insert(chart)
    context.insert(observation)
    try context.save()
    let payload = try ObservationPayload(observation)
    let remote = MockObservationRecordStore()
    remote.state.observations = [
      try ObservationTestSupport.changing(payload, key: "schemaVersion", to: 999)
    ]
    do {
      _ = try await CloudObservationSynchronizer(store: remote).reconcile(
        consentGranted: true, charts: [chart], deletions: [], modelContext: context)
      XCTFail("應拒絕未知 schema")
    } catch { XCTAssertEqual(error as? ObservationError, .unsupportedSchema(999)) }
    let differentSnapshot = try ObservationTestSupport.snapshot(chart: chart, thought: "不同原文")
    let different = try SavedObservation(
      id: observation.id, chartID: chart.id, snapshot: differentSnapshot,
      createdAt: observation.createdAt)
    remote.state.observations = [try ObservationPayload(different)]
    do {
      _ = try await CloudObservationSynchronizer(store: remote).reconcile(
        consentGranted: true, charts: [chart], deletions: [], modelContext: context)
      XCTFail("應拒絕不可變原文衝突")
    } catch { XCTAssertEqual(error as? ObservationError, .immutableConflict) }
    XCTAssertEqual(remote.writes, 0)
    XCTAssertEqual(observation.snapshot?.initialThought, "原始想法不可覆寫")
  }

  func test刪除觀察會阻止其他裝置新增回顧復活() throws {
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let review = ObservationTestSupport.review(observation: observation)
    let deletion = CloudObservationDeletion(
      entityID: observation.id, entityType: RecordType.observation,
      deletedAt: observation.modifiedAt.addingTimeInterval(1))
    let plan = try CloudObservationMergePlan(
      local: CloudObservationState(deletions: [deletion]),
      remote: CloudObservationState(
        observations: [ObservationPayload(observation)], reviews: [ObservationReviewPayload(review)]
      ),
      chartRevisions: [chart.id: chart.updatedAt], chartDeletions: [:]
    )
    XCTAssertTrue(plan.observations.isEmpty)
    XCTAssertTrue(plan.reviews.isEmpty)
    XCTAssertTrue(plan.deletions.contains { $0.entityID == review.id })
    XCTAssertNotEqual(RecordType.observationDeletion, RecordType.deletion)
  }
}
