import SwiftUI

enum BirthInputAction {
  case chart
  case comparison
}

struct LunarBirthConfirmation: Identifiable {
  let id = UUID()
  let input: LunarBirthInput
  let normalized: NormalizedBirth
  let action: BirthInputAction
}

struct LunarBirthConfirmationView: View {
  let confirmation: LunarBirthConfirmation
  let onConfirm: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("你輸入的農曆日期") {
          Text(lunarSummary)
            .accessibilityIdentifier("birthInput.lunar.confirmation.input")
        }
        Section("將使用的公曆資料") {
          BirthLocalTimeCheck(profile: confirmation.normalized.profile)
          Text("請與出生紀錄核對。只有確認後才會使用這份公曆資料；農曆草稿與輸入模式不會永久保存。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if confirmation.normalized.isRepeatedLocalTime {
          Section("這個時間在當地出現兩次") {
            Text("當地因夏令時間調整而重複這個鐘錶時間。確認後採第一次出現的時間，與公曆入口相同。")
              .accessibilityIdentifier("birthInput.lunar.confirmation.repeatedTime")
          }
        }
        Section {
          Button(actionTitle, action: onConfirm)
            .buttonStyle(PrimaryActionStyle())
            .accessibilityIdentifier("birthInput.lunar.confirm")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      }
      .appPageBackground()
      .navigationTitle("確認農曆轉換")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("返回修改") { dismiss() }
            .accessibilityIdentifier("birthInput.lunar.cancel")
        }
      }
    }
  }

  private var lunarSummary: String {
    let date = confirmation.input.date
    return "農曆 \(date.year) 年\(date.isLeapMonth ? "閏" : "")\(date.month) 月 \(date.day) 日"
  }

  private var actionTitle: String {
    switch confirmation.action {
    case .chart:
      confirmation.normalized.isRepeatedLocalTime
        ? "確認採第一次時間並產生命盤" : "確認並產生命盤"
    case .comparison:
      confirmation.normalized.isRepeatedLocalTime
        ? "確認採第一次時間並比較時辰" : "確認並比較相鄰時辰"
    }
  }
}
