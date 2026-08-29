import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]
    @State private var showsSettings = false

    private var recentCharts: [SavedChart] {
        Array(charts.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("很牛的\n紫微斗數")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("一步一步認識自己的命盤")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        BirthInputView()
                    } label: {
                        Label("排一張命盤", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home.createChart")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近命盤")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        if recentCharts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("尚未儲存命盤", systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                Text("完成排盤並儲存後，可從這裡快速繼續查看。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                            .accessibilityElement(children: .combine)
                        } else {
                            ForEach(recentCharts) { chart in
                                NavigationLink {
                                    SavedChartLoaderView(savedChart: chart)
                                } label: {
                                    SavedChartRow(chart: chart)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .cardStyle()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
        }
    }
}
