import Foundation

enum BirthInputMode: String, CaseIterable {
  case gregorian
  case lunar

  var title: String {
    switch self {
    case .gregorian: "公曆"
    case .lunar: "農曆"
    }
  }
}

/// 草稿只存在本次輸入畫面；切換曆法不換算或覆寫另一份日期。
struct BirthInputDraft: Equatable {
  var mode: BirthInputMode = .gregorian
  var gregorianDate = LocalDate(year: 1990, month: 1, day: 1)
  var lunarYear = ""
  var lunarMonth = "1"
  var lunarDay = "1"
  var isLeapMonth = false
  var localTime = LocalTime(hour: 12, minute: 0)
  var timeZoneIdentifier = "Asia/Taipei"

  func lunarInput() throws -> LunarBirthInput {
    guard let year = Int(lunarYear), let month = Int(lunarMonth), let day = Int(lunarDay) else {
      throw LunarBirthValidationError.invalidDate
    }
    return LunarBirthInput(
      date: LunarBirthDate(year: year, month: month, day: day, isLeapMonth: isLeapMonth),
      localTime: localTime,
      timeZoneIdentifier: timeZoneIdentifier
    )
  }

  func profile() throws -> BirthProfile {
    switch mode {
    case .gregorian:
      BirthProfile(
        localDate: gregorianDate,
        localTime: localTime,
        timeZoneIdentifier: timeZoneIdentifier
      )
    case .lunar:
      try LunarBirthResolver.resolve(lunarInput())
    }
  }
}

enum BirthInputErrorMessage {
  static func message(for error: Error) -> String {
    if let error = error as? LunarBirthValidationError {
      return lunarMessage(for: error)
    }
    return switch error as? BirthProfileValidationError {
    case .dateOutOfRange:
      "出生日期換算為公曆後必須介於 1900/01/01 與 2099/12/31。"
    case .invalidDate:
      "出生日期無效，請重新選擇。"
    case .invalidTime:
      "出生時間無效，請重新選擇。"
    case .invalidTimeZone:
      "時區識別碼無效，請重新選擇。"
    case .nonexistentLocalTime:
      "這個當地時間因夏令時間或時區調整而不存在，請核對出生紀錄。草稿已保留。"
    case .lunarConversionFailed:
      "無法轉換這個日期的農曆資料。"
    case .unsupportedCalendar:
      "排盤資料必須使用已確認的公曆日期。"
    case nil:
      "目前無法產生命盤，請稍後再試。"
    }
  }

  private static func lunarMessage(for error: LunarBirthValidationError) -> String {
    switch error {
    case .invalidDate:
      "農曆日期無效，請核對年、月、日；小月沒有三十日。草稿已保留。"
    case .unavailableLeapMonth:
      "這個農曆年沒有你指定的閏月，請核對出生紀錄。草稿已保留。"
    case .conversionFailed:
      "無法完整核對這個農曆日期與當地時間，請核對出生紀錄。草稿已保留。"
    }
  }
}
