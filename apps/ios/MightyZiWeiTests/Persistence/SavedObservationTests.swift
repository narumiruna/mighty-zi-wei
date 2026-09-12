import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class SavedObservationTests: XCTestCase {
  func test快照保存單段原文版本及完整當時依據() throws {
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let snapshot = try XCTUnwrap(observation.snapshot)
    XCTAssertEqual(snapshot.contentVersion, "1")
    XCTAssertEqual(snapshot.seeds.count, 1)
    XCTAssertEqual(snapshot.selectedText, snapshot.seeds.first?.meaning)
    XCTAssertEqual(snapshot.facts.map(\.id), snapshot.seeds.first?.evidenceFactIDs)
    XCTAssertEqual(snapshot.ruleSetVersion, chart.ruleSetVersion)
    XCTAssertFalse(snapshot.versionDescription.contains("已審閱認證"))
    try snapshot.validate()
  }

  func test多次回顧有獨立ID且不覆寫原文或初步想法() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    context.insert(chart)
    context.insert(observation)
    try context.save()
    let original = observation.snapshotData
    try ObservationStore.addReview(
      observation: observation, content: "新的觀察", outcome: .matches, modelContext: context)
    try ObservationStore.addReview(
      observation: observation, content: "修正前次回顧", outcome: .uncertain, modelContext: context)
    let reviews = try context.fetch(FetchDescriptor<SavedObservationReview>())
    XCTAssertEqual(reviews.count, 2)
    XCTAssertEqual(Set(reviews.map(\.id)).count, 2)
    XCTAssertEqual(observation.snapshotData, original)
    XCTAssertEqual(observation.snapshot?.initialThought, "原始想法不可覆寫")
  }

  func test缺少內容版本保持Legacy而未知內容版本只供封存閱讀() throws {
    let original = try ObservationTestSupport.snapshot(chart: ObservationTestSupport.chart())
    let legacy = try ObservationTestSupport.changing(original, key: "contentVersion", to: nil)
    let future = try ObservationTestSupport.changing(original, key: "contentVersion", to: "未來內容")
    try legacy.validate()
    try future.validate()
    XCTAssertNil(legacy.contentVersion)
    XCTAssertEqual(legacy.versionDescription, "來源版本未保存")
    XCTAssertTrue(future.versionDescription.contains("僅供歷史回顧"))
  }

  func test本機基本解讀快照文字與位置必須對應唯一封存Seed() throws {
    let snapshot = try ObservationTestSupport.snapshot(chart: ObservationTestSupport.chart())
    let forgedText = try ObservationTestSupport.changing(
      snapshot,
      key: "selectedText",
      to: "與封存 seed meaning 不同的文字"
    )
    XCTAssertThrowsError(try forgedText.validate())
    let forgedLocation = try ObservationTestSupport.changing(
      snapshot,
      key: "locationID",
      to: "interpretation.other"
    )
    XCTAssertThrowsError(try forgedLocation.validate())
  }

  func test未知快照Schema或缺少引用安全拒絕() throws {
    let snapshot = try ObservationTestSupport.snapshot(chart: ObservationTestSupport.chart())
    let future = try ObservationTestSupport.changing(snapshot, key: "schemaVersion", to: 999)
    XCTAssertThrowsError(try future.validate()) { error in
      XCTAssertEqual(error as? ObservationError, .unsupportedSchema(999))
    }
    let missingFacts = try ObservationTestSupport.changing(snapshot, key: "facts", to: [])
    XCTAssertThrowsError(try missingFacts.validate())
    let multipleParagraphs = try ObservationTestSupport.changing(
      snapshot, key: "selectedText", to: "第一段\n第二段")
    XCTAssertThrowsError(try multipleParagraphs.validate())
  }

  func test刪除單則回顧保留原始觀察與其他回顧() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let first = ObservationTestSupport.review(observation: observation)
    let second = ObservationTestSupport.review(observation: observation)
    context.insert(chart)
    context.insert(observation)
    context.insert(first)
    context.insert(second)
    try context.save()
    ObservationStore.removeReview(first, modelContext: context)
    try context.save()
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservation>()).count, 1)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.id), [second.id])
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<CloudDeletion>()).first?.entityType,
      "SavedObservationReview")
  }

  func test父命盤刪除清除觀察回顧並留下獨立Tombstones() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "observation-review.test"
    context.insert(chart)
    context.insert(observation)
    context.insert(ObservationTestSupport.review(observation: observation))
    try context.save()
    let reminders = try ObservationStore.removeChartChildren(
      chartID: chart.id, modelContext: context)
    context.delete(chart)
    try context.save()
    XCTAssertEqual(reminders, ["observation-review.test"])
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservation>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservationReview>()).isEmpty)
    XCTAssertEqual(
      Set(try context.fetch(FetchDescriptor<CloudDeletion>()).map(\.entityType)),
      ["SavedObservation", "SavedObservationReview"])
  }

  func test空白回顧或已刪除父資料不能寫入() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    context.insert(chart)
    context.insert(observation)
    try context.save()
    XCTAssertThrowsError(
      try ObservationStore.addReview(
        observation: observation, content: "  ", outcome: .uncertain, modelContext: context))
    context.delete(chart)
    try context.save()
    XCTAssertThrowsError(
      try ObservationStore.addReview(
        observation: observation, content: "回顧", outcome: .uncertain, modelContext: context))
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservationReview>()).isEmpty)
  }
}
