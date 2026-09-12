import Foundation
import XCTest

@testable import MightyZiWei

final class LunarBirthInputIntegrationTests: XCTestCase {
  func testSwitchingModesKeepsBothDraftsIncludingInvalidLunarText() throws {
    var draft = BirthInputDraft()
    let original = try draft.profile()
    draft.mode = .lunar
    draft.lunarYear = "尚未確定"
    draft.lunarMonth = "2"
    draft.lunarDay = "30"
    draft.isLeapMonth = true
    let invalidDraft = draft
    XCTAssertThrowsError(try draft.profile())
    XCTAssertEqual(draft, invalidDraft)
    draft.mode = .gregorian
    XCTAssertEqual(try draft.profile(), original)
    draft.mode = .lunar
    XCTAssertEqual(draft, invalidDraft)
  }

  func testSuccessfulConversionDoesNotOverwriteGregorianDraftOrPersistLunarFields() throws {
    var draft = validDraft()
    let gregorianDraft = draft.gregorianDate
    let profile = try draft.profile()
    XCTAssertEqual(profile.localDate, LocalDate(year: 2023, month: 3, day: 22))
    XCTAssertEqual(draft.gregorianDate, gregorianDraft)
    let data = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(
      Set(object.keys), ["localDate", "localTime", "calendarIdentifier", "timeZoneIdentifier"])
    XCTAssertEqual(object["calendarIdentifier"] as? String, "gregorian")
    draft.mode = .gregorian
    XCTAssertEqual(try draft.profile().localDate, gregorianDraft)
  }

  func testChangingTimeZoneAndTimeRevalidatesWithoutDiscardingLunarDraft() throws {
    var draft = validDraft()
    draft.lunarYear = "2021"
    draft.lunarDay = "2"
    draft.isLeapMonth = false
    draft.localTime = LocalTime(hour: 2, minute: 30)
    draft.timeZoneIdentifier = "America/New_York"
    let invalidDraft = draft
    XCTAssertThrowsError(try draft.profile()) {
      XCTAssertEqual($0 as? BirthProfileValidationError, .nonexistentLocalTime)
    }
    XCTAssertEqual(draft, invalidDraft)
    draft.localTime = LocalTime(hour: 3, minute: 30)
    XCTAssertEqual(try draft.profile().localDate, LocalDate(year: 2021, month: 3, day: 14))
    draft.timeZoneIdentifier = "Asia/Taipei"
    draft.localTime = LocalTime(hour: 2, minute: 30)
    XCTAssertEqual(try draft.profile().timeZoneIdentifier, "Asia/Taipei")
  }

  func testLunarEntryMatchesAllExistingGoldenProfilesChartsAndDuplicateDetection() throws {
    for name in goldenNames {
      let fixture: ExistingGolden = try loadFixture(name)
      let lunar = fixture.expected.lunarDate
      let gregorianYear = fixture.input.localDate.year
      // Fixture 的循環年只用於辨認該公曆日期屬本年還是前一農曆年。
      let year =
        (gregorianYear - 4) % 60 + 1 == lunar.cyclicalYear ? gregorianYear : gregorianYear - 1
      let input = LunarBirthInput(
        date: LunarBirthDate(
          year: year, month: lunar.month, day: lunar.day, isLeapMonth: lunar.isLeapMonth),
        localTime: fixture.input.localTime, timeZoneIdentifier: fixture.input.timeZoneIdentifier)
      let resolved = try LunarBirthResolver.resolve(input)
      XCTAssertEqual(resolved, fixture.input, name)
      let expectedChart = try ZiWeiCalculator().calculate(fixture.input)
      let lunarChart = try ZiWeiCalculator().calculate(resolved)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      XCTAssertEqual(try encoder.encode(lunarChart), try encoder.encode(expectedChart), name)
      let first = try SavedChart.make(name: "公曆", profile: fixture.input, chart: expectedChart)
      let second = try SavedChart.make(name: "農曆", profile: resolved, chart: lunarChart)
      XCTAssertTrue(first.hasSameBirthProfile(as: second), name)
      XCTAssertEqual(first.birthProfileData, second.birthProfileData, name)
    }
  }

  func testAdjacentHourComparisonUsesExactlyTheResolvedGregorianProfile() throws {
    var draft = validDraft()
    draft.localTime = LocalTime(hour: 23, minute: 30)
    let resolved = try draft.profile()
    let expected = BirthProfile(
      localDate: LocalDate(year: 2023, month: 3, day: 22), localTime: draft.localTime)
    XCTAssertEqual(
      try AdjacentHourComparisonBuilder().make(from: resolved),
      try AdjacentHourComparisonBuilder().make(from: expected))
  }

  private func validDraft() -> BirthInputDraft {
    var draft = BirthInputDraft()
    draft.mode = .lunar
    draft.lunarYear = "2023"
    draft.lunarMonth = "2"
    draft.lunarDay = "1"
    draft.isLeapMonth = true
    return draft
  }

  private let goldenNames = [
    "chart_001_normal", "chart_002_zi_hour", "chart_003_lunar_new_year", "chart_004_leap_month",
    "chart_005_historical_dst", "chart_006_1900_boundary", "chart_007_2099_boundary",
    "chart_008_hour_yin",
    "chart_009_hour_mao", "chart_010_hour_chen", "chart_011_hour_wei", "chart_012_hour_shen",
    "chart_013_hour_you", "chart_014_hour_xu", "chart_015_hour_hai",
  ]

  private func loadFixture<T: Decodable>(_ name: String) throws -> T {
    let bundle = Bundle(for: Self.self)
    let url =
      bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? bundle.url(forResource: name, withExtension: "json")
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: XCTUnwrap(url)))
  }
}

private struct ExistingGolden: Decodable {
  let input: BirthProfile
  let expected: Expected

  struct Expected: Decodable {
    let lunarDate: LunarDate
  }
}
