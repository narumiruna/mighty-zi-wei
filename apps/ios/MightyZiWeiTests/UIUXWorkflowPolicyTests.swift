import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class UIUXWorkflowPolicyTests: XCTestCase {
  func test已儲存命盤依搜尋與篩選條件區分結果狀態() {
    let policy = SavedChartsResultStatePolicy()
    XCTAssertEqual(
      policy.state(hasResults: true, searchText: "不存在", hasActiveFilters: true), .results)
    XCTAssertEqual(
      policy.state(hasResults: false, searchText: "小明", hasActiveFilters: false), .searchEmpty)
    XCTAssertEqual(
      policy.state(hasResults: false, searchText: " \n ", hasActiveFilters: true), .filterEmpty)
    XCTAssertEqual(
      policy.state(hasResults: false, searchText: "小明", hasActiveFilters: true),
      .searchAndFilterEmpty)
    XCTAssertEqual(
      policy.state(hasResults: false, searchText: " \n ", hasActiveFilters: false), .results)
  }

  func test基本解讀與AI整理並存且重新整理保留目前選擇() {
    let basic = ChartInterpretation(sections: [], source: .deterministic)
    let firstAI = ChartInterpretation(
      sections: [
        InterpretationSection(
          id: "ai.first",
          category: .overview,
          title: "AI 第一版",
          content: "第一版內容",
          evidenceFactIDs: []
        )
      ],
      source: .remoteAI
    )
    let refreshedAI = ChartInterpretation(
      sections: [
        InterpretationSection(
          id: "ai.refreshed",
          category: .overview,
          title: "AI 更新版",
          content: "更新內容",
          evidenceFactIDs: []
        )
      ],
      source: .remoteAI
    )
    var state = InterpretationDisplayState(basic: basic)

    XCTAssertEqual(state.selectedSource, .deterministic)
    XCTAssertEqual(state.selected, basic)
    state.select(.remoteAI)
    XCTAssertEqual(state.selectedSource, .deterministic)

    state.acceptAI(firstAI)
    XCTAssertEqual(state.selectedSource, .remoteAI)
    XCTAssertEqual(state.selected, firstAI)

    state.select(.deterministic)
    state.acceptAI(refreshedAI)
    XCTAssertEqual(state.selectedSource, .deterministic)
    XCTAssertEqual(state.selected, basic)
    state.select(.remoteAI)
    XCTAssertEqual(state.selected, refreshedAI)
  }

  func test同步Adapter使用獨立Context與最新持久化資料() async throws {
    let chart = try makeSavedChart(name: "最新命盤")
    let container = try ModelContainer(
      for: SavedChart.self,
      SavedInsight.self,
      CloudDeletion.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    context.insert(chart)
    try context.save()
    let service = RecordingICloudSynchronizingService()
    service.setOriginalContext(context)
    let synchronizer = ICloudSynchronizer(service: service)

    _ = try await synchronizer.sync(
      charts: [],
      insights: [],
      deletions: [],
      modelContext: context
    )

    XCTAssertEqual(service.receivedChartNames, ["最新命盤"])
    XCTAssertFalse(service.receivedOriginalContext)
  }

  func test同步協調器呈現等待同步中與完成狀態() async throws {
    let coordinator = ICloudSyncCoordinator()
    let expected = ICloudSyncResult(uploadedCount: 1, downloadedCount: 2, conflictCount: 3)
    XCTAssertEqual(coordinator.status, .idle)
    coordinator.markEnabledWaiting()
    XCTAssertEqual(coordinator.status, .waiting)
    let result = try await coordinator.synchronize {
      XCTAssertTrue(coordinator.isSyncing)
      XCTAssertEqual(coordinator.status, .syncing)
      return expected
    }
    XCTAssertEqual(result, expected)
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(coordinator.status, .synced(expected))
  }

  func test同步未完成會保留可重試狀態且重試可完成() async throws {
    let coordinator = ICloudSyncCoordinator()
    let expected = ICloudSyncResult(uploadedCount: 4, downloadedCount: 5, conflictCount: 1)
    coordinator.markEnabledWaiting()
    do {
      _ = try await coordinator.synchronize { throw ICloudPresentationTestError.partialRemote }
      XCTFail("部分同步失敗應回報錯誤。")
    } catch ICloudPresentationTestError.partialRemote {
      // 預期錯誤。
    }
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(coordinator.status, .incomplete(.partialRemote))
    let result = try await coordinator.synchronize {
      XCTAssertEqual(coordinator.status, .syncing)
      return expected
    }
    XCTAssertEqual(result, expected)
    XCTAssertEqual(coordinator.status, .synced(expected))
  }

  func test同步失敗只呈現安全帳號或部分同步訊息() {
    let account = ICloudSyncFailureState(error: ICloudSyncService.SyncError.iCloudUnavailable)
    let partial = ICloudSyncFailureState(error: ICloudPresentationTestError.partialRemote)
    XCTAssertEqual(account, .accountUnavailable)
    XCTAssertEqual(account.message, "同步未完成。請確認已登入 iCloud 並允許此 App 使用 iCloud，再重試。")
    XCTAssertEqual(partial, .partialRemote)
    XCTAssertEqual(partial.message, "同步未完成，iCloud 可能已收到部分資料。本機資料仍保留，你可以安全地重試。")
    XCTAssertFalse(partial.message.contains(ICloudPresentationTestError.privateDescription))
  }

  func test同步協調器讓同時請求共用同一個執行結果() async throws {
    let coordinator = ICloudSyncCoordinator()
    let expected = ICloudSyncResult(uploadedCount: 1, downloadedCount: 2, conflictCount: 3)
    var executionCount = 0
    var release: CheckedContinuation<Void, Never>?

    let first = Task { @MainActor in
      try await coordinator.synchronize {
        executionCount += 1
        await withCheckedContinuation { release = $0 }
        return expected
      }
    }
    while release == nil {
      await Task.yield()
    }
    XCTAssertEqual(coordinator.status, .syncing)
    let second = Task { @MainActor in
      try await coordinator.synchronize {
        executionCount += 1
        return ICloudSyncResult(
          uploadedCount: 99,
          downloadedCount: 99,
          conflictCount: 99
        )
      }
    }
    while coordinator.waitingCallerCount == 0 {
      await Task.yield()
    }
    XCTAssertEqual(coordinator.status, .syncing)
    release?.resume()
    release = nil

    let combined = ICloudSyncResult(
      uploadedCount: 100,
      downloadedCount: 101,
      conflictCount: 102
    )
    let firstResult = try await first.value
    let secondResult = try await second.value
    XCTAssertEqual(firstResult, combined)
    XCTAssertEqual(secondResult, combined)
    XCTAssertEqual(executionCount, 2)
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(coordinator.status, .synced(combined))
  }

  func test等待共用同步的呼叫可取消且不停止主要同步() async throws {
    let coordinator = ICloudSyncCoordinator()
    let expected = ICloudSyncResult(uploadedCount: 1, downloadedCount: 0, conflictCount: 0)
    var release: CheckedContinuation<Void, Never>?
    let first = Task { @MainActor in
      try await coordinator.synchronize {
        await withCheckedContinuation { release = $0 }
        return expected
      }
    }
    while release == nil { await Task.yield() }

    let waiter = Task { @MainActor in
      try await coordinator.synchronize {
        XCTFail("已取消的 trailing 呼叫不應執行。")
        return expected
      }
    }
    while coordinator.waitingCallerCount == 0 { await Task.yield() }
    waiter.cancel()

    do {
      _ = try await waiter.value
      XCTFail("取消等待應回傳 CancellationError。")
    } catch is CancellationError {
      // 預期取消。
    }
    XCTAssertTrue(coordinator.isSyncing)
    XCTAssertEqual(coordinator.waitingCallerCount, 0)

    release?.resume()
    release = nil
    let result = try await first.value
    XCTAssertEqual(result, expected)
    XCTAssertEqual(coordinator.status, .synced(expected))
  }

  private func makeSavedChart(name: String) throws -> SavedChart {
    let profile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    return try SavedChart.make(
      name: name,
      profile: profile,
      chart: ZiWeiCalculator().calculate(profile)
    )
  }
}

private enum ICloudPresentationTestError: LocalizedError {
  case partialRemote
  static let privateDescription = "CloudKit record payload: private-chart-name"
  var errorDescription: String? { Self.privateDescription }
}

@MainActor
private final class RecordingICloudSynchronizingService: ICloudSynchronizing {
  private var originalContext: ModelContext?
  private(set) var receivedChartNames: [String] = []
  private(set) var receivedOriginalContext = false

  func sync(
    charts: [SavedChart],
    insights: [SavedInsight],
    deletions: [CloudDeletion],
    modelContext: ModelContext
  ) async throws -> ICloudSyncResult {
    _ = (insights, deletions)
    receivedChartNames = charts.map(\.name)
    if let originalContext {
      receivedOriginalContext = originalContext === modelContext
    }
    return ICloudSyncResult(uploadedCount: 0, downloadedCount: 0, conflictCount: 0)
  }

  func setOriginalContext(_ context: ModelContext) {
    originalContext = context
  }
}
