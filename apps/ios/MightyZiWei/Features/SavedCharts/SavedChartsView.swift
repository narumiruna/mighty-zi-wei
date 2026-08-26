import SwiftData
import SwiftUI

struct SavedInsightDeletionSummary: Equatable {
    let noteCount: Int
    let bookmarkCount: Int

    init(insights: [SavedInsight]) {
        noteCount = insights.count { $0.kind == .note }
        bookmarkCount = insights.count { $0.kind == .bookmark }
    }

    var message: String {
        "將一併永久刪除 \(noteCount) 則私人筆記與 \(bookmarkCount) 則收藏。這個動作無法復原。"
    }
}

struct SavedChartDuplicateKey: Hashable {
    let profile: BirthProfile

    init(_ profile: BirthProfile) {
        self.profile = profile
    }
}

struct SavedChartTagSelectionPolicy: Sendable {
    func validSelection(_ selection: String?, availableTags: [String]) -> String? {
        guard let selection, availableTags.contains(selection) else { return nil }
        return selection
    }
}

enum SavedChartCreatedDateFilter: String, CaseIterable, Identifiable {
    case all
    case sevenDays
    case thirtyDays
    case thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "不限日期"
        case .sevenDays: "最近 7 天"
        case .thirtyDays: "最近 30 天"
        case .thisYear: "今年建立"
        }
    }

    func includes(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            true
        case .sevenDays:
            date >= calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays:
            date >= calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        case .thisYear:
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        }
    }
}

private struct ExternalSavedDestination: Identifiable, Hashable {
    enum Kind: Hashable { case chart, journal }
    let id: UUID
    let kind: Kind
}

