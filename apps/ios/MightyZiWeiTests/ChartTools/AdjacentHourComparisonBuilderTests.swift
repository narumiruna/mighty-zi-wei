import XCTest

@testable import MightyZiWei

final class AdjacentHourComparisonBuilderTests: XCTestCase {
  func test比較只包含指定的已驗證位置差異() throws {
    let comparison = try AdjacentHourComparisonBuilder().make(
      from: BirthProfile(
        localDate: LocalDate(year: 1990, month: 6, day: 15),
        localTime: LocalTime(hour: 10, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))

    for snapshot in [comparison.previous, comparison.current, comparison.next] {
      XCTAssertEqual(snapshot.mainStars.count, 14)
      XCTAssertTrue(snapshot.mainStars.allSatisfy { $0.star.category == .main })
      XCTAssertEqual(snapshot.transformations.count, 4)
    }

    let differences = comparison.previousDifferences + comparison.nextDifferences
    XCTAssertFalse(differences.isEmpty)
    for difference in differences {
      XCTAssertNotEqual(difference.currentValue, difference.adjacentValue)
      switch difference.subject {
      case .lifePalace, .bodyPalace, .fiveElementBureau, .transformation:
        break
      case .mainStar(let star):
        XCTAssertEqual(star.category, .main)
      }
    }
  }

  func test子時跨日仍取得正確的前後時辰() throws {
    let lateZiHour = try AdjacentHourComparisonBuilder().make(
      from: BirthProfile(
        localDate: LocalDate(year: 2000, month: 1, day: 1),
        localTime: LocalTime(hour: 23, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))

    XCTAssertEqual(lateZiHour.previous.hourBranch, .hai)
    XCTAssertEqual(
      lateZiHour.previous.birthProfile.localDate, LocalDate(year: 2000, month: 1, day: 1))
    XCTAssertEqual(lateZiHour.previous.birthProfile.localTime, LocalTime(hour: 21, minute: 0))
    XCTAssertEqual(lateZiHour.current.birthProfile.localTime, LocalTime(hour: 23, minute: 30))
    XCTAssertEqual(lateZiHour.next.hourBranch, .chou)
    XCTAssertEqual(lateZiHour.next.birthProfile.localDate, LocalDate(year: 2000, month: 1, day: 2))
    XCTAssertEqual(lateZiHour.next.birthProfile.localTime, LocalTime(hour: 1, minute: 0))

    let earlyZiHour = try AdjacentHourComparisonBuilder().make(
      from: BirthProfile(
        localDate: LocalDate(year: 2000, month: 1, day: 2),
        localTime: LocalTime(hour: 0, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))

    XCTAssertEqual(earlyZiHour.previous.hourBranch, .hai)
    XCTAssertEqual(
      earlyZiHour.previous.birthProfile.localDate, LocalDate(year: 2000, month: 1, day: 1))
    XCTAssertEqual(earlyZiHour.next.hourBranch, .chou)
    XCTAssertEqual(earlyZiHour.next.birthProfile.localDate, LocalDate(year: 2000, month: 1, day: 2))
  }

  func test夏令時間跳時以相鄰民用時辰計算() throws {
    let comparison = try AdjacentHourComparisonBuilder().make(
      from: BirthProfile(
        localDate: LocalDate(year: 2021, month: 3, day: 14),
        localTime: LocalTime(hour: 1, minute: 30),
        timeZoneIdentifier: "America/New_York"
      ))

    XCTAssertEqual(comparison.previous.hourBranch, .zi)
    XCTAssertEqual(
      comparison.previous.birthProfile.localDate, LocalDate(year: 2021, month: 3, day: 13))
    XCTAssertEqual(comparison.previous.birthProfile.localTime, LocalTime(hour: 23, minute: 0))
    XCTAssertEqual(comparison.current.hourBranch, .chou)
    XCTAssertEqual(comparison.next.hourBranch, .yin)
    XCTAssertEqual(comparison.next.birthProfile.localDate, LocalDate(year: 2021, month: 3, day: 14))
    XCTAssertEqual(comparison.next.birthProfile.localTime, LocalTime(hour: 3, minute: 0))
  }

  func test支援日期邊界外的相鄰時辰會回傳明確錯誤() {
    XCTAssertThrowsError(
      try AdjacentHourComparisonBuilder().make(
        from: BirthProfile(
          localDate: LocalDate(year: 1900, month: 1, day: 1),
          localTime: LocalTime(hour: 0, minute: 30),
          timeZoneIdentifier: "Asia/Taipei"
        ))
    ) { error in
      XCTAssertEqual(
        error as? AdjacentHourComparisonError,
        .adjacentHourUnavailable(.previous)
      )
    }

    XCTAssertThrowsError(
      try AdjacentHourComparisonBuilder().make(
        from: BirthProfile(
          localDate: LocalDate(year: 2099, month: 12, day: 31),
          localTime: LocalTime(hour: 23, minute: 30),
          timeZoneIdentifier: "Asia/Taipei"
        ))
    ) { error in
      XCTAssertEqual(
        error as? AdjacentHourComparisonError,
        .adjacentHourUnavailable(.next)
      )
    }
  }

  func test不存在的當地時間會安全回傳既有驗證錯誤() {
    XCTAssertThrowsError(
      try AdjacentHourComparisonBuilder().make(
        from: BirthProfile(
          localDate: LocalDate(year: 2021, month: 3, day: 14),
          localTime: LocalTime(hour: 2, minute: 30),
          timeZoneIdentifier: "America/New_York"
        ))
    ) { error in
      XCTAssertEqual(error as? BirthProfileValidationError, .nonexistentLocalTime)
    }
  }
}
