import Accessibility
import SwiftData
import SwiftUI

struct SavedChartReferenceResolver: Sendable {
    static func effectiveID(
        savedChartID: UUID?,
        newlySavedChartID: UUID?,
        newlySavedIsConfirmed: Bool,
        availableIDs: Set<UUID>
    ) -> UUID? {
        if newlySavedIsConfirmed, let newlySavedChartID {
            return newlySavedChartID
        }
        return existingID(
            savedChartID: savedChartID,
            newlySavedChartID: newlySavedChartID,
            availableIDs: availableIDs
        )
    }

    static func existingID(
        savedChartID: UUID?,
        newlySavedChartID: UUID?,
        availableIDs: Set<UUID>
    ) -> UUID? {
        guard let candidate = savedChartID ?? newlySavedChartID,
              availableIDs.contains(candidate) else {
            return nil
        }
        return candidate
    }
}

struct ChartView: View {
    let chart: ZiWeiChart
    let name: String
    var allowsSaving = true
    var notice: String?
    var savedChartID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Environment(ChartAssistantStore.self) private var assistantStore
    @Query private var savedCharts: [SavedChart]
    @State private var assistantChartID = UUID()
    @State private var showsAssistantSwitchConfirmation = false
    @State private var showsSharing = false
    @State private var duplicateChart: SavedChart?
    @State private var isSaved = false
    @State private var newlySavedChartID: UUID?
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

                    Text(displayName)
                        .font(.headline)

