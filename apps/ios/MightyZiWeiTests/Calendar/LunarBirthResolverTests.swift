import Foundation
import XCTest

@testable import MightyZiWei

final class LunarBirthResolverTests: XCTestCase {
  func testReferenceCasesHaveTraceableEvidenceAndExpectedCivilDates() throws {
    let references: LunarBirthReferences = try loadFixture("lunar_birth_reference_cases")
    XCTAssertEqual(references.schemaVersion, 1)
    XCTAssertFalse(references.evidencePolicy.isEmpty)
    for sample in references.cases {
      let source = try XCTUnwrap(references.sources.first { $0.id == sample.sourceID })
      XCTAssertFalse(source.locator.isEmpty)
      XCTAssertFalse(source.excerpt.isEmpty)
      XCTAssertFalse(source.limitation.isEmpty)
      if source.kind == "公開文字" {
        XCTAssertEqual(source.sha256?.count, 64)
      }
      let profile = try LunarBirthResolver.resolve(
        LunarBirthInput(
          date: sample.lunar, localTime: sample.time, timeZoneIdentifier: sample.timeZone))
      XCTAssertEqual(profile.localDate, sample.gregorian, sample.name)
      XCTAssertEqual(profile.localTime, sample.time, sample.name)
      XCTAssertEqual(profile.timeZoneIdentifier, sample.timeZone, sample.name)
      XCTAssertEqual(profile.calendarIdentifier, .gregorian, sample.name)
    }
  }

  func testAbsoluteYearDoesNotCollapseAcrossSixtyYearCycles() throws {
    let years = [1904, 1964, 2024, 2084]
    for year in years {
      let profile = try resolve(year, 1, 1)
      XCTAssertEqual(profile.localDate.year, year)
      let normalized = try CalendarNormalizer.normalize(profile)
      XCTAssertEqual(try CalendarNormalizer.lunarDate(from: normalized).cyclicalYear, 41)
      XCTAssertEqual(try LunarBirthResolver.lunarDate(from: normalized).year, year)
    }
  }

  func testLeapMonthIsDistinctAndNeverAppliedAsFollowingMonthDuringConversion() throws {
    XCTAssertEqual(try resolve(2023, 2, 1).localDate, LocalDate(year: 2023, month: 2, day: 20))
    XCTAssertEqual(
      try resolve(2023, 2, 1, leap: true).localDate, LocalDate(year: 2023, month: 3, day: 22))
    XCTAssertEqual(try resolve(2023, 3, 1).localDate, LocalDate(year: 2023, month: 4, day: 20))
    XCTAssertThrowsError(try resolve(2024, 2, 1, leap: true)) {
      XCTAssertEqual($0 as? LunarBirthValidationError, .unavailableLeapMonth)
    }
    XCTAssertThrowsError(try resolve(2023, 3, 1, leap: true)) {
      XCTAssertEqual($0 as? LunarBirthValidationError, .unavailableLeapMonth)
    }
  }

  func testSmallMonthRejectsDayThirtyInsteadOfNormalizingIntoNextMonth() throws {
    XCTAssertEqual(
      try resolve(2023, 2, 29, leap: true).localDate, LocalDate(year: 2023, month: 4, day: 19))
    XCTAssertThrowsError(try resolve(2023, 2, 30, leap: true)) {
      XCTAssertEqual($0 as? LunarBirthValidationError, .invalidDate)
    }
    XCTAssertEqual(try resolve(2023, 2, 30).localDate, LocalDate(year: 2023, month: 3, day: 21))
  }

  func testInvalidComponentsAreRejectedBeforeFoundationCanNormalizeThem() {
    for (month, day) in [(0, 1), (13, 1), (1, 0), (1, 31), (Int.max, 1), (1, Int.min)] {
      XCTAssertThrowsError(try resolve(2023, month, day)) {
        XCTAssertEqual($0 as? LunarBirthValidationError, .invalidDate)
      }
    }
    for year in [Int.min, 60, 1898, 2100, Int.max] {
      XCTAssertThrowsError(try resolve(year, 1, 1)) {
        XCTAssertEqual($0 as? BirthProfileValidationError, .dateOutOfRange)
      }
    }
  }

  func testSupportRangeIsDecidedByConvertedGregorianDate() throws {
    XCTAssertEqual(try resolve(1899, 12, 1).localDate, LocalDate(year: 1900, month: 1, day: 1))
    XCTAssertEqual(try resolve(2099, 11, 20).localDate, LocalDate(year: 2099, month: 12, day: 31))
    for date in [
      LunarBirthDate(year: 1899, month: 11, day: 29),
      LunarBirthDate(year: 2099, month: 11, day: 21),
    ] {
      XCTAssertThrowsError(
        try LunarBirthResolver.resolve(LunarBirthInput(date: date, localTime: noon))
      ) {
        XCTAssertEqual($0 as? BirthProfileValidationError, .dateOutOfRange)
      }
    }
  }

