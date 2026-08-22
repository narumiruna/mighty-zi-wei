import SwiftData
import SwiftUI

struct ChartView: View {
    let chart: ZiWeiChart
    let name: String
    var allowsSaving = true
    var notice: String?

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPalace: PalaceKind?
    @State private var isSaved = false
    @State private var saveMessage: String?
    @State private var errorMessage: String?

    private var facts: [ChartFact] {
        ChartFactBuilder().makeFacts(from: chart)
    }

    private var seeds: [InterpretationSeed] {
        InterpretationSeedBuilder().makeSeeds(from: facts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                Text("十二宮")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("點選宮位可查看星曜、四化與三方四正。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let notice {
                    Label(notice, systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .cardStyle()
                }

                ScrollView(.horizontal) {
                    ChartGrid(
                        chart: chart,
                        name: displayName,
                        selectedPalace: $selectedPalace
                    )
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                        .accessibilityLabel(saveMessage)
                }

                NavigationLink {
                    InterpretationView(facts: facts, seeds: seeds)
                } label: {
                    Label("查看命盤解讀", systemImage: "text.book.closed")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chart.interpretation")

                DisclaimerView(compact: true)
            }
            .padding()
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveChart()
                    } label: {
                        Label(
                            isSaved ? "已儲存" : "儲存命盤",
                            systemImage: isSaved ? "checkmark" : "square.and.arrow.down"
                        )
                    }
                    .disabled(isSaved)
                    .accessibilityIdentifier("chart.save")
                }
            }
        }
        .sheet(item: $selectedPalace) { kind in
            PalaceDetailView(chart: chart, palaceKind: kind)
        }
        .alert("無法儲存命盤", isPresented: errorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名命盤" : trimmed
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func saveChart() {
        do {
            let saved = try SavedChart.make(name: name, profile: chart.birthProfile, chart: chart)
            modelContext.insert(saved)
            try modelContext.save()
            withAnimation {
                isSaved = true
                saveMessage = "命盤已儲存在這台裝置。"
            }
        } catch {
            errorMessage = "本機資料寫入失敗，請稍後再試。"
        }
    }
}

private struct ChartGrid: View {
    let chart: ZiWeiChart
    let name: String
    @Binding var selectedPalace: PalaceKind?

