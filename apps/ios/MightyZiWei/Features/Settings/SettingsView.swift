import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(AIConfigurationStore.self) private var aiConfigurationStore
  @Environment(AppLockStore.self) private var appLockStore
  @Environment(ICloudSyncCoordinator.self) private var iCloudSyncCoordinator
  @Environment(ICloudSynchronizer.self) private var iCloudSynchronizer
  @Query private var charts: [SavedChart]
  @Query private var insights: [SavedInsight]
  @Query private var deletions: [CloudDeletion]
  @AppStorage(ICloudSyncService.enabledKey) private var iCloudSyncEnabled = false
  @AppStorage("accessibility.linear-chart") private var linearChartEnabled = false
  @State private var showsICloudEnablePreview = false
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

        Section {
          Label("不使用開發者控制的伺服器", systemImage: "hand.raised")
          LabeledContent("App 鎖", value: appLockStore.isEnabled ? "已開啟" : "未開啟")
          Button {
            Task {
              let succeeded =
                appLockStore.isEnabled
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
          Toggle("同步命盤、筆記與收藏", isOn: iCloudSyncBinding)
            .disabled(iCloudSyncCoordinator.isSyncing)
            .accessibilityIdentifier("settings.icloud.toggle")

          if iCloudSyncCoordinator.isSyncing {
            DisabledReasonView("同步完成前無法關閉同步。")
          }

          if iCloudSyncEnabled {
            Label(syncStatusMessage, systemImage: syncStatusSymbol)
              .font(.footnote)
              .foregroundStyle(syncStatusIsIncomplete ? .orange : .secondary)
              .accessibilityIdentifier("settings.icloud.status")

            Button {
              Task { await synchronizeNow() }
            } label: {
              if iCloudSyncCoordinator.isSyncing {
                Label("正在同步…", systemImage: "arrow.triangle.2.circlepath")
              } else if syncStatusIsIncomplete {
                Label("重試同步", systemImage: "arrow.clockwise")
              } else {
                Label("立即同步", systemImage: "icloud.and.arrow.up")
              }
            }
            .disabled(iCloudSyncCoordinator.isSyncing)
            .accessibilityIdentifier("settings.icloud.sync")
          } else {
            Text("同步已關閉。關閉同步不會自動刪除 iCloud 已有資料。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("選擇性 iCloud 同步")
        } footer: {
          Text(
            "預設關閉。開啟後資料會存入你 Apple ID 的私人 CloudKit 資料庫；同一筆內容衝突時保留較新的修改，刪除也會同步。API 設定、API key、AI 對話與提醒通知不會同步。關閉同步只停止後續同步，不會刪除 iCloud 已有資料。Apple 會依 iCloud 條款處理資料。"
          )
        }

        Section {
          Toggle("線性命盤模式", isOn: $linearChartEnabled)
        } header: {
          Text("顯示與無障礙")
        } footer: {
          Text("將十二宮改為循序清單。VoiceOver 開啟時會自動使用線性模式。")
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
      .onAppear {
        if iCloudSyncEnabled, iCloudSyncCoordinator.status == .idle {
          iCloudSyncCoordinator.markEnabledWaiting()
        }
      }
      .alert(
        "啟用 iCloud 同步？",
        isPresented: $showsICloudEnablePreview
      ) {
        Button("啟用並同步") { enableICloudAndSynchronize() }
        Button("取消", role: .cancel) {}
      } message: {
        Text(
          "會同步：已儲存命盤、筆記、收藏與刪除紀錄。\n不會同步：API 設定、API key、AI 對話與提醒通知。同步會使用你 Apple ID 的私人 CloudKit 資料庫。")
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

  private var iCloudSyncBinding: Binding<Bool> {
    Binding(
      get: { iCloudSyncEnabled },
      set: { enabled in
        if enabled {
          guard !iCloudSyncEnabled else { return }
          showsICloudEnablePreview = true
        } else {
          iCloudSyncEnabled = false
          iCloudSyncCoordinator.markDisabled()
        }
      }
    )
  }

  private var syncStatusMessage: String {
    switch iCloudSyncCoordinator.status {
    case .idle, .waiting:
      "已啟用，等待同步。"
    case .syncing:
      "已啟用，正在同步。"
    case .synced(let result):
      "同步完成：上傳 \(result.uploadedCount) 筆、下載 \(result.downloadedCount) 筆；處理 \(result.conflictCount) 筆版本衝突。"
    case .incomplete(let failure):
      failure.message
    }
  }

  private var syncStatusSymbol: String {
    switch iCloudSyncCoordinator.status {
    case .synced:
      "checkmark.icloud"
    case .incomplete:
      "exclamationmark.icloud"
    case .syncing:
      "arrow.triangle.2.circlepath.icloud"
    case .idle, .waiting:
      "icloud"
    }
  }

  private var syncStatusIsIncomplete: Bool {
    if case .incomplete = iCloudSyncCoordinator.status { return true }
    return false
  }

  private func enableICloudAndSynchronize() {
    iCloudSyncEnabled = true
    iCloudSyncCoordinator.markEnabledWaiting()
    Task {
      await Task.yield()
      await synchronizeNow()
    }
  }

  private func synchronizeNow() async {
    guard iCloudSyncEnabled else { return }
    do {
      _ = try await iCloudSyncCoordinator.synchronize {
        let result = try await iCloudSynchronizer.sync(
          charts: charts,
          insights: insights,
          deletions: deletions,
          modelContext: modelContext
        )
        let currentCharts = try modelContext.fetch(FetchDescriptor<SavedChart>())
        PinnedChartShortcut.reconcile(charts: currentCharts)
        return result
      }
    } catch {
      // 協調器保留安全、可重試的部分同步狀態，且不關閉已啟用設定。
    }
  }
}
