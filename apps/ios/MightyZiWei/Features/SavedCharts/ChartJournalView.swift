import SwiftData
import SwiftUI

struct ChartJournalView: View {
  let chartID: UUID
  let chartName: String
  var suggestedLocationID = "chart.general"
  var suggestedTitle = "命盤筆記"
  var startsWithNewNote = false

  @Environment(\.modelContext) private var modelContext
  @Query private var savedCharts: [SavedChart]
  @Query(sort: \SavedInsight.updatedAt, order: .reverse) private var allInsights: [SavedInsight]
  @Query(sort: \SavedObservation.createdAt, order: .reverse) private var allObservations:
    [SavedObservation]
  @State private var editingInsight: SavedInsight?
  @State private var createsNewNote = false
  @State private var startsObservation = false
  @State private var errorMessage: String?

  private var insights: [SavedInsight] {
    allInsights.filter { $0.chartID == chartID }
  }

  private var notes: [SavedInsight] {
    insights.filter { $0.kind == .note }.sorted { $0.createdAt > $1.createdAt }
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
        Text("筆記、收藏與觀察保存在本機，也可能納入 iOS 裝置備份或移轉。你可主動建立加密備份；觀察與回顧的 iCloud 同步需要另行同意，不會傳給 AI。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        ForEach(allObservations.filter { $0.chartID == chartID }) { observation in
          NavigationLink {
            ObservationDetailView(observation: observation)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(observation.snapshot?.selectedText ?? "無法讀取觀察快照")
                .lineLimit(2)
              Text(observation.createdAt, format: .dateTime.year().month().day())
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("journal.observation")
        }
        Button("開始觀察", systemImage: "text.badge.plus") {
          startsObservation = true
        }
        .disabled(!chartExists)
        .accessibilityIdentifier("journal.startObservation")
      } header: {
        Text("觀察與前後回顧")
      } footer: {
        Text("只保存你選取的單段解讀與當時想法。之後新增回顧，不覆寫原文；主觀符合與否不代表命理準確率。")
      }

      Section {
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
      } header: {
        Text("私人筆記")
      } footer: {
        Text("回顧提醒只使用你選擇的日期，不會根據命盤推算吉凶或事件。")
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
    .task {
      if startsWithNewNote, chartExists, editingInsight == nil {
        createsNewNote = true
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $startsObservation) {
      ObservationEditor(chartID: chartID)
    }
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
    let reminderIdentifiers = insights.compactMap(\.reminderIdentifier)
    for insight in insights {
      ICloudSyncService.recordDeletion(
        entityID: insight.id,
        entityType: "SavedInsight",
        modelContext: modelContext
      )
      modelContext.delete(insight)
    }
    do {
      try modelContext.save()
      for identifier in reminderIdentifiers {
        ReviewReminderScheduler().cancel(identifier: identifier)
      }
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
        Text(versionDescription)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("journal.bookmarkDetail.versionLimitation")
        NavigationLink {
          InterpretationSourceView(
            seedIDs: insight.evidenceSeedIDs,
            factIDs: insight.evidenceFactIDs,
            contentVersion: insight.interpretationContentVersion
          )
        } label: {
          Label("查看本段引用依據", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("journal.bookmarkDetail.sources")
        if !insight.evidenceSeedIDs.isEmpty {
          Label(
            "保留 \(insight.evidenceSeedIDs.count) 項原始解讀引用",
            systemImage: "text.quote"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
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

  private var versionDescription: String {
    guard let version = insight.interpretationContentVersion else {
      return "來源版本未保存。原文與引用僅供歷史閱讀，不回填目前規則或審閱認證。"
    }
    return "解讀內容版本：\(version)"
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
      HStack(spacing: 10) {
        Label(insight.linkedContentTitle, systemImage: "link")
        Text(insight.createdAt, format: .dateTime.year().month().day())
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      if let reviewDate = insight.reviewDate {
        Label(
          "\(reviewDate.formatted(date: .abbreviated, time: .shortened)) 回顧",
          systemImage: "bell"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
      if !insight.evidenceSeedIDs.isEmpty {
        Label(
          "保留 \(insight.evidenceSeedIDs.count) 項原始解讀引用",
          systemImage: "text.quote"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
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

private struct NoteLinkTarget: Identifiable, Hashable {
  let id: String
  let title: String

  static let all: [NoteLinkTarget] =
    [
      NoteLinkTarget(id: "chart.general", title: "整張命盤")
    ]
    + PalaceKind.allCases.map {
      NoteLinkTarget(id: "palace.\($0.rawValue)", title: $0.displayName)
    }
    + InterpretationCategory.allCases.map {
      NoteLinkTarget(id: "interpretation.\($0.rawValue)", title: "解讀：\($0.title)")
    }
}

private enum ReviewReminderChoice: String, CaseIterable, Identifiable {
  case none
  case oneMonth
  case threeMonths
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: "不提醒"
    case .oneMonth: "一個月後"
    case .threeMonths: "三個月後"
    case .custom: "自訂日期"
    }
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
  @State private var selectedLocationID: String
  @State private var selectedEvidenceIDs: Set<String>
  @State private var reminderChoice: ReviewReminderChoice
  @State private var customReviewDate: Date
  @State private var isSaving = false
  @State private var savedWithReminderWarning = false
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
    _selectedLocationID = State(initialValue: insight?.locationID ?? locationID)
    _selectedEvidenceIDs = State(initialValue: Set(insight?.evidenceFactIDs ?? []))
    _reminderChoice = State(initialValue: insight?.reviewDate == nil ? .none : .custom)
    _customReviewDate = State(
      initialValue: insight?.reviewDate
        ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)
        ?? .now.addingTimeInterval(7_776_000)
    )
  }

  private var savedChart: SavedChart? {
    savedCharts.first { $0.id == chartID }
  }

  private var availableFacts: [ChartFact] {
    guard let savedChart,
      let chart = try? savedChart.resolvedChart()
    else { return [] }
    return ChartFactBuilder().makeFacts(from: chart)
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

        Section("連結命盤內容") {
          Picker("連結到", selection: $selectedLocationID) {
            ForEach(NoteLinkTarget.all) { target in
              Text(target.title).tag(target.id)
            }
          }

          if !availableFacts.isEmpty {
            DisclosureGroup("連結已驗證命盤依據（選填）") {
              ForEach(availableFacts) { fact in
                Button {
                  if selectedEvidenceIDs.contains(fact.id) {
                    selectedEvidenceIDs.remove(fact.id)
                  } else {
                    selectedEvidenceIDs.insert(fact.id)
                  }
                } label: {
                  Label(
                    fact.displayText,
                    systemImage: selectedEvidenceIDs.contains(fact.id)
                      ? "checkmark.circle.fill"
                      : "circle"
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        Section("自我觀察") {
          Picker("標記", selection: $marker) {
            ForEach(SavedInsight.Marker.allCases, id: \.rawValue) { marker in
              Text(marker.title).tag(marker)
            }
          }
          .pickerStyle(.segmented)
        }

        Section {
          Picker("回顧提醒", selection: $reminderChoice) {
            ForEach(ReviewReminderChoice.allCases) { choice in
              Text(choice.title).tag(choice)
            }
          }
          if reminderChoice == .custom {
            DatePicker(
              "回顧日期",
              selection: $customReviewDate,
              in: Date.now...,
              displayedComponents: [.date, .hourAndMinute]
            )
          }
        } header: {
          Text("回顧提醒")
        } footer: {
          Text("日期完全由你設定，只提醒回顧自己的筆記，不代表命盤事件、吉日或凶日。")
        }
      }
      .navigationTitle(insight == nil ? "新增筆記" : "編輯筆記")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("儲存") { Task { await save() } }
            .disabled(
              isSaving
                || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("journal.saveNote")
        }
      }
      .alert(savedWithReminderWarning ? "筆記已儲存" : "無法儲存筆記", isPresented: errorIsPresented) {
        Button("好", role: .cancel) {
          if savedWithReminderWarning { dismiss() }
        }
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

  private var selectedReviewDate: Date? {
    switch reminderChoice {
    case .none:
      nil
    case .oneMonth:
      Calendar.current.date(byAdding: .month, value: 1, to: .now)
    case .threeMonths:
      Calendar.current.date(byAdding: .month, value: 3, to: .now)
    case .custom:
      customReviewDate
    }
  }

  @MainActor
  private func save() async {
    guard let savedChart else {
      errorMessage = "這張命盤已刪除，無法儲存筆記。"
      return
    }
    isSaving = true
    defer { isSaving = false }
    let target =
      insight
      ?? SavedInsight(
        chartID: chartID,
        kind: .note,
        locationID: selectedLocationID,
        title: initialTitle,
        content: ""
      )
    let oldReminderIdentifier = target.reminderIdentifier
    var newReminderIdentifier: String?
    if let reviewDate = selectedReviewDate {
      do {
        newReminderIdentifier = try await ReviewReminderScheduler().schedule(
          insightID: target.id,
          chartName: savedChart.name,
          title: title.trimmingCharacters(in: .whitespacesAndNewlines),
          date: reviewDate
        )
      } catch {
        savedWithReminderWarning = true
        newReminderIdentifier = oldReminderIdentifier
      }
    }
    guard savedCharts.contains(where: { $0.id == chartID }) else {
      if newReminderIdentifier != oldReminderIdentifier {
        ReviewReminderScheduler().cancel(identifier: newReminderIdentifier)
      }
      savedWithReminderWarning = false
      errorMessage = "這張命盤已刪除，無法儲存筆記。"
      return
    }
    target.updateNote(
      title: title,
      content: content,
      marker: marker,
      locationID: selectedLocationID,
      evidenceFactIDs: Array(selectedEvidenceIDs).sorted(),
      reviewDate: savedWithReminderWarning ? target.reviewDate : selectedReviewDate,
      reminderIdentifier: newReminderIdentifier
    )
    if insight == nil {
      modelContext.insert(target)
    }
    do {
      try modelContext.save()
      if oldReminderIdentifier != newReminderIdentifier {
        ReviewReminderScheduler().cancel(identifier: oldReminderIdentifier)
      }
      if savedWithReminderWarning {
        errorMessage = "筆記已儲存，但新的提醒未設定；原有提醒未變更。你仍可隨時回顧筆記。"
      } else {
        dismiss()
      }
    } catch {
      savedWithReminderWarning = false
      modelContext.rollback()
      if newReminderIdentifier != oldReminderIdentifier {
        ReviewReminderScheduler().cancel(identifier: newReminderIdentifier)
      }
      errorMessage = "本機資料寫入失敗，請再試一次。"
    }
  }
}

struct InsightBookmarkButton: View {
  let chartID: UUID?
  let locationID: String
  let title: String
  let content: String
  let evidenceSeedIDs: [String]
  let evidenceFactIDs: [String]
  let interpretationContentVersion: String?

  @Environment(\.modelContext) private var modelContext
  @Query private var savedCharts: [SavedChart]
  @Query private var allInsights: [SavedInsight]
  @State private var errorMessage: String?

  private var validChartID: UUID? {
    guard let chartID,
      savedCharts.contains(where: { $0.id == chartID })
    else {
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

  private var matchesCurrentContent: Bool {
    existing?.matchesBookmark(
      title: title,
      content: content,
      evidenceSeedIDs: evidenceSeedIDs,
      evidenceFactIDs: evidenceFactIDs,
      interpretationContentVersion: interpretationContentVersion
    ) == true
  }

  private var buttonTitle: String {
    guard existing != nil else { return "收藏" }
    return matchesCurrentContent ? "已收藏" : "更新收藏"
  }

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Button {
        toggle()
      } label: {
        Label(
          buttonTitle,
          systemImage: matchesCurrentContent ? "bookmark.fill" : "bookmark"
        )
      }
      .disabled(validChartID == nil)
      .accessibilityHint(
        validChartID == nil
          ? "先儲存命盤才能收藏"
          : "收藏會保留內容與命盤依據"
      )

      if validChartID == nil {
        Text("先儲存命盤才能收藏")
          .font(.callout.weight(.medium))
          .foregroundStyle(Color.primary)
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("bookmark.disabledReason")
      }
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

  private func toggle() {
    guard let chartID = validChartID else { return }
    if let existing {
      if matchesCurrentContent {
        ICloudSyncService.recordDeletion(
          entityID: existing.id,
          entityType: "SavedInsight",
          modelContext: modelContext
        )
        modelContext.delete(existing)
      } else {
        existing.updateBookmark(
          title: title,
          content: content,
          evidenceSeedIDs: evidenceSeedIDs,
          evidenceFactIDs: evidenceFactIDs,
          interpretationContentVersion: interpretationContentVersion
        )
      }
    } else {
      modelContext.insert(
        SavedInsight.bookmark(
          chartID: chartID,
          locationID: locationID,
          title: title,
          content: content,
          evidenceSeedIDs: evidenceSeedIDs,
          evidenceFactIDs: evidenceFactIDs,
          interpretationContentVersion: interpretationContentVersion
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