  func testInvalidTimeAndTimeZoneAreRejected() {
    for time in [LocalTime(hour: 24, minute: 0), LocalTime(hour: 12, minute: 60)] {
      XCTAssertThrowsError(try resolve(2024, 1, 1, time: time)) {
        XCTAssertEqual($0 as? BirthProfileValidationError, .invalidTime)
      }
    }
    XCTAssertThrowsError(try resolve(2024, 1, 1, zone: "不是時區")) {
      XCTAssertEqual($0 as? BirthProfileValidationError, .invalidTimeZone)
    }
  }

  func testNonexistentDSTTimeIsRejectedWithoutShiftingTheClock() {
    // 此例驗證既有民用時間政策，不列為海外獨立曆法來源。
    XCTAssertThrowsError(
      try resolve(2021, 2, 2, time: LocalTime(hour: 2, minute: 30), zone: "America/New_York")
    ) {
      XCTAssertEqual($0 as? BirthProfileValidationError, .nonexistentLocalTime)
    }
  }

  func testRepeatedHistoricalTimeUsesFirstOccurrenceAndPreservesTheZone() throws {
    let profile = try resolve(
      1945, 8, 25, time: LocalTime(hour: 1, minute: 30), zone: "America/New_York")
    let normalized = try CalendarNormalizer.normalize(profile)
    XCTAssertTrue(normalized.isRepeatedLocalTime)
    XCTAssertEqual(normalized.instant.timeIntervalSince1970, -765_397_800, accuracy: 0.1)
    XCTAssertEqual(profile.timeZoneIdentifier, "America/New_York")
  }

  func testMidnightAndZiHourKeepTheCivilDay() throws {
    for time in [LocalTime(hour: 0, minute: 0), LocalTime(hour: 23, minute: 30)] {
      let profile = try resolve(2024, 1, 1, time: time)
      XCTAssertEqual(profile.localDate, LocalDate(year: 2024, month: 2, day: 10))
      XCTAssertEqual(try ZiWeiCalculator().calculate(profile).hourBranch, .zi)
    }
    XCTAssertEqual(
      try resolve(2024, 1, 2, time: LocalTime(hour: 0, minute: 0)).localDate,
      LocalDate(year: 2024, month: 2, day: 11))
  }

  func testOverseasCivilDateIsNotConvertedToTaiwanDate() throws {
    let time = LocalTime(hour: 23, minute: 30)
    let profile = try resolve(2024, 1, 1, time: time, zone: "America/New_York")
    XCTAssertEqual(profile.localDate, LocalDate(year: 2024, month: 2, day: 10))
    var taipei = Calendar(identifier: .gregorian)
    taipei.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
    let normalized = try CalendarNormalizer.normalize(profile)
    XCTAssertEqual(taipei.component(.day, from: normalized.instant), 11)
    XCTAssertEqual(profile.localTime, time)
  }

  private var noon: LocalTime { LocalTime(hour: 12, minute: 0) }

  private func resolve(
    _ year: Int, _ month: Int, _ day: Int, leap: Bool = false,
    time: LocalTime = LocalTime(hour: 12, minute: 0), zone: String = "Asia/Taipei"
  ) throws -> BirthProfile {
    try LunarBirthResolver.resolve(
      LunarBirthInput(
        date: LunarBirthDate(year: year, month: month, day: day, isLeapMonth: leap),
        localTime: time, timeZoneIdentifier: zone))
  }

  private func loadFixture<T: Decodable>(_ name: String) throws -> T {
    let bundle = Bundle(for: Self.self)
    let url =
      bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? bundle.url(forResource: name, withExtension: "json")
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: XCTUnwrap(url)))
  }
}

private struct LunarBirthReferences: Decodable {
  let schemaVersion: Int
  let evidencePolicy: String
  let sources: [Source]
  let cases: [ReferenceCase]

  struct Source: Decodable {
    let id: String
    let kind: String
    let locator: String
    let sha256: String?
    let excerpt: String
    let limitation: String
  }

  struct ReferenceCase: Decodable {
    let name: String
    let sourceID: String
    let lunar: LunarBirthDate
    let gregorian: LocalDate
    let time: LocalTime
    let timeZone: String
  }
}
