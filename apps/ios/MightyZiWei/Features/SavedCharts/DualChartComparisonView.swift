import SwiftData
import SwiftUI

struct SavedChartPickerLabelBuilder: Sendable {
    static func make(name: String, profile: BirthProfile?) -> String {
        guard let profile else { return name }
        let date = profile.localDate
        let time = profile.localTime
        let birthDateTime = String(
            format: "%04d/%02d/%02d %02d:%02d",
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute
        )
        return "\(name)・\(birthDateTime)"
    }
}

struct DualChartComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]
    @State private var firstID: UUID?
    @State private var secondID: UUID?
    @State private var reference: DualChartInteractionReference?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("雙人互動參考")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("並列兩張命盤的既有位置事實，不判定適配度或關係結果。")
                        .foregroundStyle(.secondary)
                }

                if charts.count < 2 {
                    EmptyStateView(
                        symbol: "person.2",
                        title: "需要兩張已儲存命盤",
                        message: "先儲存另一張命盤，才能進行並列比較。"
                    )
                } else {
                    selectors

                    if let reference {
                        ForEach(reference.comparisons, id: \.palaceKind) { comparison in
                            PalaceInteractionComparisonView(
                                comparison: comparison,
                                firstName: firstChart?.name ?? "第一張命盤",
                                secondName: secondChart?.name ?? "第二張命盤"
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("閱讀限制", systemImage: "info.circle")
                                .font(.headline)
                            ForEach(reference.limitations, id: \.self) { limitation in
                                Text("• \(limitation)")
                                    .font(.footnote)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .cardStyle()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("雙人互動參考")
        .navigationBarTitleDisplayMode(.inline)
        .task { prepareDefaults() }
        .onChange(of: firstID) { _, _ in load() }
        .onChange(of: secondID) { _, _ in load() }
        .alert("無法比較命盤", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var selectors: some View {
        VStack(spacing: 12) {
            chartPicker(title: "第一張命盤", selection: $firstID)
            chartPicker(title: "第二張命盤", selection: $secondID)
        }
        .cardStyle()
    }

    private func chartPicker(title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(charts) { chart in
                Text(SavedChartPickerLabelBuilder.make(
                    name: chart.name,
                    profile: try? chart.birthProfile()
                ))
                .tag(Optional(chart.id))
            }
        }
        .pickerStyle(.menu)
    }

    private var firstChart: SavedChart? {
        charts.first { $0.id == firstID }
    }

    private var secondChart: SavedChart? {
        charts.first { $0.id == secondID }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func prepareDefaults() {
        guard charts.count >= 2 else { return }
        if firstID == nil { firstID = charts[0].id }
        if secondID == nil { secondID = charts[1].id }
        load()
    }

    private func load() {
        guard let firstChart, let secondChart else {
            reference = nil
            return
        }
        guard firstChart.id != secondChart.id else {
            reference = nil
            errorMessage = "請選擇兩張不同的命盤。"
            return
        }
        do {
            reference = DualChartInteractionReferenceBuilder().make(
                firstChart: try firstChart.resolvedChart(),
                secondChart: try secondChart.resolvedChart()
            )
            try modelContext.save()
        } catch {
            reference = nil
            errorMessage = "其中一張本機命盤無法讀取，請重新建立後再試。"
        }
    }
}

private struct PalaceInteractionComparisonView: View {
    let comparison: InteractionPalaceComparison
    let firstName: String
    let secondName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(comparison.palaceKind.displayName)
                .font(.title2.bold())
            facts(name: firstName, value: comparison.firstChart)
            Divider()
            facts(name: secondName, value: comparison.secondChart)
        }
        .cardStyle()
    }

    private func facts(name: String, value: InteractionPalaceFacts?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)
            if let value {
                Text("宮位干支：\(value.palace.stemBranch.displayName)")
                Text(
                    "主星：\(value.mainStars.isEmpty ? "無主星" : value.mainStars.map(\.star.displayName).joined(separator: "、"))"
                )
            } else {
                Text("缺少可比較資料")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
