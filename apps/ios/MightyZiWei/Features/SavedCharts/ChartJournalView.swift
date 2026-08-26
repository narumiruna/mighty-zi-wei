import SwiftData
import SwiftUI

struct ChartJournalView: View {
    let chartID: UUID
    let chartName: String
    var suggestedLocationID = "chart.general"
    var suggestedTitle = "命盤筆記"

    @Environment(\.modelContext) private var modelContext
    @Query private var savedCharts: [SavedChart]
    @Query(sort: \SavedInsight.updatedAt, order: .reverse) private var allInsights: [SavedInsight]
    @State private var editingInsight: SavedInsight?
    @State private var createsNewNote = false
    @State private var errorMessage: String?

    private var insights: [SavedInsight] {
        allInsights.filter { $0.chartID == chartID }
    }

    private var notes: [SavedInsight] {
        insights.filter { $0.kind == .note }
    }

    private var bookmarks: [SavedInsight] {
        insights.filter { $0.kind == .bookmark }
    }

    private var chartExists: Bool {
        savedCharts.contains { $0.id == chartID }
    }

    var body: some View {
        List {
            if !chartExists {
                Section {
                    Label("這張命盤已刪除，無法再新增或修改內容。", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("筆記與收藏由 App 保存在本機，也可能依 iOS 設定納入裝置備份或移轉；只有你主動建立加密備份時，App 才會匯出這些內容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("私人筆記") {
                if notes.isEmpty {
                    Text("還沒有筆記")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { insight in
                        Button {
                            editingInsight = insight
                        } label: {
                            InsightRow(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        delete(insights: offsets.map { notes[$0] })
                    }
                }

                Button {
                    createsNewNote = true
                } label: {
                    Label("新增筆記", systemImage: "square.and.pencil")
                }
                .disabled(!chartExists)
                .accessibilityIdentifier("journal.addNote")
            }

            Section("稍後閱讀") {
                if bookmarks.isEmpty {
                    Text("在命盤解讀或 AI 回答點選「收藏」後，會顯示在這裡。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bookmarks) { insight in
                        NavigationLink {
                            SavedBookmarkDetailView(insight: insight)
                        } label: {
                            InsightRow(insight: insight)
                        }
                        .accessibilityIdentifier("journal.bookmark")
                    }
                    .onDelete { offsets in
                        delete(insights: offsets.map { bookmarks[$0] })
                    }
                }
            }
        }
        .navigationTitle(chartName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $createsNewNote) {
            InsightNoteEditor(
                chartID: chartID,
                locationID: suggestedLocationID,
                initialTitle: suggestedTitle
            )
        }
        .sheet(item: $editingInsight) { insight in
            InsightNoteEditor(
                chartID: chartID,
                locationID: insight.locationID,
                initialTitle: insight.title,
                insight: insight
            )
        }
        .alert("操作未完成", isPresented: errorIsPresented) {
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

    private func delete(insights: [SavedInsight]) {
        insights.forEach(modelContext.delete)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "無法刪除本機內容。"
        }
    }
}

private struct SavedBookmarkDetailView: View {
    let insight: SavedInsight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
                Text(insight.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(insight.content)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("journal.bookmarkDetail.content")
                if !insight.evidenceFactIDs.isEmpty {
                    Label(
                        "保留 \(insight.evidenceFactIDs.count) 項命盤依據",
                        systemImage: "checkmark.seal"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("收藏內容")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InsightRow: View {
    let insight: SavedInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(insight.title)
                    .font(.headline)
                Spacer()
                if insight.marker != .none {
                    Text(insight.marker.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Text(insight.content)
                .font(.subheadline)
                .lineLimit(3)
            if !insight.evidenceFactIDs.isEmpty {
                Label("保留 \(insight.evidenceFactIDs.count) 項命盤依據", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct InsightNoteEditor: View {
    let chartID: UUID
    let locationID: String
    let initialTitle: String
    var insight: SavedInsight?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedCharts: [SavedChart]
    @State private var title: String
    @State private var content: String
    @State private var marker: SavedInsight.Marker
    @State private var errorMessage: String?

    init(
        chartID: UUID,
        locationID: String,
        initialTitle: String,
        insight: SavedInsight? = nil
    ) {
        self.chartID = chartID
        self.locationID = locationID
        self.initialTitle = initialTitle
        self.insight = insight
        _title = State(initialValue: insight?.title ?? initialTitle)
        _content = State(initialValue: insight?.content ?? "")
        _marker = State(initialValue: insight?.marker ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("內容") {
                    TextField("標題", text: $title)
                    TextField("寫下想法或之後要觀察的內容", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                        .accessibilityIdentifier("journal.noteContent")
                }

                Section("自我觀察") {
                    Picker("標記", selection: $marker) {
                        ForEach(SavedInsight.Marker.allCases, id: \.rawValue) { marker in
                            Text(marker.title).tag(marker)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(insight == nil ? "新增筆記" : "編輯筆記")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("journal.saveNote")
                }
            }
            .alert("無法儲存筆記", isPresented: errorIsPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知錯誤")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard savedCharts.contains(where: { $0.id == chartID }) else {
            errorMessage = "這張命盤已刪除，無法儲存筆記。"
            return
        }
        let target = insight ?? SavedInsight(
            chartID: chartID,
            kind: .note,
            locationID: locationID,
            title: initialTitle,
            content: ""
        )
        target.updateNote(title: title, content: content, marker: marker)
        if insight == nil {
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "本機資料寫入失敗，請再試一次。"
        }
    }
}

struct InsightBookmarkButton: View {
    let chartID: UUID?
    let locationID: String
    let title: String
    let content: String
    let evidenceFactIDs: [String]

    @Environment(\.modelContext) private var modelContext
    @Query private var savedCharts: [SavedChart]
    @Query private var allInsights: [SavedInsight]
    @State private var errorMessage: String?

    private var validChartID: UUID? {
        guard let chartID,
              savedCharts.contains(where: { $0.id == chartID }) else {
            return nil
        }
        return chartID
    }

    private var existing: SavedInsight? {
        guard let validChartID else { return nil }
        return allInsights.first {
            $0.chartID == validChartID
                && $0.kind == .bookmark
                && $0.locationID == locationID
        }
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            Label(
                existing == nil ? "收藏" : "已收藏",
                systemImage: existing == nil ? "bookmark" : "bookmark.fill"
            )
        }
        .disabled(validChartID == nil)
        .accessibilityHint(validChartID == nil ? "請先儲存命盤" : "收藏會保留內容與命盤依據")
        .alert("操作未完成", isPresented: errorIsPresented) {
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

    private func toggle() {
        guard let chartID = validChartID else { return }
        if let existing {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedInsight.bookmark(
                chartID: chartID,
                locationID: locationID,
                title: title,
                content: content,
                evidenceFactIDs: evidenceFactIDs
            ))
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "無法更新本機收藏。"
        }
    }
}
