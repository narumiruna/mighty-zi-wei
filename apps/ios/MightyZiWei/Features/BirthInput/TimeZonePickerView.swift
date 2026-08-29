import SwiftUI

struct TimeZonePickerView: View {
  @Binding var selection: String
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""

  private var identifiers: [String] {
    let all = TimeZone.knownTimeZoneIdentifiers
    guard !searchText.isEmpty else { return all }
    return all.filter {
      $0.localizedStandardContains(searchText)
        || displayName(for: $0).localizedStandardContains(searchText)
    }
  }

  var body: some View {
    List(identifiers, id: \.self) { identifier in
      Button {
        selection = identifier
        dismiss()
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(identifier)
              .foregroundStyle(.primary)
            Text(displayName(for: identifier))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if identifier == selection {
            Image(systemName: "checkmark")
              .fontWeight(.semibold)
              .accessibilityLabel("已選取")
          }
        }
      }
      .accessibilityLabel("\(identifier)，\(displayName(for: identifier))")
    }
    .navigationTitle("出生地時區")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "搜尋城市或時區")
    .overlay {
      if identifiers.isEmpty {
        EmptyStateView(
          symbol: "globe",
          title: "找不到時區",
          message: "請改用城市英文名稱或 IANA 時區識別碼搜尋。"
        )
      }
    }
  }

  private func displayName(for identifier: String) -> String {
    guard let timeZone = TimeZone(identifier: identifier) else { return identifier }
    return timeZone.localizedName(
      for: .standard,
      locale: Locale(identifier: "zh-Hant-TW")
    ) ?? identifier
  }
}
