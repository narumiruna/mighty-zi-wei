import SwiftData
import SwiftUI

struct ChartView: View {
    let chart: ZiWeiChart
    let name: String
    var allowsSaving = true
    var notice: String?
    var savedChartID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Environment(ChartAssistantStore.self) private var assistantStore
    @State private var assistantChartID = UUID()
    @State private var showsAssistantSwitchConfirmation = false
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("命盤總覽")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("先從命宮開始，或點選你想了解的生活面向。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let notice {
                    Label(notice, systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .cardStyle()
                }

                ChartOverview(
                    chart: chart,
                    name: displayName
                )

                ChartDataDisclosure(chart: chart)

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

                Button {
                    openAssistant()
                } label: {
                    Label("用 AI 詢問這張命盤", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("chart.askAI")

                DisclaimerView(compact: true)
            }
            .padding()
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            assistantStore.offer(assistantChart)
        }
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
        .alert("無法儲存命盤", isPresented: errorIsPresented) {
            Button("再試一次") { saveChart() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
        .confirmationDialog(
            "切換命盤並清除本次 AI 對話？",
            isPresented: $showsAssistantSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button("切換並前往 AI", role: .destructive) {
                assistantStore.select(assistantChart)
                navigation.selectedTab = .ai
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目前 AI 對話使用另一張命盤。不同命盤的對話依據不能混用。")
        }
    }

    private var assistantChart: ChartAssistantChart {
        ChartAssistantChart.make(
            id: savedChartID ?? assistantChartID,
            savedChartID: savedChartID,
            name: name,
            chart: chart
        )
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

    private func openAssistant() {
        if assistantStore.requiresConfirmation(toSelect: assistantChart) {
            showsAssistantSwitchConfirmation = true
        } else {
            assistantStore.select(assistantChart)
            navigation.selectedTab = .ai
        }
    }

    private func saveChart() {
        errorMessage = nil
        do {
            let saved = try SavedChart.make(name: name, profile: chart.birthProfile, chart: chart)
            modelContext.insert(saved)
            try modelContext.save()
            withAnimation {
                isSaved = true
                saveMessage = "命盤已儲存在這台裝置。"
            }
        } catch {
            modelContext.rollback()
            errorMessage = "本機資料寫入失敗，目前命盤仍保留。你可以再試一次。"
        }
    }
}

private enum ChartOverviewMetrics {
    static let spacing: CGFloat = 8
    static let maximumSideLength: CGFloat = 680
}

private enum ChartText {
    static func gregorianSummary(_ chart: ZiWeiChart) -> String {
        let date = chart.birthProfile.localDate
        let time = chart.birthProfile.localTime
        return String(
            format: "%04d/%02d/%02d　%02d:%02d",
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute
        )
    }

    static func lunarSummary(_ chart: ZiWeiChart) -> String {
        let date = chart.lunarDate
        return "農曆\(date.isLeapMonth ? "閏" : "")\(date.month)月\(date.day)日　\(chart.hourBranch.displayName)時"
    }
}

private struct ChartOverview: View {
    let chart: ZiWeiChart
    let name: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleLayout
        } else {
            chartLayout
        }
    }

    private var chartLayout: some View {
        GeometryReader { geometry in
            let sideLength = min(geometry.size.width, ChartOverviewMetrics.maximumSideLength)
            let cellSize = (
                sideLength - ChartOverviewMetrics.spacing * 3
            ) / 4

            ChartGrid(
                chart: chart,
                name: name,
                cellSize: cellSize
            )
            .frame(width: sideLength, height: sideLength)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: ChartOverviewMetrics.maximumSideLength)
        .frame(maxWidth: .infinity)
    }

    private var accessibleLayout: some View {
        VStack(spacing: ChartOverviewMetrics.spacing) {
            ChartIdentityCard(
                name: name,
                birthSummary: ChartText.gregorianSummary(chart)
            )

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 150),
                        spacing: ChartOverviewMetrics.spacing
                    )
                ],
                spacing: ChartOverviewMetrics.spacing
            ) {
                ForEach(PalaceKind.allCases) { kind in
                    let palace = chart.palace(kind)
                    NavigationLink {
                        PalaceDetailView(chart: chart, palaceKind: kind)
                    } label: {
                        PalaceOverviewCell(palace: palace)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chart.palace.\(kind.rawValue)")
                }
            }
        }
    }
}

