import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class ObservationSchemaMigrationTests: XCTestCase {
  func test未標版本舊Store升級保留命盤筆記收藏完整對話與Tombstone() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "ObservationMigration.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "default.store")
    let chartID = UUID()
    let conversationID = UUID()
    let deletionID = UUID()
    try autoreleasepool {
      // 與升級前 App 完全相同的未版本化 schema，不以新版 store 冒充舊版。
      let schema = Schema([
        SavedChart.self, SavedInsight.self, SavedConversation.self, CloudDeletion.self,
      ])
      let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
      let context = ModelContext(container)
      let source = try ObservationTestSupport.chart()
      source.id = chartID
      context.insert(source)
      context.insert(
        SavedInsight(
          chartID: chartID, kind: .note, locationID: "chart.general", title: "舊筆記",
          content: "原始私人內容"))
      context.insert(
        SavedInsight.bookmark(
          chartID: chartID, locationID: "interpretation.legacy", title: "舊收藏", content: "歷史文字",
          evidenceFactIDs: []))
      context.insert(
        SavedConversation(
          id: conversationID, chartID: chartID, chartName: "合成命盤", chartDetail: "舊資料",
          modelIdentifier: "舊模型", title: "完整對話例外",
          turns: [ChartConversationTurn(question: "原始完整問題", answer: "原始完整回答", evidenceFactIDs: [])]
        ))
      context.insert(CloudDeletion(id: deletionID, entityID: UUID(), entityType: "SavedChart"))
      try context.save()
    }
    let result = AppModelContainerLoader.load {
      let schema = AppModelContainerLoader.makeSchema()
      return try ModelContainer(
        for: schema, migrationPlan: AppModelSchemaMigrationPlan.self,
        configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
      )
    }
    let container = try result.get()
    let context = ModelContext(container)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedChart>()).map(\.id), [chartID])
    let insights = try context.fetch(FetchDescriptor<SavedInsight>())
    XCTAssertEqual(insights.count, 2)
    XCTAssertEqual(Set(insights.map(\.title)), ["舊筆記", "舊收藏"])
    XCTAssertTrue(insights.allSatisfy { $0.evidenceSeedIDs.isEmpty })
    let conversations = try context.fetch(FetchDescriptor<SavedConversation>())
    XCTAssertEqual(conversations.map(\.id), [conversationID])
    XCTAssertEqual(conversations.first?.turns.first?.question, "原始完整問題")
    XCTAssertEqual(conversations.first?.turns.first?.answer, "原始完整回答")
    XCTAssertEqual(try context.fetch(FetchDescriptor<CloudDeletion>()).map(\.id), [deletionID])
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservation>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservationReview>()).isEmpty)
    let observation = try ObservationTestSupport.observation(
      chart: XCTUnwrap(context.fetch(FetchDescriptor<SavedChart>()).first))
    context.insert(observation)
    try context.save()
    XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SavedObservation>()).count, 1)
  }

  func test未知StoreSchema安全拒絕且不建立空白替代資料庫() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "ObservationUnknownSchema.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "default.store")
    try autoreleasepool {
      let schema = Schema([FutureObservationMigrationModel.self])
      let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
      let context = ModelContext(container)
      context.insert(FutureObservationMigrationModel(content: "不得遺失的未來資料"))
      try context.save()
    }
    let result = AppModelContainerLoader.load {
      let schema = AppModelContainerLoader.makeSchema()
      return try ModelContainer(
        for: schema, migrationPlan: AppModelSchemaMigrationPlan.self,
        configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }
    guard case .failure = result else { return XCTFail("未知 schema 不應自動重建") }
    let originalSchema = Schema([FutureObservationMigrationModel.self])
    let original = try ModelContainer(
      for: originalSchema,
      configurations: [
        ModelConfiguration(schema: originalSchema, url: url, cloudKitDatabase: .none)
      ])
    XCTAssertEqual(
      try ModelContext(original).fetch(FetchDescriptor<FutureObservationMigrationModel>()).first?
        .content, "不得遺失的未來資料")
  }
}

@Model
private final class FutureObservationMigrationModel {
  var content: String
  init(content: String) { self.content = content }
}
