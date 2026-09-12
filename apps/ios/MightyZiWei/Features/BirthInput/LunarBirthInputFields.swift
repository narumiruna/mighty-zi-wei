import SwiftUI

struct LunarBirthInputFields: View {
  @Binding var draft: BirthInputDraft
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case year
    case month
    case day
  }

  var body: some View {
    numberField("農曆年", text: $draft.lunarYear, field: .year, placeholder: "例如 2023")
    Text("年份填寫該農曆新年所在的公曆年，不是民國年或干支年。例如 2024 農曆年從公曆 2024/02/10 開始。")
      .font(.footnote)
      .foregroundStyle(.secondary)
    numberField("農曆月", text: $draft.lunarMonth, field: .month, placeholder: "1–12")
    numberField("農曆日", text: $draft.lunarDay, field: .day, placeholder: "1–30")
    Toggle("閏月", isOn: $draft.isLeapMonth)
      .accessibilityIdentifier("birthInput.lunar.leapMonth")
    Text("只有出生紀錄標示「閏」時才開啟。轉換會保留原始月份，不先套用閏月排盤規則。")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          if focusedField != nil {
            Spacer()
            Button("完成輸入") { focusedField = nil }
              .accessibilityIdentifier("birthInput.lunar.done")
          }
        }
      }
  }

  private func numberField(
    _ title: String, text: Binding<String>, field: Field, placeholder: String
  ) -> some View {
    LabeledContent(title) {
      TextField(placeholder, text: text)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .focused($focusedField, equals: field)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier(for: field))
    }
  }

  private func identifier(for field: Field) -> String {
    switch field {
    case .year: "birthInput.lunar.year"
    case .month: "birthInput.lunar.month"
    case .day: "birthInput.lunar.day"
    }
  }
}
