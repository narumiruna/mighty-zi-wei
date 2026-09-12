import SwiftUI

struct BirthInputView: View {
  @FocusState private var nameIsFocused: Bool
  @State private var name = ""
  @State private var draft = BirthInputDraft()
  @State private var chart: ZiWeiChart?
  @State private var validationMessage: String?
  @State private var pendingGregorianProfile: BirthProfile?
  @State private var showsRepeatedTimeConfirmation = false
  @State private var showsChart = false
  @State private var confirmation: LunarBirthConfirmation?
  @State private var confirmedRequest: LunarBirthConfirmation?
  @State private var comparisonProfile: BirthProfile?
  @State private var showsComparison = false

  var body: some View {
    Form {
      birthFields
      localTimeCheck
      if let validationMessage {
        Section {
          InlineStatusView(style: .error, message: validationMessage)
            .accessibilityLabel("輸入錯誤：\(validationMessage)")
            .accessibilityIdentifier("birthInput.error")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      }
      Section {
        Button {
          prepare(.chart)
        } label: {
          Label(draft.mode == .lunar ? "核對農曆日期" : "產生命盤", systemImage: "sparkles")
        }
        .buttonStyle(PrimaryActionStyle())
        .accessibilityIdentifier("birthInput.generate")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }
      advancedChecks
      adjacentHourSection
    }
    .appPageBackground()
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("排一張命盤")
    .navigationBarTitleDisplayMode(.inline)
    .environment(\.timeZone, selectedTimeZone)
    .environment(\.calendar, calendar)
    .navigationDestination(isPresented: $showsChart) {
      if let chart {
        ChartView(chart: chart, name: name)
      }
    }
    .navigationDestination(isPresented: $showsComparison) {
      if let comparisonProfile {
        AdjacentHourComparisonView(profile: comparisonProfile)
      }
    }
    .sheet(item: $confirmation, onDismiss: completeLunarConfirmation) { request in
      LunarBirthConfirmationView(confirmation: request) {
        confirmedRequest = request
        confirmation = nil
      }
    }
    .confirmationDialog(
      "這個時間在當地出現兩次",
      isPresented: $showsRepeatedTimeConfirmation,
      titleVisibility: .visible
    ) {
      Button("使用第一次出現的時間") {
        if let pendingGregorianProfile {
          perform(.chart, profile: pendingGregorianProfile)
        }
        pendingGregorianProfile = nil
      }
      Button("返回修改", role: .cancel) { pendingGregorianProfile = nil }
    } message: {
      Text("當地曾因夏令時間調整而重複這個鐘錶時間。v1 會採第一次出現的時間；兩次都屬相同日期與時辰，不影響本命盤星曜位置。")
    }
    .onChange(of: draft) {
      validationMessage = nil
      pendingGregorianProfile = nil
      confirmedRequest = nil
    }
  }

  private var birthFields: some View {
    Section {
      TextField("名稱或暱稱（選填）", text: $name)
        .textContentType(.nickname)
        .focused($nameIsFocused)
        .submitLabel(.done)
        .onSubmit { nameIsFocused = false }
      Picker("日期輸入方式", selection: $draft.mode) {
        ForEach(BirthInputMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("birthInput.mode")
      if draft.mode == .gregorian {
        DatePicker(
          "出生日期", selection: dateBinding, in: supportedDateRange, displayedComponents: .date
        )
        .accessibilityIdentifier("birthInput.gregorian.date")
      } else {
        LunarBirthInputFields(draft: $draft)
      }
      DatePicker("出生時間", selection: timeBinding, displayedComponents: .hourAndMinute)
        .accessibilityIdentifier("birthInput.time")
      NavigationLink {
        TimeZonePickerView(selection: $draft.timeZoneIdentifier)
      } label: {
        LabeledContent("出生地時區") {
          Text(draft.timeZoneIdentifier)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
      }
      .accessibilityIdentifier("birthInput.timeZone")
    } header: {
      Text("出生資料")
    } footer: {
      Text("請輸入出生地當時鐘錶顯示的日期與時間。兩種日期草稿分開保留，切換不換算或覆寫；不支援出生時間未知的排盤。")
    }
  }

  private var localTimeCheck: some View {
    Section {
      if let profile = try? draft.profile() {
        BirthLocalTimeCheck(profile: profile)
      } else {
        Text("請填寫有效的農曆日期與當地時間，再核對公曆轉換結果。")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("當地時間核對")
    } footer: {
      Text("命盤會依出生地當時的民用時間計算。")
    }
  }

  private var advancedChecks: some View {
    Section {
      if let profile = try? draft.profile() {
        BirthDataCheckCard(profile: profile)
      }
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
  }

  private var adjacentHourSection: some View {
    Section {
      if draft.mode == .gregorian, let profile = try? draft.profile() {
        NavigationLink {
          AdjacentHourComparisonView(profile: profile)
        } label: {
          Label("比較相鄰時辰", systemImage: "arrow.left.arrow.right")
        }
        .accessibilityIdentifier("birthInput.compareHours")
      } else {
        Button {
          prepare(.comparison)
        } label: {
          Label("比較相鄰時辰", systemImage: "arrow.left.arrow.right")
        }
        .accessibilityIdentifier("birthInput.compareHours")
      }
    } header: {
      Text("出生時間不確定？")
    } footer: {
      Text("只比較盤面位置差異，不會替你選擇或猜測出生時辰。")
    }
  }

  private var selectedTimeZone: TimeZone {
    TimeZone(identifier: draft.timeZoneIdentifier) ?? TimeZone(identifier: "Asia/Taipei")!
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
          year: draft.gregorianDate.year,
          month: draft.gregorianDate.month,
          day: draft.gregorianDate.day,
          hour: 12
        )) ?? supportedDateRange.lowerBound
    } set: { newValue in
      let components = calendar.dateComponents([.year, .month, .day], from: newValue)
      guard let year = components.year, let month = components.month, let day = components.day
      else { return }
      draft.gregorianDate = LocalDate(year: year, month: month, day: day)
    }
  }

  private var timeBinding: Binding<Date> {
    // 固定參考日期只承載時、分，避免輸入中的出生日期被 DatePicker 正規化。
    Binding {
      calendar.date(
        from: DateComponents(
          timeZone: selectedTimeZone, year: 2001, month: 1, day: 1,
          hour: draft.localTime.hour, minute: draft.localTime.minute
        )) ?? Date(timeIntervalSince1970: 978_350_400)
    } set: { newValue in
      let components = calendar.dateComponents([.hour, .minute], from: newValue)
      guard let hour = components.hour, let minute = components.minute else { return }
      draft.localTime = LocalTime(hour: hour, minute: minute)
    }
  }

  private var supportedDateRange: ClosedRange<Date> {
    let lower = calendar.date(
      from: DateComponents(timeZone: selectedTimeZone, year: 1900, month: 1, day: 1, hour: 12))!
    let upper = calendar.date(
      from: DateComponents(timeZone: selectedTimeZone, year: 2099, month: 12, day: 31, hour: 12))!
    return lower...upper
  }

  private func prepare(_ action: BirthInputAction) {
    nameIsFocused = false
    validationMessage = nil
    do {
      let profile = try draft.profile()
      let normalized = try CalendarNormalizer.normalize(profile)
      if draft.mode == .lunar {
        confirmation = LunarBirthConfirmation(
          input: try draft.lunarInput(), normalized: normalized, action: action)
      } else if normalized.isRepeatedLocalTime {
        pendingGregorianProfile = profile
        showsRepeatedTimeConfirmation = true
      } else {
        perform(action, profile: profile)
      }
    } catch {
      validationMessage = BirthInputErrorMessage.message(for: error)
    }
  }

  private func completeLunarConfirmation() {
    guard let request = confirmedRequest else { return }
    confirmedRequest = nil
    perform(request.action, profile: request.normalized.profile)
  }

  private func perform(_ action: BirthInputAction, profile: BirthProfile) {
    do {
      switch action {
      case .chart:
        chart = try ZiWeiCalculator().calculate(profile)
        showsChart = true
      case .comparison:
        comparisonProfile = profile
        showsComparison = true
      }
    } catch {
      chart = nil
      validationMessage = BirthInputErrorMessage.message(for: error)
    }
  }
}