private struct ChartGrid: View {
    let chart: ZiWeiChart
    let name: String
    let cellSize: CGFloat

    private let spacing = ChartOverviewMetrics.spacing

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
                ChartIdentityCard(
                    name: name,
                    birthSummary: ChartText.gregorianSummary(chart),
                    size: cellSize * 2 + spacing
                )
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
    }

    private func cell(_ branch: EarthlyBranch) -> some View {
        let palace = chart.palaces.first { $0.stemBranch.branch == branch }!
        return NavigationLink {
            PalaceDetailView(chart: chart, palaceKind: palace.kind)
        } label: {
            PalaceOverviewCell(
                palace: palace,
                size: cellSize
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chart.palace.\(palace.kind.rawValue)")
    }
}

private struct ChartIdentityCard: View {
    let name: String
    let birthSummary: String
    var size: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            Text(birthSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: size, height: size, alignment: .topLeading)
        .frame(
            maxWidth: size == nil ? .infinity : nil,
            minHeight: size == nil ? 88 : nil,
            alignment: .topLeading
        )
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name)，出生時間\(birthSummary)")
    }
}

private struct PalaceOverviewCell: View {
    let palace: ChartPalace
    var size: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(palace.kind.displayName)
                .font(.subheadline.weight(.semibold))

            if palace.isBodyPalace {
                Text("身宮")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: size, height: size, alignment: .topLeading)
        .frame(
            maxWidth: size == nil ? .infinity : nil,
            minHeight: size == nil ? 72 : nil,
            alignment: .topLeading
        )
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
        )
        .overlay {
            if palace.kind == .life {
                RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
                    .stroke(.tint, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("點兩下查看宮位內容")
    }

    private var accessibilityText: String {
        palace.isBodyPalace
            ? "\(palace.kind.displayName)，身宮位於此"
            : palace.kind.displayName
    }
}

private struct ChartDataDisclosure: View {
    let chart: ZiWeiChart

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("公曆", value: ChartText.gregorianSummary(chart))
                LabeledContent("農曆", value: ChartText.lunarSummary(chart))
                LabeledContent("出生地時區", value: chart.birthProfile.timeZoneIdentifier)
                Divider()
                LabeledContent("命宮干支", value: chart.lifePalace.stemBranch.displayName)
                LabeledContent("身宮", value: chart.bodyPalace.kind.displayName)
                LabeledContent("五行局", value: chart.fiveElementBureau.displayName)
            }
            .font(.footnote)
            .padding(.top, 8)
        } label: {
            Label("排盤資料", systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
        }
        .cardStyle()
        .accessibilityIdentifier("chart.data")
    }
}

private struct PalaceDetailView: View {
    let chart: ZiWeiChart
    let palaceKind: PalaceKind

    private var palace: ChartPalace { chart.palace(palaceKind) }
    private var stars: [StarPlacement] { chart.stars.filter { $0.palace == palaceKind } }
    private var mainStars: [StarPlacement] { stars.filter { $0.star.category == .main } }
    private var otherStars: [StarPlacement] { stars.filter { $0.star.category != .main } }
    private var transformations: [Transformation] { chart.transformations.filter { $0.palace == palaceKind } }
    private var relation: PalaceRelation { chart.relation(of: palaceKind) }

    var body: some View {
        List {
            Section {
                LabeledContent("宮位干支", value: palace.stemBranch.displayName)
                if palace.isBodyPalace {
                    Label("身宮位於此宮", systemImage: "person.crop.circle")
                }
            }

            Section("主星") {
                if mainStars.isEmpty {
                    Text("本宮無主星")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mainStars) { placement in
                        Text(placement.star.displayName)
                    }
                }
            }

            if !transformations.isEmpty {
                Section("生年四化") {
                    ForEach(transformations) { transformation in
                        LabeledContent(
                            transformation.star.displayName,
                            value: transformation.kind.displayName
                        )
                    }
                }
            }

            Section {
                DisclosureGroup("其他星曜（\(otherStars.count) 顆）") {
                    if otherStars.isEmpty {
                        Text("本宮沒有其他星曜")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(otherStars) { placement in
                            Text(placement.star.displayName)
                        }
                    }
                }
                .accessibilityIdentifier("palace.otherStars")
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
                .accessibilityIdentifier("palace.relations")
            }
        }
        .navigationTitle(palace.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
