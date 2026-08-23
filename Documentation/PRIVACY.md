# 隱私權說明

很牛的紫微斗數不需要帳號，也不建立開發者控制的後端服務。

App 不會將你的出生資料、命盤、prompt 或解讀內容傳送到我們的伺服器。

出生資料與已儲存命盤使用 SwiftData 保存在本機。

iOS 仍可能依使用者的系統設定，將 App 資料納入裝置備份或裝置移轉。

AI 解讀是選用功能。

使用 AI 解讀前，你必須自行設定完整的 HTTPS OpenAI 相容 Responses API endpoint 與模型名稱；不要求 Bearer token 的相容服務可將 API key 留空。

API key 儲存在不可同步、僅限本裝置且解鎖時可讀的 iOS Keychain item，不會寫入 SwiftData、診斷記錄或 repository。

非空的 API key 只會作為 `Authorization` header 傳送到你設定的 endpoint。

App 以非串流 HTTPS 請求，將產生解讀所需的命盤 facts、interpretation seeds、prompt 與技術性請求資料直接傳送至你指定的第三方服務商。

這些資料離開裝置後，會依該服務商的服務條款、隱私政策、資料保留設定與所在地法規處理。

請勿設定你不信任的 endpoint，並在啟用前查閱服務商的隱私與安全說明。

第三方服務商可能依請求量、token 用量或其方案另外收費。

這些費用不包含在 App 買斷價格內，也不由 App 開發者代收或控制。

若 API 未設定、無法連線、回應無效或內容驗證失敗，App 會使用本機 deterministic 基本解讀。

停用 AI 解讀不影響排盤、命盤閱讀、基本解讀或本機儲存。

App 不包含第三方分析、廣告或當機回報 SDK。

你可以刪除單張命盤或所有已儲存命盤，也可以在「設定」中另外清除 endpoint、model 與 Keychain 中的 API key。
