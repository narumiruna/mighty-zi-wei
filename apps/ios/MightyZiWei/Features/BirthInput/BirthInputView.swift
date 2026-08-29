import SwiftUI

struct BirthInputView: View {
  @State private var name = ""
  @State private var localDate = LocalDate(year: 1990, month: 1, day: 1)
  @State private var localTime = LocalTime(hour: 12, minute: 0)
  @State private var timeZoneIdentifier = "Asia/Taipei"
  @State private var chart: ZiWeiChart?
  @State private var validationMessage: String?
  @State private var showsRepeatedTimeConfirmation = false
  @State private var showsChart = false

  var body: some View {
    Form {
      Section {
        TextField("名稱或暱稱（選填）", text: $name)
          .textContentType(.nickname)

        DatePicker(
          "出生日期",
          selection: dateBinding,
          in: supportedDateRange,
          displayedComponents: .date
        )

        DatePicker(
          "出生時間",
          selection: timeBinding,
          displayedComponents: .hourAndMinute
        )

        NavigationLink {
          TimeZonePickerView(selection: $timeZoneIdentifier)
        } label: {
          LabeledContent("出生地時區") {
            Text(timeZoneIdentifier)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
          }
        }
      } header: {
        Text("出生資料")
      } footer: {
        Text("請輸入出生地當時鐘錶顯示的日期與時間。第一版不支援出生時間未知的排盤。")
      }

      Section {
        BirthLocalTimeCheck(profile: inputProfile)
      } header: {
        Text("當地時間核對")
      } footer: {
        Text("命盤會依出生地當時的民用時間計算。")
      }

      if let validationMessage {
        Section {
          InlineStatusView(style: .error, message: validationMessage)
            .accessibilityLabel("輸入錯誤：\(validationMessage)")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      }

      Section {
        Button {
          calculate()
        } label: {
          Text("產生命盤")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("birthInput.generate")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        BirthDataCheckCard(profile: inputProfile)

        DisclosureGroup("排盤方式") {
          VStack(alignment: .leading, spacing: 8) {
            Text("採用台灣傳統三合派 v1，並以中州派資料補充流派差異。")
            Text("排盤使用出生地當地民用時間，不使用真太陽時。")
            Text("不同流派的結果可能略有差異。")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.vertical, 6)
        }
      } header: {
        Text("進階核對")
      } footer: {
        Text("時區與夏令時間依 iOS 時區資料庫判定。")
      }

      Section {
        NavigationLink {
          AdjacentHourComparisonView(profile: inputProfile)
        } label: {
          Label("比較相鄰時辰", systemImage: "arrow.left.arrow.right")
        }
        .accessibilityIdentifier("birthInput.compareHours")
      } header: {
        Text("出生時間不確定？")
      } footer: {
        Text("只比較盤面位置差異，不會替你選擇或猜測出生時辰。")
      }
    }
    .navigationTitle("排一張命盤")
    .navigationBarTitleDisplayMode(.inline)
    .environment(\.timeZone, selectedTimeZone)
    .navigationDestination(isPresented: $showsChart) {
      if let chart {
        ChartView(chart: chart, name: name)
      }
    }
    .confirmationDialog(
      "這個時間在當地出現兩次",
      isPresented: $showsRepeatedTimeConfirmation,
      titleVisibility: .visible
    ) {
      Button("使用第一次出現的時間") {
        finishCalculation()
      }
      Button("返回修改", role: .cancel) {}
    } message: {
      Text("當地曾因夏令時間調整而重複這個鐘錶時間。v1 會採第一次出現的時間；兩次都屬相同日期與時辰，不影響本命盤星曜位置。")
    }
  }

  private var inputProfile: BirthProfile {
    BirthProfile(
      localDate: localDate,
      localTime: localTime,
      timeZoneIdentifier: timeZoneIdentifier
    )
  }

  private var selectedTimeZone: TimeZone {
    TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Taipei")!
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "zh-Hant-TW")
    calendar.timeZone = selectedTimeZone
    return calendar
  }

  private var dateBinding: Binding<Date> {
    Binding {
      calendar.date(
        from: DateComponents(
          timeZone: selectedTimeZone,
          year: localDate.year,
          month: localDate.month,
          day: localDate.day,
          hour: 12
        )) ?? supportedDateRange.lowerBound
    } set: { newValue in
      let components = calendar.dateComponents([.year, .month, .day], from: newValue)
      guard let year = components.year, let month = components.month, let day = components.day
      else { return }
      localDate = LocalDate(year: year, month: month, day: day)
      validationMessage = nil
    }
  }

  private var timeBinding: Binding<Date> {
    Binding {
      calendar.date(
        from: DateComponents(
          timeZone: selectedTimeZone,
          year: 2001,
          month: 1,
          day: 1,
          hour: localTime.hour,
          minute: localTime.minute
        )) ?? Date(timeIntervalSince1970: 978_350_400)
    } set: { newValue in
      let components = calendar.dateComponents([.hour, .minute], from: newValue)
      guard let hour = components.hour, let minute = components.minute else { return }
      localTime = LocalTime(hour: hour, minute: minute)
      validationMessage = nil
    }
  }

  private var supportedDateRange: ClosedRange<Date> {
    let lower = calendar.date(
      from: DateComponents(
        timeZone: selectedTimeZone,
        year: 1900,
        month: 1,
        day: 1,
        hour: 12
      ))!
    let upper = calendar.date(
      from: DateComponents(
        timeZone: selectedTimeZone,
        year: 2099,
        month: 12,
        day: 31,
        hour: 12
      ))!
    return lower...upper
  }

  private func calculate() {
    validationMessage = nil
    do {
      let normalized = try ZiWeiCalculator().normalize(inputProfile)
      chart = try ZiWeiCalculator().calculate(inputProfile)
      if normalized.isRepeatedLocalTime {
        showsRepeatedTimeConfirmation = true
      } else {
        finishCalculation()
      }
    } catch {
      chart = nil
      validationMessage = message(for: error)
    }
  }

  private func finishCalculation() {
    guard chart != nil else { return }
    showsChart = true
  }

  private func message(for error: Error) -> String {
    switch error as? BirthProfileValidationError {
    case .dateOutOfRange:
      "出生日期必須介於 1900/01/01 與 2099/12/31。"
    case .invalidDate:
      "出生日期無效，請重新選擇。"
    case .invalidTime:
      "出生時間無效，請重新選擇。"
    case .invalidTimeZone:
      "時區識別碼無效，請重新選擇。"
    case .nonexistentLocalTime:
      "這個當地時間因夏令時間調整而不存在，請核對出生紀錄。"
    case .lunarConversionFailed:
      "無法轉換這個日期的農曆資料。"
    case .unsupportedCalendar:
      "第一版只支援公曆出生日期。"
    case nil:
      "目前無法產生命盤，請稍後再試。"
    }
  }
}

private struct BirthLocalTimeCheck: View {
  let profile: BirthProfile

