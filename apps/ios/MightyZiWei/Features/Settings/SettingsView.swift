import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
    @Query private var charts: [SavedChart]
    @Query private var insights: [SavedInsight]
    @State private var showsDeleteAllConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("AI API") {
                    LabeledContent {
                        Text(aiConfigurationStore.isConfigured ? "已設定" : "尚未設定")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("OpenAI 相容 API", systemImage: "cloud")
                    }
                    NavigationLink("設定 API") {
                        AIConfigurationView()
                    }
                }

                Section("隱私與資料") {
                    Label("不使用開發者控制的伺服器", systemImage: "hand.raised")
                    LabeledContent("已儲存命盤", value: "\(charts.count) 張")
                    if !charts.isEmpty {
                        Button("刪除所有已儲存命盤", systemImage: "trash", role: .destructive) {
                            showsDeleteAllConfirmation = true
                        }
                    }
                }

                Section("學習") {
                    NavigationLink("星曜與術語小百科") {
                        ChartEncyclopediaView()
                    }
                    NavigationLink("關於與排盤說明") {
                        AboutView()
                    }
                }

                Section {
                    DisclaimerView()
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "刪除所有已儲存命盤？",
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("刪除所有命盤、筆記與收藏", role: .destructive) { deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(SavedInsightDeletionSummary(insights: insights).message)
            }
            .alert("刪除未完成", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func deleteAll() {
        do {
            try modelContext.delete(model: SavedInsight.self)
            try modelContext.delete(model: SavedChart.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "目前無法刪除已儲存命盤，請稍後再試。"
        }
    }
}
