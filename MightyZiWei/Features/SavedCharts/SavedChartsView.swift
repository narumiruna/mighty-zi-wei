import SwiftData
import SwiftUI

struct SavedChartsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]

    @State private var chartToRename: SavedChart?
    @State private var proposedName = ""
    @State private var showsDeleteAllConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if charts.isEmpty {
                    EmptyStateView(
                        symbol: "rectangle.stack",
                        title: "還沒有已儲存命盤",
                        message: "完成排盤後，點選右上角的儲存按鈕即可保留命盤。"
                    )
                } else {
                    List {
                        ForEach(charts) { chart in
                            NavigationLink {
                                SavedChartLoaderView(savedChart: chart)
                            } label: {
                                SavedChartRow(chart: chart)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    chartToRename = chart
                                    proposedName = chart.name
                                } label: {
                                    Label("重新命名", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(chart)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("已儲存命盤")
            .toolbar {
                if !charts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("刪除所有已儲存命盤", systemImage: "trash", role: .destructive) {
                                showsDeleteAllConfirmation = true
                            }
                        } label: {
                            Label("更多操作", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("重新命名", isPresented: renameIsPresented) {
                TextField("命盤名稱", text: $proposedName)
                Button("取消", role: .cancel) {}
                Button("儲存") { rename() }
            } message: {
                Text("名稱只會儲存在本機。")
            }
            .confirmationDialog(
                "刪除所有已儲存命盤？",
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("全部刪除", role: .destructive) { deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這個動作無法復原。")
            }
            .alert("操作未完成", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { chartToRename != nil },
            set: { if !$0 { chartToRename = nil } }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func rename() {
        guard let chartToRename else { return }
        do {
            try chartToRename.rename(to: proposedName)
            try modelContext.save()
            self.chartToRename = nil
        } catch {
            errorMessage = "無法重新命名命盤。"
        }
    }

    private func delete(_ chart: SavedChart) {
        modelContext.delete(chart)
        saveChanges(errorText: "無法刪除命盤。")
    }

    private func deleteAll() {
        do {
            try modelContext.delete(model: SavedChart.self)
            try modelContext.save()
        } catch {
            errorMessage = "無法刪除所有已儲存命盤。"
        }
    }

    private func saveChanges(errorText: String) {
        do {
            try modelContext.save()
        } catch {
            errorMessage = errorText
        }
    }
}

struct SavedChartRow: View {
    let chart: SavedChart

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(chart.name)
                .font(.headline)
            if let profile = try? chart.birthProfile() {
                Text(dateText(profile))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(profile.timeZoneIdentifier)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func dateText(_ profile: BirthProfile) -> String {
        let date = profile.localDate
        let time = profile.localTime
        return String(format: "%04d/%02d/%02d　%02d:%02d", date.year, date.month, date.day, time.hour, time.minute)
    }
}

struct SavedChartLoaderView: View {
    let savedChart: SavedChart
    @Environment(\.modelContext) private var modelContext
    @State private var chart: ZiWeiChart?
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let chart {
                ChartView(
                    chart: chart,
                    name: savedChart.name,
                    allowsSaving: false,
                    notice: notice
                )
            } else if let errorMessage {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "無法開啟命盤",
                    message: errorMessage
                )
            } else {
                ProgressView("正在準備命盤…")
            }
        }
        .task { load() }
    }

    private func load() {
        let current = RuleSetIdentity.taiwanTraditionalSanheV1
        let needsRecalculation = savedChart.ruleSetID != current.id
            || savedChart.ruleSetVersion != current.version
            || savedChart.appSchemaVersion != SavedChart.schemaVersion
        do {
            chart = try savedChart.resolvedChart()
            if needsRecalculation {
                notice = "這張命盤已依目前規則重新計算，結果可能與舊版不同。"
                try modelContext.save()
            }
        } catch {
            errorMessage = "本機資料可能已損毀，請刪除這張命盤後重新建立。"
        }
    }
}
