import SwiftUI

struct AIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIConfigurationStore.self) private var configurationStore
    @Environment(AIUsageStore.self) private var usageStore

    @State private var endpoint = AIConfigurationStore.defaultEndpoint
    @State private var model = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var showsClearConfirmation = false
    @State private var hasLoaded = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var testTask: Task<Void, Never>?
    @State private var copiedDiagnostic = false

    var body: some View {
        Form {
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
                        Text(isTesting ? "正在測試…" : "測試 API 連線")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
                .accessibilityIdentifier("ai.test")

                if let testMessage {
                    Text(testMessage)
                        .font(.footnote)
                        .foregroundStyle(testSucceeded ? .green : .red)
                        .accessibilityIdentifier("ai.testStatus")
                }
            } footer: {
                Text("測試會使用目前欄位發出一個小型 Responses API request，可能產生少量 token 費用，但不會傳送命盤資料。")
            }

            Section {
                Picker("每次回答長度", selection: answerLengthBinding) {
                    Text("精簡（600 字）").tag(600)
                    Text("標準（1,200 字）").tag(1_200)
                    Text("詳細（2,000 字）").tag(2_000)
                }
                Picker("每月請求上限", selection: monthlyLimitBinding) {
                    Text("10 次").tag(10)
                    Text("25 次").tag(25)
                    Text("50 次").tag(50)
                    Text("100 次").tag(100)
                    Text("不設上限").tag(0)
                }
                LabeledContent("本月已送出", value: "\(usageStore.currentMonthCount) 次")
                if let remaining = usageStore.remainingRequests {
                    LabeledContent("本月剩餘", value: "\(remaining) 次")
                }
            } header: {
                Text("回答與費用保護")
            } footer: {
                Text("請求上限在送出前由 App 檢查；實際 token 與費用仍以第三方服務紀錄為準。")
            }

            if let diagnostic = usageStore.lastDiagnostic {
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

            if configurationStore.hasStoredValues {
                Section {
                    Button("清除 API 設定", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .accessibilityIdentifier("ai.clear")
                }
            }
        }
        .navigationTitle("AI API 設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadConfigurationIfNeeded)
        .onDisappear {
            testTask?.cancel()
        }
        .onChange(of: endpoint) { _, _ in resetTestStatus() }
        .onChange(of: model) { _, _ in resetTestStatus() }
        .onChange(of: apiKey) { _, _ in resetTestStatus() }
        .confirmationDialog(
            "清除 API 設定？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除設定", role: .destructive) { clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Endpoint、model 與 Keychain 中的 API key 都會移除。")
        }
        .alert("API 設定未完成", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadConfigurationIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        endpoint = configurationStore.endpoint
        model = configurationStore.model
        do {
            apiKey = try configurationStore.loadAPIKey()
        } catch {
            errorMessage = "目前無法讀取已儲存的 API key，請稍後再試。"
        }
    }

    private func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        testMessage = nil
        testSucceeded = false
        testTask = Task {
            defer {
                isTesting = false
                testTask = nil
            }
            do {
                let configuration = try OpenAIResponsesConfiguration(
                    endpoint: endpoint,
                    model: model,
                    apiKey: apiKey
                )
                try usageStore.reserve(.connectionTest)
                endpoint = configuration.endpoint.absoluteString
                try await OpenAIResponsesInterpreter().testConnection(
                    configuration: configuration
                )
                try Task.checkCancellation()
                testSucceeded = true
                testMessage = "連線、model 與 structured output 測試成功。"
            } catch is CancellationError {
                return
            } catch let error as LocalizedError {
                usageStore.record(error: error, kind: .connectionTest)
                testMessage = error.errorDescription ?? "API 測試失敗，請檢查設定。"
            } catch {
                usageStore.record(error: error, kind: .connectionTest)
                testMessage = "API 測試失敗，請檢查設定。"
            }
        }
    }

    private var answerLengthBinding: Binding<Int> {
        Binding(
            get: { configurationStore.maximumAnswerCharacters },
            set: { configurationStore.setMaximumAnswerCharacters($0) }
        )
    }

    private var monthlyLimitBinding: Binding<Int> {
        Binding(
            get: { usageStore.monthlyLimit },
            set: { usageStore.monthlyLimit = $0 }
        )
    }

    private func resetTestStatus() {
        guard !isTesting else { return }
        testMessage = nil
        testSucceeded = false
    }

    private func save() {
        do {
            try configurationStore.save(endpoint: endpoint, model: model, apiKey: apiKey)
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "目前無法儲存 API 設定。"
        } catch {
            errorMessage = "目前無法儲存 API 設定。"
        }
    }

    private func clear() {
        do {
            try configurationStore.clear()
            endpoint = configurationStore.endpoint
            model = configurationStore.model
            apiKey = ""
            dismiss()
        } catch {
            errorMessage = "目前無法清除 API 設定，請稍後再試。"
        }
    }
}