                    Label(
                        isChartSaved ? "已儲存於這台裝置" : "尚未儲存",
                        systemImage: isChartSaved ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("先看生活化摘要，再選擇完整解讀或命盤助理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let notice {
                    InlineStatusView(style: .information, message: notice)
                }

                if let saveMessage {
                    InlineStatusView(
                        style: isChartSaved ? .success : .warning,
                        message: saveMessage
                    )
                    .transition(.opacity)
                    .accessibilityLabel(saveMessage)
                }

                PrimaryPalaceGuide(
                    chart: chart,
                    assistantChart: assistantChart
                )

                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink {
                        InterpretationView(
                            facts: facts,
                            seeds: seeds,
                            chartID: effectiveSavedChartID
                        )
                    } label: {
                        Label("閱讀命盤解讀", systemImage: "text.book.closed")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("chart.interpretation")

                    Button {
                        openAssistant()
                    } label: {
                        Label("問命盤助理", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chart.askAI")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("自由探索十二宮")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("宮格顯示主星分布；點選宮位可查看完整內容。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ChartOverview(
                        chart: chart,
                        name: displayName,
                        assistantChart: assistantChart
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("命盤工具")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    if let chartID = effectiveSavedChartID {
                        NavigationLink {
                            ChartJournalView(chartID: chartID, chartName: displayName)
                        } label: {
                            Label("筆記與收藏", systemImage: "note.text")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("chart.journal")
                    } else {
                        Button {} label: {
                            Label("筆記與收藏", systemImage: "note.text")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .accessibilityIdentifier("chart.journal")

                        DisabledReasonView("先儲存命盤才能收藏。")
                    }

                    NavigationLink {
                        AdjacentHourComparisonView(profile: chart.birthProfile)
                    } label: {
                        Label("比較相鄰時辰", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chart.compareHours")

                    Button {
                        showsSharing = true
                    } label: {
                        Label("分享命盤摘要", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chart.share")

                    ChartDataDisclosure(chart: chart)
                }

                DisclaimerView(compact: true)
            }
            .padding()
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            assistantStore.offer(assistantChart)
        }
        .onChange(of: savedCharts.map(\.id)) { _, availableIDs in
            reconcileSavedChartState(availableIDs: Set(availableIDs))
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
        .sheet(isPresented: $showsSharing) {
            ChartSharingView(chart: chart, name: displayName)
        }
        .alert("無法儲存命盤", isPresented: errorIsPresented) {
            Button("再試一次") { saveChart() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
        .confirmationDialog(
            "已有相同出生資料的命盤",
            isPresented: duplicateConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("仍要儲存另一張") { persistChart() }
            Button("取消", role: .cancel) { duplicateChart = nil }
        } message: {
            Text("「\(duplicateChart?.name ?? "既有命盤")」使用相同出生日期、時間與時區。你可以取消以避免重複，或仍然保留不同名稱與標籤的版本。")
        }
        .confirmationDialog(
            "切換命盤並開始新對話？",
            isPresented: $showsAssistantSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button("返回目前對話") {
                navigation.selectedTab = .ai
            }
            Button(assistantDiscardActionTitle, role: .destructive) {
                assistantStore.select(assistantChart)
                navigation.selectedTab = .ai
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(assistantSwitchMessage)
        }
    }

    private var isChartSaved: Bool {
        isSaved || effectiveSavedChartID != nil
    }

    private var effectiveSavedChartID: UUID? {
        SavedChartReferenceResolver.effectiveID(
            savedChartID: savedChartID,
            newlySavedChartID: newlySavedChartID,
            newlySavedIsConfirmed: isSaved,
            availableIDs: Set(savedCharts.map(\.id))
        )
    }

    private var assistantChart: ChartAssistantChart {
        ChartAssistantChart.make(
            id: effectiveSavedChartID ?? assistantChartID,
            savedChartID: effectiveSavedChartID,
            name: name,
            chart: chart
        )
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名命盤" : trimmed
    }

    private var duplicateConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { duplicateChart != nil },
            set: { if !$0 { duplicateChart = nil } }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var assistantDiscardActionTitle: String {
        let hasUnpreservedWork = !assistantStore.trimmedDraft.isEmpty
            || assistantStore.hasUnsavedChanges
            || assistantStore.isRequesting
        return hasUnpreservedWork ? "不保存，切換並前往" : "切換並前往"
    }

    private var assistantSwitchMessage: String {
        if !assistantStore.trimmedDraft.isEmpty, assistantStore.turns.isEmpty {
            return "目前問題草稿屬於另一張命盤。直接切換會捨棄草稿，也不會自動送出。"
        }
        if assistantStore.hasUnsavedChanges || assistantStore.isRequesting {
            return "目前對話使用另一張命盤，尚未保存的內容會無法復原。你可以先返回目前對話保存。"
        }
        return "不同命盤的對話依據不能混用。切換後會清除畫面上的目前對話。"
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
        if let duplicate = savedCharts.first(where: {
            (try? $0.birthProfile()) == chart.birthProfile
        }) {
            duplicateChart = duplicate
            return
        }
        persistChart()
    }

    private func persistChart() {
        duplicateChart = nil
        errorMessage = nil
        do {
            let previousAssistantID = assistantChart.id
            let saved = try SavedChart.make(name: name, profile: chart.birthProfile, chart: chart)
            modelContext.insert(saved)
            try modelContext.save()
            newlySavedChartID = saved.id
            let savedAssistantChart = ChartAssistantChart.make(
                id: saved.id,
                savedChartID: saved.id,
                name: name,
                chart: chart
            )
            assistantStore.migrateSelection(from: previousAssistantID, to: savedAssistantChart)
            assistantStore.offer(savedAssistantChart)
            withAnimation {
                isSaved = true
                saveMessage = "命盤已儲存在這台裝置。"
            }
            AccessibilityNotification.Announcement("命盤已儲存在這台裝置。").post()
        } catch {
            modelContext.rollback()
            errorMessage = "本機資料寫入失敗，目前命盤仍保留。你可以再試一次。"
        }
    }

    private func reconcileSavedChartState(availableIDs: Set<UUID>) {
        guard let newlySavedChartID,
              !availableIDs.contains(newlySavedChartID) else {
            return
        }
        let unsavedAssistantChart = ChartAssistantChart.make(
            id: assistantChartID,
            savedChartID: nil,
            name: name,
            chart: chart
        )
        assistantStore.migrateSelection(
            from: newlySavedChartID,
            to: unsavedAssistantChart
        )
        self.newlySavedChartID = nil
        isSaved = false
        saveMessage = "原本儲存的命盤已刪除，你可以重新儲存。"
    }
}

private struct PrimaryPalaceGuide: View {
    let chart: ZiWeiChart
    let assistantChart: ChartAssistantChart

    private var mainStars: [Star] {
        chart.stars
            .filter { $0.palace == .life && $0.star.category == .main }
            .map(\.star)
    }

    private var summary: String {
        let facts = ChartFactBuilder().makeFacts(from: chart)
        return PalaceLearningSummaryBuilder().make(
            palaceKind: .life,
            mainStars: mainStars,
            facts: facts,
            seeds: InterpretationSeedBuilder().makeSeeds(from: facts)
        )
    }

    private var starNames: String {
        mainStars.isEmpty
            ? "從相關宮位一起理解"
            : mainStars.map(\.displayName).joined(separator: " × ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("先從你自己開始")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("你的核心性格")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text(summary)
                .lineSpacing(4)

            Text(starNames)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)

            NavigationLink {
                PalaceDetailView(
                    chart: chart,
                    palaceKind: .life,
                    assistantChart: assistantChart
                )
            } label: {
                Label("認識我的核心性格", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("chart.startExploring")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
    let assistantChart: ChartAssistantChart

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("accessibility.linear-chart") private var linearChartEnabled = false

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize >= .xxLarge || voiceOverEnabled || linearChartEnabled {
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
                assistantChart: assistantChart,
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
                        .flexible(),
                        spacing: ChartOverviewMetrics.spacing
                    )
                ],
                spacing: ChartOverviewMetrics.spacing
            ) {
                ForEach(PalaceKind.allCases) { kind in
                    let palace = chart.palace(kind)
                    NavigationLink {
                        PalaceDetailView(
                            chart: chart,
                            palaceKind: kind,
                            assistantChart: assistantChart
                        )
                    } label: {
                        PalaceOverviewCell(
                            palace: palace,
                            stars: chart.stars.filter { $0.palace == kind }
                        )
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
    let assistantChart: ChartAssistantChart
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
            PalaceDetailView(
                chart: chart,
                palaceKind: palace.kind,
                assistantChart: assistantChart
            )
        } label: {
            PalaceOverviewCell(
                palace: palace,
                stars: chart.stars.filter { $0.palace == palace.kind },
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
    var stars: [StarPlacement] = []
    var size: CGFloat?

    private var mainStarNames: [String] {
        stars.filter { $0.star.category == .main }.map(\.star.displayName)
    }

    private var otherStarNames: [String] {
        stars.filter { $0.star.category != .main }.map(\.star.displayName)
    }

    var body: some View {
        Group {
            if size == nil {
                fullContent
            } else {
                compactContent
            }
        }
        .padding(size == nil ? 12 : 7)
        .frame(width: size, height: size, alignment: .topLeading)
        .frame(
            maxWidth: size == nil ? .infinity : nil,
            minHeight: size == nil ? 96 : nil,
            alignment: .topLeading
        )
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
        )
        .overlay {
            if palace.kind == .life {
                RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
                    .stroke(.tint, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("點兩下查看宮位內容")
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(palace.kind.displayName)
                    .font(.caption.weight(.semibold))

                if palace.isBodyPalace {
                    Text("身宮")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }

            ForEach(Array(mainStarNames.prefix(2).enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption2.weight(.medium))
            }

            Spacer(minLength: 0)
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(palace.kind.displayName)
                    .font(.headline)
                if palace.isBodyPalace {
                    Text("身宮")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Text("宮位干支：\(palace.stemBranch.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(mainStarNames.isEmpty ? "本宮無主星" : "主星：\(mainStarNames.joined(separator: "、"))")
                .font(.subheadline)
            if !otherStarNames.isEmpty {
                Text("其他星曜：\(otherStarNames.joined(separator: "、"))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [
            palace.kind.displayName,
            "宮位干支\(palace.stemBranch.displayName)",
            mainStarNames.isEmpty ? "本宮無主星" : "主星\(mainStarNames.joined(separator: "、"))"
        ]
        if palace.isBodyPalace { parts.append("身宮位於此") }
        if !otherStarNames.isEmpty { parts.append("其他星曜\(otherStarNames.joined(separator: "、"))") }
        return parts.joined(separator: "，")
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
