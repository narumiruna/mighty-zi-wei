import Foundation

/// 年份是該農曆新年所在的公曆年，不是六十年循環值。
public struct LunarBirthDate: Codable, Hashable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int
  public let isLeapMonth: Bool

  public init(year: Int, month: Int, day: Int, isLeapMonth: Bool = false) {
    self.year = year
    self.month = month
    self.day = day
    self.isLeapMonth = isLeapMonth
  }
}

/// 僅供輸入轉換，不作為已儲存命盤的資料格式。
public struct LunarBirthInput: Hashable, Sendable {
  public let date: LunarBirthDate
  public let localTime: LocalTime
  public let timeZoneIdentifier: String

  public init(
    date: LunarBirthDate,
    localTime: LocalTime,
    timeZoneIdentifier: String = "Asia/Taipei"
  ) {
    self.date = date
    self.localTime = localTime
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}

public enum LunarBirthValidationError: Error, Equatable, Sendable {
  case invalidDate
  case unavailableLeapMonth
  case conversionFailed
}

public enum LunarBirthResolver {
  /// 回傳可交給既有排盤器的公曆資料；呼叫端仍須請使用者確認。
  public static func resolve(_ input: LunarBirthInput) throws -> BirthProfile {
    // 下界可能屬於 1899 農曆年；最後仍依公曆結果判定支援範圍。
    guard (1899...2099).contains(input.date.year) else {
      throw BirthProfileValidationError.dateOutOfRange
    }
    guard (1...12).contains(input.date.month), (1...30).contains(input.date.day) else {
      throw LunarBirthValidationError.invalidDate
    }
    guard (0...23).contains(input.localTime.hour), (0...59).contains(input.localTime.minute) else {
      throw BirthProfileValidationError.invalidTime
    }
    let calendars = try calendars(in: input.timeZoneIdentifier)
    let gregorian = calendars.gregorian
    let lunar = calendars.lunar

    // 七月必定已過該年農曆新年，以同一出生地時區取得 era + 循環年。
    // 不硬編 Foundation 的紀元，也不把使用者的絕對年直接填入 .chinese.year。
    guard
      let anchor = gregorian.date(
        from: DateComponents(year: input.date.year, month: 7, day: 1, hour: 12))
    else {
      throw LunarBirthValidationError.conversionFailed
    }
    var wanted = lunar.dateComponents([.era, .year], from: anchor)
    wanted.month = input.date.month
    wanted.day = 1
    wanted.isLeapMonth = input.date.isLeapMonth
    wanted.hour = 12
    guard let monthStart = lunar.date(from: wanted),
      matches(
        wanted, lunar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: monthStart))
    else {
      throw input.date.isLeapMonth
        ? LunarBirthValidationError.unavailableLeapMonth : LunarBirthValidationError.invalidDate
    }
    // 部分 Foundation 版本曾在月界回傳「第 0 日」。若月首的前一天仍屬同月，
    // 該月與民用日期無法完整核對，整月拒絕，不把偏移一天的結果當成有效轉換。
    guard let previousDay = gregorian.date(byAdding: .day, value: -1, to: monthStart) else {
      throw LunarBirthValidationError.conversionFailed
    }
    let previous = lunar.dateComponents(
      [.era, .year, .month, .day, .isLeapMonth], from: previousDay)
    guard let previousDayNumber = previous.day, (1...30).contains(previousDayNumber),
      previous.era != wanted.era || previous.year != wanted.year
        || previous.month != wanted.month || previous.isLeapMonth != wanted.isLeapMonth
    else {
      throw LunarBirthValidationError.conversionFailed
    }
    wanted.day = input.date.day
    guard let candidate = lunar.date(from: wanted),
      matches(
        wanted, lunar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: candidate))
    else {
      throw LunarBirthValidationError.invalidDate
    }
    let values = gregorian.dateComponents([.year, .month, .day], from: candidate)
    guard let year = values.year, let month = values.month, let day = values.day else {
      throw LunarBirthValidationError.conversionFailed
    }
    let profile = BirthProfile(
      localDate: LocalDate(year: year, month: month, day: day),
      localTime: input.localTime,
      timeZoneIdentifier: input.timeZoneIdentifier
    )
    // 中午只用來定位日期；必須以完整當地時間再核對，拒絕 DST 缺口。
    // 重複時間完全沿用既有 normalizer 的第一次出現政策。
    let normalized = try CalendarNormalizer.normalize(profile)
    guard try lunarDate(from: normalized) == input.date else {
      throw LunarBirthValidationError.conversionFailed
    }
    return profile
  }

  /// 以既有完整民用時間正規化結果取得絕對農曆日期。
  public static func lunarDate(from normalized: NormalizedBirth) throws -> LunarBirthDate {
    let calendars = try calendars(in: normalized.profile.timeZoneIdentifier)
    let values = calendars.lunar.dateComponents(
      [.month, .day, .isLeapMonth], from: normalized.instant)
    guard let month = values.month, let day = values.day,
      (1...12).contains(month), (1...30).contains(day),
      let yearInterval = calendars.lunar.dateInterval(of: .year, for: normalized.instant)
    else {
      throw LunarBirthValidationError.conversionFailed
    }
    let year = calendars.gregorian.component(.year, from: yearInterval.start)
    return LunarBirthDate(
      year: year, month: month, day: day, isLeapMonth: values.isLeapMonth ?? false)
  }

  private static func calendars(in identifier: String) throws -> (
    gregorian: Calendar, lunar: Calendar
  ) {
    guard let timeZone = TimeZone(identifier: identifier) else {
      throw BirthProfileValidationError.invalidTimeZone
    }
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.locale = Locale(identifier: "en_US_POSIX")
    gregorian.timeZone = timeZone
    var lunar = Calendar(identifier: .chinese)
    lunar.locale = Locale(identifier: "zh_Hant_TW")
    lunar.timeZone = timeZone
    return (gregorian, lunar)
  }

  private static func matches(_ wanted: DateComponents, _ actual: DateComponents) -> Bool {
    wanted.era == actual.era && wanted.year == actual.year
      && wanted.month == actual.month && wanted.day == actual.day
      && wanted.isLeapMonth == (actual.isLeapMonth ?? false)
  }
}