    private let cellSize: CGFloat = 164
    private let spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach([EarthlyBranch.si, .wu, .wei, .shen], id: \.rawValue) { branch in
                    cell(branch)
                }
            }
            HStack(spacing: spacing) {
                VStack(spacing: spacing) {
                    cell(.chen)
                    cell(.mao)
                }
                chartSummary
                    .frame(width: cellSize * 2 + spacing, height: cellSize * 2 + spacing)
                VStack(spacing: spacing) {
                    cell(.you)
                    cell(.xu)
                }
            }
            HStack(spacing: spacing) {
                ForEach([EarthlyBranch.yin, .chou, .zi, .hai], id: \.rawValue) { branch in
                    cell(branch)
                }
            }
        }
        .frame(minWidth: cellSize * 4 + spacing * 3)
    }

    private var chartSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.title2.bold())
                .lineLimit(2)
            Spacer()
            LabeledContent("命宮", value: chart.lifePalace.stemBranch.displayName)
            LabeledContent("身宮", value: chart.bodyPalace.kind.displayName)
            LabeledContent("五行局", value: chart.fiveElementBureau.displayName)
            Divider()
            Text(gregorianSummary)
            Text(lunarSummary)
            Text(chart.birthProfile.timeZoneIdentifier)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)，命宮\(chart.lifePalace.stemBranch.displayName)，身宮在\(chart.bodyPalace.kind.displayName)，\(chart.fiveElementBureau.displayName)，\(gregorianSummary)，\(lunarSummary)")
    }

    private var gregorianSummary: String {
        let date = chart.birthProfile.localDate
        let time = chart.birthProfile.localTime
        return String(format: "%04d/%02d/%02d　%02d:%02d", date.year, date.month, date.day, time.hour, time.minute)
    }

    private var lunarSummary: String {
        let date = chart.lunarDate
        return "農曆\(date.isLeapMonth ? "閏" : "")\(date.month)月\(date.day)日　\(chart.hourBranch.displayName)時"
    }

    private func cell(_ branch: EarthlyBranch) -> some View {
        let palace = chart.palaces.first { $0.stemBranch.branch == branch }!
        let stars = chart.stars.filter { $0.palace == palace.kind }
        let transformations = Dictionary(
            uniqueKeysWithValues: chart.transformations.map { ($0.star, $0.kind) }
        )
        return Button {
            selectedPalace = palace.kind
        } label: {
            PalaceCell(
                palace: palace,
                stars: stars,
                transformations: transformations
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PalaceCell: View {
    let palace: ChartPalace
    let stars: [StarPlacement]
    let transformations: [Star: TransformationKind]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(palace.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(palace.stemBranch.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if palace.isBodyPalace {
                Text("身宮")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(stars.prefix(6)) { placement in
                    HStack(spacing: 3) {
                        Text(placement.star.displayName)
                            .font(placement.star.category == .main ? .caption.weight(.semibold) : .caption2)
                        if let transformation = transformations[placement.star] {
                            Text(transformation.displayName)
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                if stars.count > 6 {
                    Text("另有 \(stars.count - 6) 顆")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 164, height: 164, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("點兩下查看宮位詳細資訊")
    }

    private var accessibilityText: String {
        let starNames = stars.map { placement in
            if let transformation = transformations[placement.star] {
                return placement.star.displayName + transformation.displayName
            }
            return placement.star.displayName
        }
        let body = palace.isBodyPalace ? "，身宮在此" : ""
        return "\(palace.kind.displayName)，\(palace.stemBranch.displayName)\(body)，星曜：\(starNames.joined(separator: "、"))"
    }
}

private struct PalaceDetailView: View {
    let chart: ZiWeiChart
    let palaceKind: PalaceKind
    @Environment(\.dismiss) private var dismiss

    private var palace: ChartPalace { chart.palace(palaceKind) }
    private var stars: [StarPlacement] { chart.stars.filter { $0.palace == palaceKind } }
    private var transformations: [Transformation] { chart.transformations.filter { $0.palace == palaceKind } }
    private var relation: PalaceRelation { chart.relation(of: palaceKind) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("宮位干支", value: palace.stemBranch.displayName)
                    if palace.isBodyPalace {
                        LabeledContent("身宮", value: "身宮位於此宮")
                    }
                }

                Section("十四主星") {
                    starRows(category: .main)
                }

                Section("其他星曜") {
                    ForEach(stars.filter { $0.star.category != .main }) { placement in
                        starRow(placement)
                    }
                }

                if !transformations.isEmpty {
                    Section("生年四化") {
                        ForEach(transformations) { transformation in
                            LabeledContent(
                                transformation.kind.displayName,
                                value: transformation.star.displayName
                            )
                        }
                    }
                }

                Section {
                    DisclosureGroup("三方四正") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("三合宮", value: relation.trines.map(\.displayName).joined(separator: "、"))
                            LabeledContent("對宮", value: relation.opposite.displayName)
                        }
                        .font(.footnote)
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(palace.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func starRows(category: StarCategory) -> some View {
        let filtered = stars.filter { $0.star.category == category }
        if filtered.isEmpty {
            Text("本宮無十四主星")
                .foregroundStyle(.secondary)
        } else {
            ForEach(filtered) { placement in
                starRow(placement)
            }
        }
    }

    private func starRow(_ placement: StarPlacement) -> some View {
        HStack {
            Text(placement.star.displayName)
            Spacer()
            if let transformation = chart.transformations.first(where: { $0.star == placement.star }) {
                Text(transformation.kind.displayName)
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