struct SavedChartsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationState.self) private var navigation
    @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]
    @Query private var insights: [SavedInsight]

    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var createdDateFilter: SavedChartCreatedDateFilter = .all
    @State private var externalDestination: ExternalSavedDestination?
    @State private var chartToRename: SavedChart?
    @State private var chartToEditTags: SavedChart?
    @State private var chartToDelete: SavedChart?
    @State private var proposedName = ""
    @State private var proposedTags = ""
    @State private var showsDeleteAllConfirmation = false
    @State private var errorMessage: String?

    private var availableTags: [String] {
        Array(Set(charts.flatMap(\.tags))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var duplicateChartIDs: Set<UUID> {
        let valid = charts.compactMap { chart in
            (try? chart.birthProfile()).map { (SavedChartDuplicateKey($0), chart) }
        }
        let grouped = Dictionary(grouping: valid, by: \.0)
        return Set(grouped.values.filter { $0.count > 1 }.flatMap { $0.map(\.1.id) })
    }

    private var filteredCharts: [SavedChart] {
        charts.filter { chart in
            chart.matchesSearch(searchText)
                && (selectedTag.map(chart.tags.contains) ?? true)
                && createdDateFilter.includes(chart.createdAt)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        NavigationStack {
            screenContent
            .navigationTitle("已儲存命盤")
            .searchable(text: $searchText, prompt: "搜尋姓名、標籤或建立日期")
            .navigationDestination(item: $externalDestination) { destination in
                externalDestinationView(destination)
            }
            .task { handleExternalDestination() }
            .onChange(of: navigation.requestedSavedDestination) { _, _ in
                handleExternalDestination()
            }
            .onChange(of: availableTags) { _, tags in
                selectedTag = SavedChartTagSelectionPolicy().validSelection(
                    selectedTag,
                    availableTags: tags
                )
            }
            .toolbar { moreActionsToolbar }
            .alert("編輯自訂標籤", isPresented: tagsArePresented) {
                TextField("例如：家人、朋友、個案", text: $proposedTags)
                Button("取消", role: .cancel) {}
                Button("儲存") { saveTags() }
            } message: {
                Text("以逗號、頓號或換行分隔，最多 20 個標籤。")
            }
            .alert("重新命名", isPresented: renameIsPresented) {
                TextField("命盤名稱", text: $proposedName)
                Button("取消", role: .cancel) {}
                Button("儲存") { rename() }
            } message: {
                Text("名稱只會儲存在本機。")
            }
            .confirmationDialog(
                "刪除這張命盤？",
                isPresented: deleteIsPresented,
                titleVisibility: .visible
            ) {
                Button("刪除命盤、筆記與收藏", role: .destructive) {
                    guard let chartToDelete else { return }
                    delete(chartToDelete)
                    self.chartToDelete = nil
                }
                Button("取消", role: .cancel) {
                    chartToDelete = nil
                }
            } message: {
                Text(singleDeletionSummary.message)
            }
            .confirmationDialog(
                "刪除所有已儲存命盤？",
                isPresented: $showsDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("刪除所有命盤、筆記與收藏", role: .destructive) { deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(SavedInsightDeletionSummary(insights: insights).message)
            }
            .alert("操作未完成", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        if charts.isEmpty {
            EmptyStateView(
                symbol: "rectangle.stack",
                title: "還沒有已儲存命盤",
                message: "完成排盤後，點選右上角的儲存按鈕即可保留命盤。"
            )
        } else {
            List {
                Section {
                    Picker("建立日期", selection: $createdDateFilter) {
                        ForEach(SavedChartCreatedDateFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    if !availableTags.isEmpty {
                        Picker("標籤", selection: $selectedTag) {
                            Text("所有標籤").tag(String?.none)
                            ForEach(availableTags, id: \.self) { tag in
                                Text(tag).tag(String?.some(tag))
                            }
                        }
                    }
                } header: {
                    Text("搜尋篩選")
                }

                if filteredCharts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }

                ForEach(filteredCharts) { chart in
                    chartRow(chart)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var moreActionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if charts.count >= 2 {
                    NavigationLink {
                        DualChartComparisonView()
                    } label: {
                        Label("雙人互動參考", systemImage: "person.2")
                    }
                }
                NavigationLink {
                    BackupManagementView()
                } label: {
                    Label("加密備份與還原", systemImage: "lock.doc")
                }
                if !charts.isEmpty {
                    Divider()
                    Button("刪除所有已儲存命盤", systemImage: "trash", role: .destructive) {
                        showsDeleteAllConfirmation = true
                    }
                }
            } label: {
                Label("更多操作", systemImage: "ellipsis.circle")
            }
        }
    }

    private func chartRow(_ chart: SavedChart) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                SavedChartLoaderView(savedChart: chart)
            } label: {
                SavedChartRow(
                    chart: chart,
                    isDuplicate: duplicateChartIDs.contains(chart.id)
                )
            }
            Menu {
                Button {
                    togglePinned(chart)
                } label: {
                    Label(
                        chart.isPinned ? "取消釘選" : "釘選",
                        systemImage: chart.isPinned ? "pin.slash" : "pin"
                    )
                }
                Button {
                    chartToEditTags = chart
                    proposedTags = chart.tags.joined(separator: "、")
                } label: {
                    Label("編輯標籤", systemImage: "tag")
                }
                Button {
                    chartToRename = chart
                    proposedName = chart.name
                } label: {
                    Label("重新命名", systemImage: "pencil")
                }
            } label: {
                Label("命盤分類操作", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                togglePinned(chart)
            } label: {
                Label(
                    chart.isPinned ? "取消釘選" : "釘選",
                    systemImage: chart.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(.orange)
            Button {
                chartToRename = chart
                proposedName = chart.name
            } label: {
                Label("重新命名", systemImage: "pencil")
            }
            .tint(.accentColor)
            Button {
                chartToEditTags = chart
                proposedTags = chart.tags.joined(separator: "、")
            } label: {
                Label("編輯標籤", systemImage: "tag")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                chartToDelete = chart
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func externalDestinationView(_ destination: ExternalSavedDestination) -> some View {
        if let chart = charts.first(where: { $0.id == destination.id }) {
            switch destination.kind {
            case .chart:
                SavedChartLoaderView(savedChart: chart)
            case .journal:
                ChartJournalView(
                    chartID: chart.id,
                    chartName: chart.name,
                    startsWithNewNote: true
                )
            }
        } else {
            ContentUnavailableView(
                "找不到釘選命盤",
                systemImage: "pin.slash",
                description: Text("請先在已儲存命盤中釘選一張常用命盤。")
            )
        }
    }

    private func handleExternalDestination() {
        guard let request = navigation.requestedSavedDestination else { return }
        navigation.requestedSavedDestination = nil
        switch request {
        case .chart(let id):
            externalDestination = ExternalSavedDestination(id: id, kind: .chart)
        case .journal(let id):
            externalDestination = ExternalSavedDestination(id: id, kind: .journal)
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(
            get: { chartToRename != nil },
            set: { if !$0 { chartToRename = nil } }
        )
    }

    private var tagsArePresented: Binding<Bool> {
        Binding(
            get: { chartToEditTags != nil },
            set: { if !$0 { chartToEditTags = nil } }
        )
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(
            get: { chartToDelete != nil },
            set: { if !$0 { chartToDelete = nil } }
        )
    }

    private var singleDeletionSummary: SavedInsightDeletionSummary {
        guard let chartToDelete else {
            return SavedInsightDeletionSummary(insights: [])
        }
        return SavedInsightDeletionSummary(
            insights: insights.filter { $0.chartID == chartToDelete.id }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func rename() {
        guard let chartToRename else { return }
        do {
            try chartToRename.rename(to: proposedName)
            try modelContext.save()
            self.chartToRename = nil
        } catch {
            errorMessage = "無法重新命名命盤。"
        }
    }

    private func saveTags() {
        guard let chartToEditTags else { return }
        let separators = CharacterSet(charactersIn: ",，、\n")
        chartToEditTags.updateTags(
            proposedTags.components(separatedBy: separators)
        )
        do {
            try modelContext.save()
            self.chartToEditTags = nil
        } catch {
            modelContext.rollback()
            errorMessage = "無法更新命盤標籤。"
        }
    }

    private func togglePinned(_ chart: SavedChart) {
        chart.setPinned(!chart.isPinned)
        saveChanges(errorText: "無法更新釘選狀態。") {
            PinnedChartShortcut.reconcile(charts: charts)
        }
    }

    private func delete(_ chart: SavedChart) {
        let deletedInsights = insights.filter { $0.chartID == chart.id }
        let reminderIdentifiers = deletedInsights.compactMap(\.reminderIdentifier)
        ICloudSyncService.recordDeletion(
            entityID: chart.id,
            entityType: "SavedChart",
            modelContext: modelContext
        )
        deletedInsights.forEach { insight in
            ICloudSyncService.recordDeletion(
                entityID: insight.id,
                entityType: "SavedInsight",
                modelContext: modelContext
            )
            modelContext.delete(insight)
        }
        modelContext.delete(chart)
        saveChanges(errorText: "無法刪除命盤。") {
            reminderIdentifiers.forEach {
                ReviewReminderScheduler().cancel(identifier: $0)
            }
            PinnedChartShortcut.reconcile(charts: charts.filter { $0.id != chart.id })
        }
    }

    private func deleteAll() {
        let reminderIdentifiers = insights.compactMap(\.reminderIdentifier)
        do {
            charts.forEach {
                ICloudSyncService.recordDeletion(
                    entityID: $0.id,
                    entityType: "SavedChart",
                    modelContext: modelContext
                )
            }
            insights.forEach {
                ICloudSyncService.recordDeletion(
                    entityID: $0.id,
                    entityType: "SavedInsight",
                    modelContext: modelContext
                )
            }
            try modelContext.delete(model: SavedInsight.self)
            try modelContext.delete(model: SavedChart.self)
            try modelContext.save()
            reminderIdentifiers.forEach {
                ReviewReminderScheduler().cancel(identifier: $0)
            }
            PinnedChartShortcut.reconcile(charts: [])
        } catch {
            modelContext.rollback()
            errorMessage = "無法刪除所有已儲存命盤。"
        }
    }

    private func saveChanges(errorText: String, afterSave: () -> Void = {}) {
        do {
            try modelContext.save()
            afterSave()
        } catch {
            modelContext.rollback()
            errorMessage = errorText
        }
    }
}

struct SavedChartRow: View {
    let chart: SavedChart
    var isDuplicate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if chart.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("已釘選")
                }
                Text(chart.name)
                    .font(.headline)
                if isDuplicate {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("有相同出生資料的命盤")
                }
            }
            if let profile = try? chart.birthProfile() {
                Text(dateText(profile))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(profile.timeZoneIdentifier)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if !chart.tags.isEmpty {
                Text(chart.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
            }
            if isDuplicate {
                Text("這份出生資料也存在於其他命盤")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func dateText(_ profile: BirthProfile) -> String {
        let date = profile.localDate
        let time = profile.localTime
        return String(format: "%04d/%02d/%02d　%02d:%02d", date.year, date.month, date.day, time.hour, time.minute)
    }
}

struct SavedChartContentRevision: Hashable, Sendable {
    let birthProfileData: Data
    let ruleSetID: String
    let ruleSetVersion: Int
    let appSchemaVersion: Int

    init(savedChart: SavedChart) {
        birthProfileData = savedChart.birthProfileData
        ruleSetID = savedChart.ruleSetID
        ruleSetVersion = savedChart.ruleSetVersion
        appSchemaVersion = savedChart.appSchemaVersion
    }
}

struct SavedChartLoaderView: View {
    let savedChart: SavedChart
    @Environment(\.modelContext) private var modelContext
    @State private var chart: ZiWeiChart?
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let chart {
                ChartView(
                    chart: chart,
                    name: savedChart.name,
                    allowsSaving: false,
                    notice: notice,
                    savedChartID: savedChart.id
                )
            } else if let errorMessage {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "無法開啟命盤",
                    message: errorMessage
                )
            } else {
                ProgressView("正在準備命盤…")
            }
        }
        .task(id: SavedChartContentRevision(savedChart: savedChart)) {
            load()
        }
    }

    private func load() {
        errorMessage = nil
        let current = RuleSetIdentity.taiwanTraditionalSanheV1
        let needsRecalculation = savedChart.ruleSetID != current.id
            || savedChart.ruleSetVersion != current.version
            || savedChart.appSchemaVersion != SavedChart.schemaVersion
        do {
            chart = try savedChart.resolvedChart()
            if needsRecalculation {
                notice = "這張命盤已依目前規則重新計算，結果可能與舊版不同。"
                try modelContext.save()
            }
        } catch {
            errorMessage = "本機資料可能已損毀，請刪除這張命盤後重新建立。"
        }
    }
}
