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

                PrimaryPalaceGuide(
                    chart: chart,
                    assistantChart: assistantChart
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("自由探索十二宮")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("也可以直接選擇你現在最想了解的生活面向。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ChartOverview(
                        chart: chart,
                        name: displayName,
                        assistantChart: assistantChart
                    )
                }

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
            .buttonStyle(.borderedProminent)
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
                        .adaptive(minimum: 150),
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
    let assistantChart: ChartAssistantChart

    @Environment(AppNavigationState.self) private var navigation
    @Environment(ChartAssistantStore.self) private var assistantStore
    @AppStorage("learning.palace-understood") private var palaceTipUnderstood = false
    @AppStorage("learning.main-star-understood") private var mainStarTipUnderstood = false
    @AppStorage("learning.relation-understood") private var relationTipUnderstood = false
    @State private var showsWhy = false
    @State private var showsOtherFactors = false
    @State private var showsRelations = false
    @State private var showsRawData = false
    @State private var pendingQuestion: String?

    private var palace: ChartPalace { chart.palace(palaceKind) }
    private var stars: [StarPlacement] { chart.stars.filter { $0.palace == palaceKind } }
    private var mainStars: [StarPlacement] { stars.filter { $0.star.category == .main } }
    private var otherStars: [StarPlacement] { stars.filter { $0.star.category != .main } }
    private var transformations: [Transformation] { chart.transformations.filter { $0.palace == palaceKind } }
    private var relation: PalaceRelation { chart.relation(of: palaceKind) }
    private var learning: PalaceLearningContent { ChartLearningCatalog.palace(palaceKind) }

    private var facts: [ChartFact] {
        ChartFactBuilder().makeFacts(from: chart)
    }

    private var summary: String {
        PalaceLearningSummaryBuilder().make(
            palaceKind: palaceKind,
            mainStars: mainStars.map(\.star),
            facts: facts,
            seeds: InterpretationSeedBuilder().makeSeeds(from: facts)
        )
    }

    private var starNames: String {
        mainStars.isEmpty
            ? "從相關宮位一起理解"
            : mainStars.map(\.star.displayName).joined(separator: " × ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                palaceSummary

                if showsWhy {
                    mainStarExplanation
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                otherInfluences
                relatedAspects
                contextualQuestions
                rawChartData
            }
            .padding()
        }
        .navigationTitle(palace.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "切換命盤並清除本次 AI 對話？",
            isPresented: pendingQuestionIsPresented,
            titleVisibility: .visible
        ) {
            Button("切換並填入問題", role: .destructive) {
                guard let pendingQuestion else { return }
                assistantStore.select(assistantChart)
                assistantStore.draft = pendingQuestion
                self.pendingQuestion = nil
                navigation.selectedTab = .ai
            }
            Button("取消", role: .cancel) {
                pendingQuestion = nil
            }
        } message: {
            Text("目前 AI 對話使用另一張命盤。切換後會清除該次對話，但不會自動送出新問題。")
        }
    }

    private var pendingQuestionIsPresented: Binding<Bool> {
        Binding(
            get: { pendingQuestion != nil },
            set: { if !$0 { pendingQuestion = nil } }
        )
    }

    private var palaceSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(learning.focusTitle)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            Text(learning.purpose)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.title3.weight(.semibold))
                .lineSpacing(5)
                .textSelection(.enabled)

            Text(starNames)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)

            if !palaceTipUnderstood {
                LearningTipView(
                    title: "這個宮位在看什麼？",
                    message: "宮位可以先理解成生活中的一個面向。現在先從「\(learning.focusTitle)」開始。",
                    action: { palaceTipUnderstood = true }
                )
            }

            Button {
                withAnimation { showsWhy.toggle() }
            } label: {
                Label(
                    showsWhy ? "收合解讀原因" : "了解為什麼",
                    systemImage: showsWhy ? "chevron.up" : "chevron.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("palace.why")
            .accessibilityValue(showsWhy ? "已展開" : "已收合")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mainStarExplanation: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !mainStarTipUnderstood {
                LearningTipView(
                    title: "主星是什麼？",
                    message: "主星是這個宮位最主要的觀察角度。先理解每顆星，再回頭看它們如何同時出現在這裡。",
                    action: { mainStarTipUnderstood = true }
                )
            }

            Text("你的主要星曜")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            if mainStars.isEmpty {
                Text("本宮沒有主星。紫微斗數會再一起參考相關宮位，不代表這個面向沒有內容。")
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                ForEach(mainStars) { placement in
                    StarLearningLink(star: placement.star)
                }

                if mainStars.count > 1 {
                    Text("App 會分別參考這些主星已驗證的傾向，不會把尚未建立規則的組合說成固定結論。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("palace.why.content")
    }

    private var otherInfluences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("還有什麼會影響這個宮位？")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            if otherStars.isEmpty {
                Text("目前沒有其他星曜需要另外說明。")
                    .foregroundStyle(.secondary)
            } else {
                Text(otherStars.map(\.star.displayName).joined(separator: "、"))
                    .font(.headline)
                Text(
                    mainStars.isEmpty
                        ? "這些星曜會和相關宮位一起提供補充角度。需要時再逐一了解即可。"
                        : "這些星曜會補充主星的表現方式。需要時再逐一了解即可。"
                )
                .foregroundStyle(.secondary)

                Button(showsOtherFactors ? "收合其他影響" : "了解更多") {
                    withAnimation { showsOtherFactors.toggle() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("palace.otherStars")
                .accessibilityValue(showsOtherFactors ? "已展開" : "已收合")

                if showsOtherFactors {
                    VStack(spacing: 10) {
                        ForEach(otherStars) { placement in
                            StarLearningLink(star: placement.star)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var relatedAspects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("和這個宮位有關的其他面向")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text(relatedKinds.map { ChartLearningCatalog.palace($0).relatedLabel }.joined(separator: " · "))
                .font(.headline)
            Text("紫微斗數不只看單一宮位，也會一起參考這些生活面向。")
                .foregroundStyle(.secondary)

            Button(showsRelations ? "收合彼此關係" : "看看彼此的關係") {
                withAnimation { showsRelations.toggle() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("palace.relations")
            .accessibilityValue(showsRelations ? "已展開" : "已收合")

            if showsRelations {
                VStack(alignment: .leading, spacing: 12) {
                    if !relationTipUnderstood {
                        LearningTipView(
                            title: "這就是三方四正",
                            message: "本宮、兩個相互呼應的宮位與對面的宮位會一起參考。理解關係後，再記住術語即可。",
                            action: { relationTipUnderstood = true }
                        )
                    }

                    ForEach(relatedKinds) { kind in
                        NavigationLink {
                            PalaceDetailView(
                                chart: chart,
                                palaceKind: kind,
                                assistantChart: assistantChart
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ChartLearningCatalog.palace(kind).relatedLabel)
                                        .font(.headline)
                                    Text(kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .background(
                            .background,
                            in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
                        )
                    }

                    Text("這四個彼此關聯的宮位，在紫微斗數裡稱為「三方四正」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var relatedKinds: [PalaceKind] {
        relation.trines + [relation.opposite]
    }

    private var contextualQuestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接著想問什麼？")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("選擇後只會填入問題，不會自動送出或產生費用。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(Array(contextQuestions.enumerated()), id: \.offset) { index, question in
                Button {
                    prepareQuestion(question)
                } label: {
                    HStack {
                        Text(question)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("palace.question.\(index)")
            }
        }
    }

    private var contextQuestions: [String] {
        [
            "從命盤來看，\(learning.focusTitle)可能有什麼特色？",
            "這些星曜會如何影響\(learning.relatedLabel)？",
            "這個宮位有什麼值得我留意？"
        ]
    }

    private func prepareQuestion(_ question: String) {
        if assistantStore.requiresConfirmation(toSelect: assistantChart) {
            pendingQuestion = question
            return
        }
        assistantStore.select(assistantChart)
        assistantStore.draft = question
        navigation.selectedTab = .ai
    }

    private var rawChartData: some View {
        DisclosureGroup(isExpanded: $showsRawData) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("宮位干支", value: palace.stemBranch.displayName)
                    .accessibilityIdentifier("palace.data.stemBranch")
                if palace.isBodyPalace {
                    Label("身宮位於此宮", systemImage: "person.crop.circle")
                }
                Divider()
                LabeledContent(
                    "主星",
                    value: mainStars.isEmpty
                        ? "本宮無主星"
                        : mainStars.map(\.star.displayName).joined(separator: "、")
                )
                LabeledContent(
                    "其他星曜",
                    value: otherStars.isEmpty
                        ? "無"
                        : otherStars.map(\.star.displayName).joined(separator: "、")
                )
                if !transformations.isEmpty {
                    Divider()
                    ForEach(transformations) { transformation in
                        LabeledContent(
                            transformation.star.displayName,
                            value: transformation.kind.displayName
                        )
                    }
                }
                Divider()
                LabeledContent("三合宮", value: relation.trines.map(\.displayName).joined(separator: "、"))
                LabeledContent("對宮", value: relation.opposite.displayName)
            }
            .font(.footnote)
            .padding(.top, 10)
        } label: {
            Label("查看命盤資料", systemImage: "tablecells")
                .font(.headline)
        }
        .cardStyle()
        .accessibilityIdentifier("palace.data")
        .accessibilityValue(showsRawData ? "已展開" : "已收合")
    }
}

private struct StarLearningLink: View {
    let star: Star

    private var learning: StarLearningContent {
        ChartLearningCatalog.star(star)
    }

    var body: some View {
        NavigationLink {
            StarLearningView(star: star)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(star.displayName)
                        .font(.headline)
                        .accessibilityIdentifier("palace.star.name.\(star.rawValue)")
                    Text(learning.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                .background.secondary,
                in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
            )
        }
        .accessibilityIdentifier("palace.star.\(star.rawValue)")
        .accessibilityHint("點兩下進一步認識\(star.displayName)")
        .buttonStyle(.plain)
    }
}

private struct StarLearningView: View {
    let star: Star

    private var learning: StarLearningContent {
        ChartLearningCatalog.star(star)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ChartLearningCatalog.categoryTitle(for: star.category))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(star.displayName)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text(learning.keywords.joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)

                    Text(learning.summary)
                        .font(.title3)
                        .lineSpacing(5)
                }

                DisclosureGroup("看看可能的優勢與盲點") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("可能的優勢")
                                .font(.headline)
                            Text(learning.strengths)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("值得留意")
                                .font(.headline)
                            Text(learning.cautions)
                        }
                    }
                    .padding(.top, 10)
                }
                .cardStyle()
                .accessibilityIdentifier("star.details")

                DisclaimerView(compact: true)
            }
            .padding()
        }
        .navigationTitle(star.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LearningTipView: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "lightbulb")
                .font(.headline)
            Text(message)
                .font(.subheadline)
            Button("知道了", action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
        .accessibilityElement(children: .contain)
    }
}
