import SwiftUI

struct AIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIConfigurationStore.self) private var configurationStore

    @State private var endpoint = AIConfigurationStore.defaultEndpoint
    @State private var model = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var showsClearConfirmation = false
    @State private var hasLoaded = false

    var body: some View {
        Form {
            Section {
                TextField("完整 Responses API URL", text: $endpoint, axis: .vertical)
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
                Text("Endpoint 必須是完整的 HTTPS Responses API URL。API key 只儲存在本機 Keychain，不會同步到其他裝置。")
            }

            Section("資料與費用") {
                Text("只有在你主動要求雲端整理時，App 才會傳送已驗證的命盤事實與基礎解讀。")
                Text("資料會傳送到你設定的第三方服務，並受該服務的隱私政策、保存方式與費用規則約束。")
                Text("Prompt 不包含姓名、原始出生日期或出生時間。API key 只會作為授權 header 傳送到你設定的 endpoint。")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("儲存 API 設定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
