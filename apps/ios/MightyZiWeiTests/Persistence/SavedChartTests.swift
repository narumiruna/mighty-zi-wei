import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class SavedChartTests: XCTestCase {
  func test儲存資料以BirthProfile為SourceOfTruth() throws {
    let profile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let chart = try ZiWeiCalculator().calculate(profile)
    let saved = try SavedChart.make(name: "測試命盤", profile: profile, chart: chart)

    XCTAssertEqual(try saved.birthProfile(), profile)
    XCTAssertEqual(try saved.resolvedChart().stars, chart.stars)
    XCTAssertEqual(saved.ruleSetID, RuleSetIdentity.taiwanTraditionalSanheV1.id)
    XCTAssertEqual(saved.appSchemaVersion, SavedChart.schemaVersion)
  }

  func test不相容Cache會重新計算() throws {
    let profile = BirthProfile(
      localDate: LocalDate(year: 2024, month: 2, day: 10),
      localTime: LocalTime(hour: 0, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let chart = try ZiWeiCalculator().calculate(profile)
    let saved = try SavedChart.make(name: "", profile: profile, chart: chart)
    saved.ruleSetVersion = 0
    saved.chartCacheData = Data("無效快取".utf8)

    let regenerated = try saved.resolvedChart()

    XCTAssertEqual(regenerated.ruleSet, .taiwanTraditionalSanheV1)
    XCTAssertEqual(saved.ruleSetVersion, 1)
    XCTAssertNotNil(
      try JSONDecoder().decode(ZiWeiChart.self, from: XCTUnwrap(saved.chartCacheData)))
  }

  func test所有命盤選單以出生時間區分同名命盤() throws {
    let firstProfile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let secondProfile = BirthProfile(
      localDate: LocalDate(year: 1992, month: 8, day: 20),
      localTime: LocalTime(hour: 18, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let first = try SavedChart.make(
      name: "同名命盤",
      profile: firstProfile,
      chart: ZiWeiCalculator().calculate(firstProfile)
    )
    let second = try SavedChart.make(
      name: "同名命盤",
      profile: secondProfile,
      chart: ZiWeiCalculator().calculate(secondProfile)
    )

    let firstLabel = SavedChartPickerLabelBuilder.make(savedChart: first)
    let secondLabel = SavedChartPickerLabelBuilder.make(savedChart: second)

    XCTAssertEqual(firstLabel, "同名命盤・1990/06/15 10:30")
    XCTAssertEqual(secondLabel, "同名命盤・1992/08/20 18:30")
    XCTAssertNotEqual(firstLabel, secondLabel)
  }

  func test已開啟命盤的來源資料變更時內容Revision也會更新() throws {
    let originalProfile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let savedChart = try SavedChart.make(
      name: "測試命盤",
      profile: originalProfile,
      chart: ZiWeiCalculator().calculate(originalProfile)
    )
    let originalRevision = SavedChartContentRevision(savedChart: savedChart)
    let restoredProfile = BirthProfile(
      localDate: LocalDate(year: 1992, month: 8, day: 20),
      localTime: LocalTime(hour: 18, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )

    savedChart.birthProfileData = try JSONEncoder().encode(restoredProfile)

    XCTAssertNotEqual(
      SavedChartContentRevision(savedChart: savedChart),
      originalRevision
    )
  }

  func test命盤識別只在對應SwiftData紀錄仍存在時有效() {
    let existingID = UUID()
    let deletedID = UUID()

    XCTAssertEqual(
      SavedChartReferenceResolver.existingID(
        savedChartID: nil,
        newlySavedChartID: existingID,
        availableIDs: [existingID]
      ),
      existingID
    )
    XCTAssertNil(
      SavedChartReferenceResolver.existingID(
        savedChartID: nil,
        newlySavedChartID: deletedID,
        availableIDs: [existingID]
      ))
  }

  func test剛儲存完成時不會因Query尚未刷新而遺失命盤識別() {
    let newlySavedID = UUID()

    XCTAssertEqual(
      SavedChartReferenceResolver.effectiveID(
        savedChartID: nil,
        newlySavedChartID: newlySavedID,
        newlySavedIsConfirmed: true,
        availableIDs: []
      ),
      newlySavedID
    )
    XCTAssertNil(
      SavedChartReferenceResolver.effectiveID(
        savedChartID: nil,
        newlySavedChartID: newlySavedID,
        newlySavedIsConfirmed: false,
        availableIDs: []
      ))
  }

  func testSwiftData可新增重新命名與刪除() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: SavedChart.self, configurations: configuration)
    let context = ModelContext(container)
    let profile = BirthProfile(
      localDate: LocalDate(year: 2000, month: 1, day: 1),
      localTime: LocalTime(hour: 12, minute: 0)
    )
    let saved = try SavedChart.make(
      name: "原名稱",
      profile: profile,
      chart: ZiWeiCalculator().calculate(profile)
    )

    context.insert(saved)
    try context.save()
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedChart>()).count, 1)

    try saved.rename(to: "新名稱")
    try context.save()
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedChart>()).first?.name, "新名稱")

    context.delete(saved)
    try context.save()
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedChart>()).isEmpty)
  }
}