  private var localInputText: String {
    String(
      format: "%04d/%02d/%02d　%02d:%02d",
      profile.localDate.year,
      profile.localDate.month,
      profile.localDate.day,
      profile.localTime.hour,
      profile.localTime.minute
    )
  }

  private var offsetText: String? {
    guard let normalized = try? CalendarNormalizer.normalize(profile),
      let timeZone = TimeZone(identifier: profile.timeZoneIdentifier)
    else {
      return nil
    }
    let seconds = timeZone.secondsFromGMT(for: normalized.instant)
    let sign = seconds >= 0 ? "+" : "−"
    let absolute = abs(seconds)
    return String(format: "UTC%@%02d:%02d", sign, absolute / 3_600, absolute % 3_600 / 60)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("將採用出生地當地時間", systemImage: "clock")
        .font(.subheadline.weight(.semibold))
      Text(localInputText)
        .font(.headline.monospacedDigit())
      Text(timeZoneSummary)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("birthInput.localTimeCheck")
  }

  private var timeZoneSummary: String {
    if let offsetText {
      return "\(profile.timeZoneIdentifier)（\(offsetText)）"
    }
    return "\(profile.timeZoneIdentifier)（請確認此時間是否存在）"
  }
}

private struct BirthDataCheckCard: View {
  let profile: BirthProfile

  private var normalized: NormalizedBirth? {
    try? CalendarNormalizer.normalize(profile)
  }

  private var localInputText: String {
    String(
      format: "%04d/%02d/%02d　%02d:%02d",
      profile.localDate.year,
      profile.localDate.month,
      profile.localDate.day,
      profile.localTime.hour,
      profile.localTime.minute
    )
  }

  private var offsetText: String {
    guard let normalized,
      let timeZone = TimeZone(identifier: profile.timeZoneIdentifier)
    else {
      return "無法判定"
    }
    let seconds = timeZone.secondsFromGMT(for: normalized.instant)
    let sign = seconds >= 0 ? "+" : "−"
    let absolute = abs(seconds)
    return String(format: "UTC%@%02d:%02d", sign, absolute / 3_600, absolute % 3_600 / 60)
  }

  private var daylightSavingText: String {
    guard let normalized,
      let timeZone = TimeZone(identifier: profile.timeZoneIdentifier)
    else {
      return "無法判定"
    }
    if normalized.isRepeatedLocalTime {
      return "曾重複出現（v1 採第一次）"
    }
    return timeZone.isDaylightSavingTime(for: normalized.instant)
      ? "當時使用夏令時間"
      : "當時未使用夏令時間"
  }

  private var hourRuleText: String {
    guard let branch = try? CalendarNormalizer.hourBranch(for: profile.localTime) else {
      return "無法判定"
    }
    if profile.localTime.hour == 23 {
      return "\(branch.displayName)時；23:00 不提前換日"
    }
    return "\(branch.displayName)時；民用午夜換日"
  }

  var body: some View {
    DisclosureGroup("核對時區與排盤規則") {
      VStack(alignment: .leading, spacing: 10) {
        LabeledContent("當地日期時間", value: localInputText)
        LabeledContent("IANA 時區", value: profile.timeZoneIdentifier)
        LabeledContent("歷史 UTC 位移", value: offsetText)
        LabeledContent("夏令時間", value: daylightSavingText)
        LabeledContent("時辰與換日", value: hourRuleText)
        LabeledContent(
          "規則集",
          value:
            "\(RuleSetIdentity.taiwanTraditionalSanheV1.id) v\(RuleSetIdentity.taiwanTraditionalSanheV1.version)"
        )
        Text("本命盤使用出生地當地民用時間，不轉成台灣時間，也不使用真太陽時。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 8)
    }
    .accessibilityIdentifier("birthInput.auditCard")
  }
}
