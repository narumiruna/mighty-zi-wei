import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var charts: [SavedChart]
    @State private var showsDeleteAllConfirmation = false
    @State private var errorMessage: String?

    private let modelInterpreter = FoundationModelInterpreter()

    var body: some View {
        NavigationStack {
            List {
                Section("裝置端 AI") {
                    LabeledContent {
                        Text(availabilityTitle)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Apple Intelligence", systemImage: "apple.intelligence")
                    }
                    Text(modelInterpreter.availability.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("隱私與資料") {
                    Label("不傳送資料到開發者伺服器", systemImage: "hand.raised")
                    LabeledContent("已儲存命盤", value: "\(charts.count) 張")
                    if !charts.isEmpty {
                        Button("刪除所有本機資料", systemImage: "trash", role: .destructive) {
                            showsDeleteAllConfirmation = true
                        }
                    }
                }

                Section {
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
                "刪除所有本機資料？",
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("全部刪除", role: .destructive) { deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有已儲存命盤都會刪除，而且無法復原。")
            }
            .alert("刪除未完成", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    private var availabilityTitle: String {
        switch modelInterpreter.availability {
        case .available: "可使用"
        case .unavailable: "使用基本解讀"
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
            try modelContext.delete(model: SavedChart.self)
            try modelContext.save()
        } catch {
            errorMessage = "目前無法刪除本機資料，請稍後再試。"
        }
    }
}
