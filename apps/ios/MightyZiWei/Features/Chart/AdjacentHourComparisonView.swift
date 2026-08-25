import SwiftUI

struct AdjacentHourComparisonView: View {
    let profile: BirthProfile

    @State private var comparison: AdjacentHourComparison?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("時辰比較")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("並列相鄰三個時辰的盤面位置差異，不替你猜測出生時辰。")
                        .foregroundStyle(.secondary)
                }

                if let comparison {
                    HourSnapshotView(title: "目前輸入", snapshot: comparison.current, isCurrent: true)
                    HourDifferencesView(
                        title: "前一個時辰",
                        snapshot: comparison.previous,
                        differences: comparison.previousDifferences
                    )
                    HourDifferencesView(
                        title: "後一個時辰",
                        snapshot: comparison.next,
                        differences: comparison.nextDifferences
                    )
                } else if let errorMessage {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "無法比較時辰",
                        message: errorMessage
                    )
                } else {
                    ProgressView("正在比較相鄰時辰…")
                        .frame(maxWidth: .infinity)
                }

                Text("比較只使用命宮、身宮、五行局、十四主星與生年四化的已驗證位置，不提供定時辰結論。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("時辰比較")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do {
            comparison = try AdjacentHourComparisonBuilder().make(from: profile)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "出生資料無法通過驗證。"
        } catch {
            errorMessage = "出生資料或相鄰時辰超出目前支援範圍。"
        }
    }
}

private struct HourDifferencesView: View {
    let title: String
    let snapshot: AdjacentHourChartSnapshot
    let differences: [AdjacentHourFactDifference]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(snapshot.hourBranch.displayName)時")
                    .font(.headline)
            }

            if differences.isEmpty {
                Text("指定範圍內沒有位置差異。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(differences.enumerated()), id: \.offset) { _, difference in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: difference.subject))
                            .font(.headline)
                        Text("目前：\(text(for: difference.currentValue))")
                            .font(.subheadline)
                        Text("此時辰：\(text(for: difference.adjacentValue))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }

    private var timeText: String {
        let date = snapshot.birthProfile.localDate
        let time = snapshot.birthProfile.localTime
        return String(
            format: "%04d/%02d/%02d %02d:%02d",
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute
        )
    }

    private func title(for subject: AdjacentHourFactSubject) -> String {
        switch subject {
        case .lifePalace: "命宮"
        case .bodyPalace: "身宮"
        case .fiveElementBureau: "五行局"
        case .mainStar(let star): star.displayName
        case .transformation(let transformation): transformation.displayName
        }
    }

    private func text(for value: AdjacentHourFactValue) -> String {
        switch value {
        case .palace(let kind, let branch):
            "\(kind.displayName)・\(branch.displayName)宮"
        case .fiveElementBureau(let bureau):
            bureau.displayName
        case .starPosition(let branch, let palace):
            "\(palace.displayName)・\(branch.displayName)宮"
        case .transformationPosition(let star, let branch, let palace):
            "\(star.displayName)・\(palace.displayName)・\(branch.displayName)宮"
        }
    }
}

private struct HourSnapshotView: View {
    let title: String
    let snapshot: AdjacentHourChartSnapshot
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(snapshot.hourBranch.displayName)時")
                    .font(.headline)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            }

            LabeledContent("命宮", value: snapshot.lifePalace.stemBranch.displayName)
            LabeledContent(
                "身宮",
                value: "\(snapshot.bodyPalace.kind.displayName)（\(snapshot.bodyPalace.stemBranch.displayName)）"
            )
            LabeledContent("五行局", value: snapshot.fiveElementBureau.displayName)

            DisclosureGroup("十四主星位置") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.mainStars) { placement in
                        LabeledContent(
                            placement.star.displayName,
                            value: "\(placement.palace.displayName)・\(placement.branch.displayName)宮"
                        )
                    }
                }
                .font(.footnote)
                .padding(.top, 8)
            }

            DisclosureGroup("生年四化位置") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.transformations) { transformation in
                        LabeledContent(
                            transformation.kind.displayName,
                            value: "\(transformation.star.displayName)・\(transformation.palace.displayName)"
                        )
                    }
                }
                .font(.footnote)
                .padding(.top, 8)
            }
        }
        .cardStyle()
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius)
                    .stroke(.tint, lineWidth: 1)
            }
        }
    }

    private var timeText: String {
        let date = snapshot.birthProfile.localDate
        let time = snapshot.birthProfile.localTime
        return String(
            format: "%04d/%02d/%02d %02d:%02d",
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute
        )
    }
}
