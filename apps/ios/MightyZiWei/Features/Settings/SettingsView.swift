import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AIConfigurationStore.self) private var aiConfigurationStore
    @Environment(AppLockStore.self) private var appLockStore
    @Query private var charts: [SavedChart]
    @Query private var insights: [SavedInsight]
    @Query private var deletions: [CloudDeletion]
    @AppStorage(ICloudSyncService.enabledKey) private var iCloudSyncEnabled = false
    @AppStorage("accessibility.linear-chart") private var linearChartEnabled = false
    @State private var showsDeleteAllConfirmation = false
    @State private var errorMessage: String?
    @State private var syncMessage: String?
    @State private var isSyncing = false

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

                Section {
                    Label("不使用開發者控制的伺服器", systemImage: "hand.raised")
                    LabeledContent("App 鎖", value: appLockStore.isEnabled ? "已開啟" : "未開啟")
                    Button {
                        Task {
                            let succeeded = appLockStore.isEnabled
                                ? await appLockStore.disable()
                                : await appLockStore.enable()
                            if !succeeded, let message = appLockStore.errorMessage {
                                errorMessage = message
                            }
                        }
                    } label: {
                        Label(
                            appLockStore.isEnabled ? "關閉 Face ID／密碼鎖" : "開啟 Face ID／密碼鎖",
                            systemImage: appLockStore.isEnabled ? "lock.open" : "faceid"
                        )
                    }
                } header: {
                    Text("隱私與 App 鎖")
                } footer: {
                    Text("開啟後，App 會使用 Face ID、Touch ID 或裝置密碼解鎖；切到背景時立即鎖定並遮住畫面。")
                }

                Section {
                    Toggle("同步命盤、筆記與收藏", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, enabled in
                            if enabled { Task { await synchronizeNow() } }
                        }
                    if iCloudSyncEnabled {
                        Button {
                            Task { await synchronizeNow() }
                        } label: {
                            if isSyncing {
                                Label("正在同步…", systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label("立即同步", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        .disabled(isSyncing)
                    }
                    if let syncMessage {
                        Text(syncMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("選擇性 iCloud 同步")
                } footer: {
                    Text("預設關閉。開啟後資料會存入你 Apple ID 的私人 CloudKit 資料庫；同一筆內容衝突時保留較新的修改，刪除也會同步。API 設定、API key、AI 對話與提醒通知不會同步。Apple 會依 iCloud 條款處理資料。")
                }

                Section {
                    Toggle("線性命盤模式", isOn: $linearChartEnabled)
                } header: {
                    Text("顯示與無障礙")
                } footer: {
                    Text("將十二宮改為循序清單。VoiceOver 開啟時會自動使用線性模式。")
                }

                Section("本機資料") {
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
            .alert("操作未完成", isPresented: errorIsPresented) {
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

    private func synchronizeNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await ICloudSyncService().sync(
                charts: charts,
                insights: insights,
                deletions: deletions,
                modelContext: modelContext
            )
            let currentCharts = try modelContext.fetch(FetchDescriptor<SavedChart>())
            let defaults = UserDefaults(suiteName: ReviewReminderScheduler.sharedDefaultsSuite)
            if let pinned = currentCharts.first(where: \.isPinned) {
                defaults?.set(pinned.id.uuidString, forKey: "shortcuts.pinned-chart-id")
            } else {
                defaults?.removeObject(forKey: "shortcuts.pinned-chart-id")
            }
            syncMessage = "同步完成：上傳 \(result.uploadedCount) 筆、下載 \(result.downloadedCount) 筆；處理 \(result.conflictCount) 筆版本衝突。"
        } catch let error as LocalizedError {
            iCloudSyncEnabled = false
            errorMessage = error.errorDescription ?? "目前無法完成 iCloud 同步。"
        } catch {
            iCloudSyncEnabled = false
            errorMessage = "目前無法完成 iCloud 同步。"
        }
    }

    private func deleteAll() {
        do {
            charts.forEach {
                ICloudSyncService.recordDeletion(
                    entityID: $0.id,
                    entityType: "SavedChart",
                    modelContext: modelContext
                )
            }
            insights.forEach {
                ICloudSyncService.recordDeletion(
                    entityID: $0.id,
                    entityType: "SavedInsight",
                    modelContext: modelContext
                )
                ReviewReminderScheduler().cancel(identifier: $0.reminderIdentifier)
            }
            try modelContext.delete(model: SavedInsight.self)
            try modelContext.delete(model: SavedChart.self)
            UserDefaults(suiteName: ReviewReminderScheduler.sharedDefaultsSuite)?
                .removeObject(forKey: "shortcuts.pinned-chart-id")
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "目前無法刪除已儲存命盤，請稍後再試。"
        }
    }
}
