import SwiftUI

struct BirthLocalTimeCheck: View {
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
        .foregroundStyle(.tint)
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

struct BirthDataCheckCard: View {
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
