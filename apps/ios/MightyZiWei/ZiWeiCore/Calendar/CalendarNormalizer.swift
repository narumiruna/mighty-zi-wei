import Foundation

public enum BirthProfileValidationError: Error, Equatable, Sendable {
  case unsupportedCalendar
  case dateOutOfRange
  case invalidDate
  case invalidTime
  case invalidTimeZone
  case nonexistentLocalTime
  case lunarConversionFailed
}

public struct NormalizedBirth: Sendable {
  public let profile: BirthProfile
  public let instant: Date
  public let isRepeatedLocalTime: Bool

  public init(profile: BirthProfile, instant: Date, isRepeatedLocalTime: Bool) {
    self.profile = profile
    self.instant = instant
    self.isRepeatedLocalTime = isRepeatedLocalTime
  }
}

public enum CalendarNormalizer {
  public static func normalize(_ profile: BirthProfile) throws -> NormalizedBirth {
    guard profile.calendarIdentifier == .gregorian else {
      throw BirthProfileValidationError.unsupportedCalendar
    }
    guard isSupported(profile.localDate) else {
      throw BirthProfileValidationError.dateOutOfRange
    }
    guard (0...23).contains(profile.localTime.hour),
      (0...59).contains(profile.localTime.minute)
    else {
      throw BirthProfileValidationError.invalidTime
    }
    guard let timeZone = TimeZone(identifier: profile.timeZoneIdentifier) else {
      throw BirthProfileValidationError.invalidTimeZone
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone

    let date = profile.localDate
    let noonComponents = DateComponents(
      timeZone: timeZone,
      year: date.year,
      month: date.month,
      day: date.day,
      hour: 12
    )
    guard let noon = calendar.date(from: noonComponents),
      sameDate(calendar.dateComponents([.year, .month, .day], from: noon), date)
    else {
      throw BirthProfileValidationError.invalidDate
    }

    let wanted = DateComponents(
      timeZone: timeZone,
      year: date.year,
      month: date.month,
      day: date.day,
      hour: profile.localTime.hour,
      minute: profile.localTime.minute,
      second: 0
    )
    let searchStart = calendar.startOfDay(for: noon).addingTimeInterval(-1)
    guard
      let first = calendar.nextDate(
        after: searchStart,
        matching: wanted,
        matchingPolicy: .strict,
        repeatedTimePolicy: .first,
        direction: .forward
      ), matches(calendar: calendar, instant: first, profile: profile)
    else {
      throw BirthProfileValidationError.nonexistentLocalTime
    }

    let last = calendar.nextDate(
      after: searchStart,
      matching: wanted,
      matchingPolicy: .strict,
      repeatedTimePolicy: .last,
      direction: .forward
    )
    let repeated =
      last.map { $0 != first && matches(calendar: calendar, instant: $0, profile: profile) }
      ?? false
    return NormalizedBirth(profile: profile, instant: first, isRepeatedLocalTime: repeated)
  }

  public static func lunarDate(from normalizedBirth: NormalizedBirth) throws -> LunarDate {
    guard let timeZone = TimeZone(identifier: normalizedBirth.profile.timeZoneIdentifier) else {
      throw BirthProfileValidationError.invalidTimeZone
    }
    var calendar = Calendar(identifier: .chinese)
    calendar.locale = Locale(identifier: "zh_Hant_TW")
    calendar.timeZone = timeZone
    let values = calendar.dateComponents(
      [.year, .month, .day, .isLeapMonth], from: normalizedBirth.instant)
    guard let year = values.year, let month = values.month, let day = values.day else {
      throw BirthProfileValidationError.lunarConversionFailed
    }
    return LunarDate(
      cyclicalYear: year,
      month: month,
      day: day,
      isLeapMonth: values.isLeapMonth ?? false
    )
  }

  public static func hourBranch(for localTime: LocalTime) throws -> EarthlyBranch {
    guard (0...23).contains(localTime.hour), (0...59).contains(localTime.minute) else {
      throw BirthProfileValidationError.invalidTime
    }
    return EarthlyBranch(rawValue: ((localTime.hour + 1) / 2) % 12)!
  }

  private static func isSupported(_ date: LocalDate) -> Bool {
    let key = date.year * 10_000 + date.month * 100 + date.day
    return (19_000_101...20_991_231).contains(key)
  }

  private static func sameDate(_ components: DateComponents, _ date: LocalDate) -> Bool {
    components.year == date.year && components.month == date.month && components.day == date.day
  }

  private static func matches(calendar: Calendar, instant: Date, profile: BirthProfile) -> Bool {
    let values = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
    return values.year == profile.localDate.year
      && values.month == profile.localDate.month
      && values.day == profile.localDate.day
      && values.hour == profile.localTime.hour
      && values.minute == profile.localTime.minute
  }
}
