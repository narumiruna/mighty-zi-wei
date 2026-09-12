import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class ObservationReminderTests: XCTestCase {
  func test通知拒絕或排程失敗仍保存觀察和原始想法() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    context.insert(chart)
    try context.save()
    let result = try await ObservationStore.saveObservation(
      chartID: chart.id, snapshot: ObservationTestSupport.snapshot(chart: chart),
      reviewDate: .now.addingTimeInterval(3600), modelContext: context,
      schedule: { _, _ in throw ReviewReminderScheduler.ReminderError.permissionDenied }
    )
    XCTAssertNotNil(result.reminderWarning)
    XCTAssertNil(result.observation.reminderIdentifier)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservation>()).count, 1)
    XCTAssertEqual(result.observation.snapshot?.initialThought, "原始想法不可覆寫")
  }

  func test儲存失敗只取消本次新通知而不取消有效舊通知() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let chart = try ObservationTestSupport.chart()
    let existing = try ObservationTestSupport.observation(chart: chart)
    existing.reminderIdentifier = "有效舊通知"
    context.insert(chart)
    context.insert(existing)
    try context.save()
    var cancelled: [String] = []
    do {
      _ = try await ObservationStore.saveObservation(
        chartID: chart.id, snapshot: ObservationTestSupport.snapshot(chart: chart),
        reviewDate: .now.addingTimeInterval(3600), modelContext: context,
        schedule: { _, _ in "新通知" },
        cancel: { if let identifier = $0 { cancelled.append(identifier) } },
        save: { _ in throw ObservationTestSupport.Failure.simulated }
      )
      XCTFail("應回報儲存失敗")
    } catch {
      XCTAssertEqual(cancelled, ["新通知"])
    }
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [existing.id])
    XCTAssertEqual(existing.reminderIdentifier, "有效舊通知")
  }

  func test等待通知期間刪除命盤不會產生孤兒觀察() async throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    context.insert(chart)
    try context.save()
    let chartID = chart.id
    let snapshot = try ObservationTestSupport.snapshot(chart: chart)
    var cancelled = false
    do {
      _ = try await ObservationStore.saveObservation(
        chartID: chartID, snapshot: snapshot, reviewDate: .now.addingTimeInterval(3600),
        modelContext: context,
        schedule: { _, _ in
          context.delete(chart)
          try context.save()
          return "新通知"
        },
        cancel: { _ in cancelled = true }
      )
      XCTFail("應拒絕已刪除的父命盤")
    } catch {
      XCTAssertEqual(error as? ObservationError, .missingParent)
    }
    XCTAssertTrue(cancelled)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservation>()).isEmpty)
  }

  func test刪除全部提醒包含觀察但觀察不使用Widget前綴() {
    let observation = "\(ReviewReminderScheduler.observationIdentifierPrefix)合成通知"
    let note = "\(ReviewReminderScheduler.reminderIdentifierPrefix)合成通知"
    XCTAssertEqual(
      ReviewReminderScheduler.reviewReminderIdentifiers(in: [observation, note, "其他通知"]),
      [observation, note])
    XCTAssertFalse(observation.hasPrefix(ReviewReminderScheduler.reminderIdentifierPrefix))
  }
}
