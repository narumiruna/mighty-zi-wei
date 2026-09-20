import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class ICloudSynchronizerTests: XCTestCase {
  func test同步讀取最新持久化集合但不帶入呼叫端未儲存草稿() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let chart = try makeChart(name: "已保存")
    let insight = SavedInsight(
      chartID: chart.id, kind: .note, locationID: "chart.general", title: "筆記", content: "內容")
    let deletion = CloudDeletion(entityID: UUID(), entityType: "SavedInsight")
    context.insert(chart)
    context.insert(insight)
    context.insert(deletion)
    try context.save()
    try chart.rename(to: "未儲存草稿")
    let service = SynchronizerService { charts, insights, deletions, receivedContext in
      XCTAssertFalse(receivedContext === context)
      XCTAssertFalse(receivedContext.autosaveEnabled)
      XCTAssertEqual(charts.map(\.name), ["已保存"])
      XCTAssertEqual(insights.map(\.id), [insight.id])
      XCTAssertEqual(deletions.map(\.id), [deletion.id])
    }
    _ = try await synchronize(service: service, context: context)
    XCTAssertEqual(chart.name, "未儲存草稿")
    XCTAssertTrue(context.hasChanges)
  }

  func test成功同步後捷徑讀取下載釘選命盤而失敗不重新核對() async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let defaults = try XCTUnwrap(
      UserDefaults(suiteName: ReviewReminderScheduler.sharedDefaultsSuite))
    let previous = defaults.object(forKey: PinnedChartShortcut.key)
    defer {
      if let previous {
        defaults.set(previous, forKey: PinnedChartShortcut.key)
      } else {
        defaults.removeObject(forKey: PinnedChartShortcut.key)
      }
    }
    defaults.set("原捷徑", forKey: PinnedChartShortcut.key)
    let downloaded = try makeChart(name: "下載命盤")
    downloaded.setPinned(true)
    let success = SynchronizerService { _, _, _, syncContext in
      XCTAssertEqual(defaults.string(forKey: PinnedChartShortcut.key), "原捷徑")
      syncContext.insert(downloaded)
      try syncContext.save()
    }
    _ = try await synchronize(service: success, context: context)
    XCTAssertEqual(defaults.string(forKey: PinnedChartShortcut.key), downloaded.id.uuidString)
    let failure = SynchronizerService { charts, _, _, syncContext in
      for chart in charts { syncContext.delete(chart) }
      throw SynchronizerError.injected
    }
    do {
      _ = try await synchronize(service: failure, context: context)
      XCTFail("失敗必須向呼叫端回報。")
    } catch SynchronizerError.injected {
      XCTAssertEqual(defaults.string(forKey: PinnedChartShortcut.key), downloaded.id.uuidString)
    }
    XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<SavedChart>()), 1)
  }

  private func synchronize(
    service: SynchronizerService, context: ModelContext
  ) async throws -> ICloudSyncResult {
    try await ICloudSynchronizer(service: service).sync(modelContext: context)
  }

  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: SavedChart.self, SavedInsight.self, CloudDeletion.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  private func makeChart(name: String) throws -> SavedChart {
    let profile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30), timeZoneIdentifier: "Asia/Taipei")
    return try SavedChart.make(
      name: name, profile: profile, chart: ZiWeiCalculator().calculate(profile))
  }
}

private enum SynchronizerError: Error { case injected }

@MainActor
private struct SynchronizerService: ICloudSynchronizing {
  let operation: ([SavedChart], [SavedInsight], [CloudDeletion], ModelContext) throws -> Void

  func sync(
    charts: [SavedChart], insights: [SavedInsight], deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> ICloudSyncResult {
    try operation(charts, insights, deletions, modelContext)
    return ICloudSyncResult(uploadedCount: 0, downloadedCount: 1, conflictCount: 0)
  }
}
