import Foundation

/// 使用者輸入的當地民用日期。
public struct LocalDate: Codable, Sendable, Hashable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }
}

/// 使用者輸入的當地牆上時間，精確至分鐘。
public struct LocalTime: Codable, Sendable, Hashable {
  public let hour: Int
  public let minute: Int

  public init(hour: Int, minute: Int) {
    self.hour = hour
    self.minute = minute
  }
}

public enum CalendarIdentifier: String, Codable, Sendable {
  case gregorian
}

/// 排盤的原始輸入；刻意不以 `Date` 取代 local civil components。
public struct BirthProfile: Codable, Sendable, Hashable {
  public let localDate: LocalDate
  public let localTime: LocalTime
  public let calendarIdentifier: CalendarIdentifier
  public let timeZoneIdentifier: String

  public init(
    localDate: LocalDate,
    localTime: LocalTime,
    calendarIdentifier: CalendarIdentifier = .gregorian,
    timeZoneIdentifier: String = "Asia/Taipei"
  ) {
    self.localDate = localDate
    self.localTime = localTime
    self.calendarIdentifier = calendarIdentifier
    self.timeZoneIdentifier = timeZoneIdentifier
  }
}
