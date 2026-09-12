import Foundation
import XCTest

@testable import MightyZiWei

/// Sweep 只驗證 Foundation 往返、唯一性與具名異常的安全拒絕，不作獨立曆法證據。
final class LunarBirthRoundTripTests: XCTestCase {
  func testEveryCivilDayFrom1900Through1999RoundTripsUniquely() throws {
    try sweep(years: 1900...1999, expectedCount: 36_524)
  }

  func testEveryCivilDayFrom2000Through2099RoundTripsOrRejectsKnownInvalidMonthBoundaries() throws {
    try sweep(years: 2000...2099, expectedCount: 36_525)
  }

  func testOverseasYearBoundariesPreserveExistingHistoricalTimeRejections() throws {
    for zone in ["America/New_York", "Europe/London", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
      for year in 1900...2099 {
        for month in [1, 2, 12] {
          for time in [LocalTime(hour: 0, minute: 0), LocalTime(hour: 23, minute: 30)] {
            try checkOverseasSample(year: year, month: month, time: time, zone: zone)
          }
        }
      }
    }
  }

  func testInvalidDayZeroAndItsMonthCannotBecomeConfirmedBirthData() throws {
    let dates = [LocalDate(year: 2057, month: 9, day: 28), LocalDate(year: 2097, month: 8, day: 7)]
    for date in dates {
      let normalized = try CalendarNormalizer.normalize(
        BirthProfile(localDate: date, localTime: LocalTime(hour: 12, minute: 0)))
      let raw = try CalendarNormalizer.lunarDate(from: normalized)
      // Foundation 若已修復月界，仍須能往返；不能把舊錯誤永久寫成曆法規則。
      if raw.day == 0 {
        XCTAssertThrowsError(try LunarBirthResolver.lunarDate(from: normalized)) {
          XCTAssertEqual($0 as? LunarBirthValidationError, .conversionFailed)
        }
        let input = LunarBirthInput(
          date: LunarBirthDate(year: date.year, month: raw.month, day: 1),
          localTime: normalized.profile.localTime)
        XCTAssertThrowsError(try LunarBirthResolver.resolve(input)) {
          XCTAssertEqual($0 as? LunarBirthValidationError, .conversionFailed)
        }
      } else {
        let lunar = try LunarBirthResolver.lunarDate(from: normalized)
        XCTAssertEqual(
          try LunarBirthResolver.resolve(
            LunarBirthInput(date: lunar, localTime: normalized.profile.localTime)),
          normalized.profile)
      }
    }
  }

  func testSkippedCivilDayCannotProduceASilentlyShiftedProfile() {
    // Samoa 於 2011/12/30 跳過一整天；此例只檢查安全拒絕，不宣稱獨立曆法核對。
    let input = LunarBirthInput(
      date: LunarBirthDate(year: 2011, month: 12, day: 6),
      localTime: LocalTime(hour: 12, minute: 0), timeZoneIdentifier: "Pacific/Apia")
    XCTAssertThrowsError(try LunarBirthResolver.resolve(input))
  }

  private func checkOverseasSample(year: Int, month: Int, time: LocalTime, zone: String) throws {
    let profile = BirthProfile(
      localDate: LocalDate(year: year, month: month, day: 15),
      localTime: time, timeZoneIdentifier: zone)
    do {
      let normalized = try CalendarNormalizer.normalize(profile)
      let date = try LunarBirthResolver.lunarDate(from: normalized)
      let result = try LunarBirthResolver.resolve(
        LunarBirthInput(date: date, localTime: time, timeZoneIdentifier: zone))
      XCTAssertEqual(result, profile, "\(zone) \(year)/\(month) \(time)")
    } catch BirthProfileValidationError.nonexistentLocalTime {
      // 既有 normalizer 對歷史秒級位移的拒絕，並非本次證明當時存在 DST。
      XCTAssertEqual(time, LocalTime(hour: 23, minute: 30))
      XCTAssertTrue(
        (zone == "Pacific/Kiritimati" && year == 1900)
          || (zone == "Pacific/Pago_Pago" && (1900...1910).contains(year)))
      let noon = BirthProfile(
        localDate: profile.localDate, localTime: LocalTime(hour: 12, minute: 0),
        timeZoneIdentifier: zone)
      let date = try LunarBirthResolver.lunarDate(from: CalendarNormalizer.normalize(noon))
      XCTAssertThrowsError(
        try LunarBirthResolver.resolve(
          LunarBirthInput(date: date, localTime: time, timeZoneIdentifier: zone))
      ) {
        XCTAssertEqual($0 as? BirthProfileValidationError, .nonexistentLocalTime)
      }
    }
  }

  private func sweep(years: ClosedRange<Int>, expectedCount: Int) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
    var instant = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: years.lowerBound, month: 1, day: 1, hour: 12)))
    let end = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: years.upperBound + 1, month: 1, day: 1, hour: 12)))
    var seen: [LunarBirthDate: LocalDate] = [:]
    var rejected: [LocalDate] = []
    var count = 0
    while instant < end {
      let components = calendar.dateComponents([.year, .month, .day], from: instant)
      let localDate = LocalDate(
        year: try XCTUnwrap(components.year),
        month: try XCTUnwrap(components.month), day: try XCTUnwrap(components.day))
      let profile = BirthProfile(localDate: localDate, localTime: LocalTime(hour: 12, minute: 0))
      let normalized = try CalendarNormalizer.normalize(profile)
      do {
        let lunar = try LunarBirthResolver.lunarDate(from: normalized)
        let resolved = try LunarBirthResolver.resolve(
          LunarBirthInput(date: lunar, localTime: profile.localTime))
        XCTAssertNil(seen.updateValue(localDate, forKey: lunar), "農曆日期不可對應多個公曆日期：\(lunar)")
        XCTAssertEqual(resolved, profile)
      } catch LunarBirthValidationError.conversionFailed {
        // 只允許具名異常範圍；任何新失敗都必須調查，不能泛用略過。
        let key = localDate.year * 10_000 + localDate.month * 100 + localDate.day
        XCTAssertTrue(
          (20_570_928...20_571_027).contains(key) || (20_970_807...20_970_905).contains(key),
          "未記錄的 Foundation 轉換失敗：\(localDate)")
        rejected.append(localDate)
      }
      count += 1
      instant = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: instant))
    }
    XCTAssertEqual(count, expectedCount)
    XCTAssertEqual(seen.count + rejected.count, count)
    XCTAssertLessThanOrEqual(rejected.count, years.lowerBound == 1900 ? 0 : 60)
    print("農曆自我一致 sweep：\(years)，有效往返 \(seen.count)，具名月界異常安全拒絕 \(rejected.count)。")
  }
}
