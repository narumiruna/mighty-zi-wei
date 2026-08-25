import SwiftData
import SwiftUI

struct ChartJournalView: View {
    let chartID: UUID
    let chartName: String
    var suggestedLocationID = "chart.general"
    var suggestedTitle = "命盤筆記"

    @Environment(\.modelContext) private var modelContext
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

    var body: some View {
        List {
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
                        delete(notes: offsets.map { notes[$0] })
                    }
                }

                Button {
                    createsNewNote = true
                } label: {
                    Label("新增筆記", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("journal.addNote")
            }

            Section("稍後閱讀") {
                if bookmarks.isEmpty {
                    Text("在命盤解讀或 AI 回答點選「收藏」後，會顯示在這裡。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bookmarks) { insight in
                        InsightRow(insight: insight)
                    }
                    .onDelete { offsets in
                        delete(notes: offsets.map { bookmarks[$0] })
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

    private func delete(notes: [SavedInsight]) {
        notes.forEach(modelContext.delete)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "無法刪除本機內容。"
        }
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
    @Query private var allInsights: [SavedInsight]
    @State private var errorMessage: String?

    private var existing: SavedInsight? {
        guard let chartID else { return nil }
        return allInsights.first {
            $0.chartID == chartID
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
        .disabled(chartID == nil)
        .accessibilityHint(chartID == nil ? "請先儲存命盤" : "收藏會保留內容與命盤依據")
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
        guard let chartID else { return }
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
