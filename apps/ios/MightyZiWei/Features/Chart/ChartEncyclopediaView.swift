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
                    Label("規則來源", systemImage: "books.vertical")
                        .font(.headline)
                    Text(entry.ruleSetSection)
                    Text("規則集：taiwan-traditional-sanhe v1")
                        .foregroundStyle(.secondary)
                    Text("目前規則狀態為 implemented-pending-expert-review。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

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
                Text("宮位代表一個生活觀察面向；個人解讀仍須配合該命盤的 verified facts 與 approved seeds。")
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
                Text("關係位置是 verified fact；是否能進一步解讀，仍取決於是否有對應的 approved seed。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
    }
}

private extension ChartEncyclopediaCategory {
    var title: String {
        switch self {
        case .star: "星曜"
        case .palace: "十二宮"
        case .transformation: "生年四化"
        case .sanFangSiZheng: "術語"
        }
    }
}
