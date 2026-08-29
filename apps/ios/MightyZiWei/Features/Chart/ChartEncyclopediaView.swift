import SwiftUI

struct ChartEncyclopediaView: View {
  @State private var searchText = ""

  private var entries: [ChartEncyclopediaEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return ChartEncyclopediaCatalog.allEntries }
    return ChartEncyclopediaCatalog.allEntries.filter {
      $0.title.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    List {
      if entries.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        ForEach(ChartEncyclopediaCategory.allCases, id: \.rawValue) { category in
          let categoryEntries = entries.filter { $0.category == category }
          if !categoryEntries.isEmpty {
            Section(category.title) {
              ForEach(categoryEntries) { entry in
                NavigationLink {
                  ChartEncyclopediaDetailView(entry: entry)
                } label: {
                  Text(entry.title)
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("星曜與術語小百科")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "搜尋星曜、宮位或術語")
  }
}

private struct ChartEncyclopediaDetailView: View {
  let entry: ChartEncyclopediaEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
        Text(entry.title)
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        content

        VStack(alignment: .leading, spacing: 8) {
          Label("排盤與結構規則", systemImage: "books.vertical")
            .font(.headline)
          Text(entry.placementRuleSection)
          Text("規則集：台灣正體中文三合派第 1 版")
            .foregroundStyle(.secondary)
          Text("規則狀態：已實作，待專家審核。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardStyle()

        if let explanatorySource = entry.explanatorySource {
          VStack(alignment: .leading, spacing: 8) {
            Label("說明文字來源", systemImage: "text.book.closed")
              .font(.headline)
            Text(explanatorySource)
            Text("這些說明是現行 App 編輯文案，不等同 RULESET.md 的正式排盤規則。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .cardStyle()
        }

        DisclosureGroup("技術資訊") {
          VStack(alignment: .leading, spacing: 8) {
            Text("規則集 ID：taiwan-traditional-sanhe v1")
            Text("規則狀態 ID：implemented-pending-expert-review")
            if entry.explanatorySource != nil {
              Text("文案狀態 ID：current-product-language")
            }
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
        }

        DisclaimerView(compact: true)
      }
      .padding()
    }
    .navigationTitle(entry.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private var content: some View {
    switch entry.reference {
    case .star(let star):
      let learning = ChartLearningCatalog.star(star)
      VStack(alignment: .leading, spacing: 12) {
        Text(learning.keywords.joined(separator: " · "))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
        Text(learning.summary)
        DisclosureGroup("延伸閱讀") {
          VStack(alignment: .leading, spacing: 12) {
            LabeledContent("分類", value: ChartLearningCatalog.categoryTitle(for: star.category))
            Text(learning.strengths)
            Text(learning.cautions)
          }
          .padding(.top, 8)
        }
      }
      .cardStyle()
    case .palace(let palace):
      let learning = ChartLearningCatalog.palace(palace)
      VStack(alignment: .leading, spacing: 12) {
        Text(learning.focusTitle)
          .font(.title2.bold())
        Text(learning.purpose)
        Text("宮位代表一個生活觀察面向；個人解讀仍須配合該命盤已驗證的命盤事實與已核准的解讀素材。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .cardStyle()
    case .transformation(let transformation):
      VStack(alignment: .leading, spacing: 12) {
        Text("\(transformation.displayName)是生年四化之一。")
          .font(.title2.bold())
        Text("App 依出生年天干查表，記錄哪一顆既有星曜產生此四化，以及它在命盤中的已驗證位置。")
        Text("此頁只說明排盤資料結構，不以單一四化推定事件或人生結果。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .cardStyle()
    case .sanFangSiZheng:
      VStack(alignment: .leading, spacing: 12) {
        Text("本宮、對宮與兩個三合宮合稱三方四正。")
          .font(.title2.bold())
        Text("對宮位於地支索引加六的位置；兩個三合宮位於加四與加八的位置，所有位移都以十二取餘數。")
        Text("關係位置是已驗證的命盤事實；是否能進一步解讀，仍取決於是否有對應的已核准解讀素材。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .cardStyle()
    }
  }
}

extension ChartEncyclopediaCategory {
  fileprivate var title: String {
    switch self {
    case .star: "星曜"
    case .palace: "十二宮"
    case .transformation: "生年四化"
    case .sanFangSiZheng: "術語"
    }
  }
}
