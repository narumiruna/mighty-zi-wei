import SwiftUI

struct AIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIConfigurationCommitCoordinator.self) private var commitCoordinator

    @State private var endpoint = AIConfigurationStore.defaultEndpoint
    @State private var model = ""
    @State private var apiKey = ""
    @State private var maximumAnswerCharacters = AIConfigurationStore.defaultMaximumAnswerCharacters
    @State private var monthlyLimit = 50
    @State private var errorMessage: String?
    @State private var showsClearConfirmation = false
    @State private var showsRecoveryDiscardConfirmation = false
    @State private var hasLoaded = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var testTask: Task<Void, Never>?
    @State private var copiedDiagnostic = false

    var body: some View {
        Form {
            if let recoveryMessage = commitCoordinator.recoveryMessage {
                Section {
                    Label(recoveryMessage, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.red)
                    Button("重新載入並檢查欄位") {
                        loadDraft(force: true)
                    }
                    .accessibilityIdentifier("ai.recover")
                    Button("移除無法讀取的設定", role: .destructive) {
                        showsRecoveryDiscardConfirmation = true
                    }
                    .accessibilityIdentifier("ai.discardRecovery")
                } header: {
                    Text("需要重新設定")
                } footer: {
                    Text("重新載入後，請檢查 endpoint、model 與 API key，再按「儲存 API 設定」才會重新啟用 AI。")
                }
            }

            Section {
                TextField("API Base URL 或完整 Responses URL", text: $endpoint, axis: .vertical)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.endpoint")

                TextField("Model identifier", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.model")

                SecureField("API key（可留空）", text: $apiKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ai.apiKey")
            } header: {
                Text("Responses API")
            } footer: {
                Text("URL 必須使用 HTTPS。若網址未以 /responses 結尾，App 會自動補上。API key 只儲存在本機 Keychain，不會同步到其他裝置。")
            }
            .disabled(isTesting)

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                        }
                        Text(isTesting ? "正在測試…" : "測試目前欄位")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
                .accessibilityIdentifier("ai.test")

                if let testMessage {
                    Label(
                        testMessage,
                        systemImage: testSucceeded ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(testSucceeded ? .green : .red)
                    .accessibilityIdentifier("ai.testStatus")
                }
            } footer: {
                Text("測試只使用目前畫面中的草稿，不會儲存欄位。測試會發出一個小型 Responses API request，可能產生少量 token 費用，但不會傳送命盤資料。")
            }

            Section {
                Picker("每次回答長度", selection: $maximumAnswerCharacters) {
                    Text("精簡（600 字）").tag(600)
                    Text("標準（1,200 字）").tag(1_200)
                    Text("詳細（2,000 字）").tag(2_000)
                }
                Picker("每月請求上限", selection: $monthlyLimit) {
                    Text("10 次").tag(10)
                    Text("25 次").tag(25)
                    Text("50 次").tag(50)
                    Text("100 次").tag(100)
                    Text("不設上限").tag(0)
                }
                LabeledContent("本月已送出", value: "\(commitCoordinator.currentMonthCount) 次")
                if let remaining = commitCoordinator.remainingRequests(for: monthlyLimit) {
                    LabeledContent("套用後本月剩餘", value: "\(remaining) 次")
                }
            } header: {
                Text("回答與費用保護")
            } footer: {
                Text("回答長度與每月上限也會等到儲存後才套用。請求上限由 App 在送出前檢查；實際 token 與費用仍以第三方服務紀錄為準。")
            }
            .disabled(isTesting)

            if let diagnostic = commitCoordinator.lastDiagnostic {
                Section {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        ClipboardWriter.copy(diagnostic)
                        copiedDiagnostic = true
                    } label: {
                        Label(copiedDiagnostic ? "已複製" : "一鍵複製診斷", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("ai.copyDiagnostic")
                } header: {
                    Text("安全診斷")
                } footer: {
                    Text("診斷不包含 API key、endpoint、prompt、命盤或服務回應內容。")
                }
            }

            Section("資料與費用") {
                Text("只有在你主動要求雲端整理時，App 才會傳送已驗證的命盤事實與基礎解讀。")
                Text("資料會傳送到你設定的第三方服務，並受該服務的隱私政策、保存方式與費用規則約束。")
                Text("App 不會主動把姓名、原始出生日期或出生時間加入 prompt；你在問題中輸入的內容仍會傳送。API key 只會作為授權 header 傳送到你設定的 endpoint。")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("儲存 API 設定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting)
                .accessibilityIdentifier("ai.save")
            }

            if commitCoordinator.hasStoredValues {
                Section {
                    Button("清除 API 設定", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .disabled(isTesting)
                    .accessibilityIdentifier("ai.clear")
                }
            }
        }
        .navigationTitle("AI API 設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDraft(force: false) }
        .onDisappear {
            testTask?.cancel()
        }
        .onChange(of: endpoint) { _, _ in resetTestStatus() }
        .onChange(of: model) { _, _ in resetTestStatus() }
        .onChange(of: apiKey) { _, _ in resetTestStatus() }
        .onChange(of: maximumAnswerCharacters) { _, _ in resetTestStatus() }
        .onChange(of: monthlyLimit) { _, _ in resetTestStatus() }
        .alert(
            "移除無法讀取的 API 設定？",
            isPresented: $showsRecoveryDiscardConfirmation
        ) {
            Button("移除並重新設定", role: .destructive) {
                discardRecoveryConfiguration()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這會移除目前可讀取或損毀的 API key、endpoint、model 與回答長度。每月上限及本月用量會保留。")
        }
        .confirmationDialog(
            "清除 API 設定？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除設定", role: .destructive) { clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Endpoint、model、回答長度與 Keychain 中的 API key 都會移除。每月上限與本月用量會保留。")
        }
        .alert("API 設定未完成", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var draft: AIConfigurationDraft {
        AIConfigurationDraft(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            maximumAnswerCharacters: maximumAnswerCharacters,
            monthlyLimit: monthlyLimit
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadDraft(force: Bool) {
        guard force || !hasLoaded else { return }
        hasLoaded = true
        do {
            let loadedDraft = try commitCoordinator.makeDraft()
            endpoint = loadedDraft.endpoint
            model = loadedDraft.model
            apiKey = loadedDraft.apiKey
            maximumAnswerCharacters = loadedDraft.maximumAnswerCharacters
            monthlyLimit = loadedDraft.monthlyLimit
            resetTestStatus()
        } catch {
            errorMessage = safeMessage(
                for: error,
                fallback: "目前無法讀取已儲存的 API key，請稍後再試。"
            )
        }
    }

    private func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        testMessage = nil
        testSucceeded = false
        let currentDraft = draft
        testTask = Task {
            defer {
                isTesting = false
                testTask = nil
            }
            do {
                try await commitCoordinator.testConnection(draft: currentDraft)
                testSucceeded = true
                testMessage = "連線、model 與 structured output 測試成功。草稿尚未儲存。"
            } catch is CancellationError {
                return
            } catch {
                testMessage = safeMessage(for: error, fallback: "API 測試失敗，請檢查目前欄位。")
            }
        }
    }

    private func resetTestStatus() {
        guard !isTesting else { return }
        testMessage = nil
        testSucceeded = false
    }

    private func save() {
        do {
            try commitCoordinator.commit(draft: draft)
            dismiss()
        } catch {
            errorMessage = safeMessage(for: error, fallback: "目前無法儲存 API 設定。先前設定未變更，請稍後再試。")
        }
    }

    private func clear() {
        do {
            try commitCoordinator.clear()
            dismiss()
        } catch {
            errorMessage = safeMessage(for: error, fallback: "目前無法清除 API 設定。先前設定未變更，請稍後再試。")
        }
    }

    private func discardRecoveryConfiguration() {
        do {
            try commitCoordinator.discardRecoveryConfiguration()
            loadDraft(force: true)
        } catch {
            errorMessage = safeMessage(
                for: error,
                fallback: "目前仍無法移除損毀設定，AI 會保持停用。請稍後再試。"
            )
        }
    }

    private func safeMessage(for error: any Error, fallback: String) -> String {
        switch error {
        case let error as OpenAIResponsesConfiguration.ValidationError:
            return error.errorDescription ?? fallback
        case let error as OpenAIResponsesInterpreter.InterpreterError:
            return error.errorDescription ?? fallback
        case let error as KeychainAPICredentialStore.CredentialError:
            return error.errorDescription ?? fallback
        case let error as AIUsageStore.UsageError:
            return error.errorDescription ?? fallback
        case let error as AIConfigurationCommitError:
            return error.errorDescription ?? fallback
        default:
            return fallback
        }
    }
}
