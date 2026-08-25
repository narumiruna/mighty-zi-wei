import SwiftUI

struct ChartShareBuilder: Sendable {
    struct Options: Equatable, Sendable {
        var includesName = false
        var includesBirthData = false
    }

    func makeText(chart: ZiWeiChart, name: String, options: Options) -> String {
        var lines = ["很牛的紫微斗數｜命盤摘要"]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if options.includesName, !trimmedName.isEmpty {
            lines.append("名稱：\(trimmedName)")
        }
        if options.includesBirthData {
            let date = chart.birthProfile.localDate
            let time = chart.birthProfile.localTime
            lines.append(String(
                format: "出生資料：%04d/%02d/%02d %02d:%02d（%@）",
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
                chart.birthProfile.timeZoneIdentifier
            ))
        }

        let lifeStars = chart.stars
            .filter { $0.palace == .life && $0.star.category == .main }
            .map(\.star.displayName)
        lines.append("命宮：\(chart.lifePalace.stemBranch.displayName)")
        lines.append("身宮：\(chart.bodyPalace.kind.displayName)")
        lines.append("五行局：\(chart.fiveElementBureau.displayName)")
        lines.append("命宮主星：\(lifeStars.isEmpty ? "無主星" : lifeStars.joined(separator: "、"))")
        lines.append("規則集：\(chart.ruleSet.id) v\(chart.ruleSet.version)")
        lines.append("僅供娛樂與自我反思，不應取代專業意見或重大人生決策。")
        return lines.joined(separator: "\n")
    }
}

struct ChartSharingView: View {
    let chart: ZiWeiChart
    let name: String

    @Environment(\.dismiss) private var dismiss
    @State private var includesName = false
    @State private var includesBirthData = false

    private var text: String {
        ChartShareBuilder().makeText(
            chart: chart,
            name: name,
            options: .init(
                includesName: includesName,
                includesBirthData: includesBirthData
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("包含名稱", isOn: $includesName)
                    Toggle("包含完整出生資料", isOn: $includesBirthData)
                } header: {
                    Text("個人資料")
                } footer: {
                    Text("預設不包含名稱、出生日期、時間或時區。開啟後請先確認分享對象。")
                }

                Section("分享預覽") {
                    Text(text)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                Section {
                    ShareLink(item: text) {
                        Label("分享文字摘要", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("share.confirm")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .navigationTitle("隱私分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}
