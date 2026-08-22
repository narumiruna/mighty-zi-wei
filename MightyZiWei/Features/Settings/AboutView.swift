import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section("關於") {
                LabeledContent("App", value: "很牛的紫微斗數")
                LabeledContent("版本", value: appVersion)
                LabeledContent("排盤規則", value: "台灣傳統三合派 v1")
                LabeledContent("輔助參考", value: "中州派")
            }

            Section("排盤說明") {
                Text("不同流派對閏月、四化與部分星曜可能採用不同規則，因此命盤結果可能略有差異。")
                Text("本 App 以民用日期午夜換日，23:00 至 00:59 都屬子時，但 23:00 不提前換日。")
                Text("本命盤不使用真太陽時，也不包含大限、流年、流月或流日。")
            }

            Section("隱私") {
                Text("App 不會將你的出生資料或命盤傳送到我們的伺服器。")
                Text("裝置端 AI 解讀只使用 Apple Intelligence；模型不可用時仍可使用基本解讀。")
                Text("iOS 可能依你的系統設定，將 App 資料納入備份或裝置移轉。")
            }

            Section("支援") {
                Link(
                    "隱私權說明",
                    destination: URL(string: "https://github.com/narumiruna/mighty-zi-wei/blob/main/Documentation/PRIVACY.md")!
                )
                Link(
                    "回報問題",
                    destination: URL(string: "https://github.com/narumiruna/mighty-zi-wei/issues")!
                )
            }

            Section("重要提醒") {
                DisclaimerView()
            }
        }
        .navigationTitle("關於")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)（\(build)）"
    }
}
