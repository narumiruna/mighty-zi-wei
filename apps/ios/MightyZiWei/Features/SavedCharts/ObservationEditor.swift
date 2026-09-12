import SwiftData
import SwiftUI

struct ObservationEditor: View {
  let chartID: UUID
  @Environment(\.dismiss) private var dismiss
  @Query private var charts: [SavedChart]

  private var savedChart: SavedChart? { charts.first { $0.id == chartID } }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("先選取一段本機基本解讀。下一步確認只保存這一段、當時依據與你的初步想法，不保存完整解讀或對話。")
            .font(.callout)
        }
        if let savedChart, let chart = try? savedChart.resolvedChart() {
          let facts = ChartFactBuilder().makeFacts(from: chart)
          let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)
          ForEach(InterpretationCategory.allCases) { category in
            Section(category.title) {
              ForEach(seeds.filter { $0.category == category }) { seed in
                NavigationLink {
                  ObservationSnapshotForm(
                    chart: savedChart, seed: seed, facts: facts, onSaved: { dismiss() })
                } label: {
                  Text(seed.meaning)
                }
                .accessibilityIdentifier("observation.select.\(seed.id)")
              }
            }
          }
        } else {
          Label("找不到可用的已儲存命盤，無法開始觀察。", systemImage: "exclamationmark.triangle")
        }
      }
      .navigationTitle("選取一段解讀")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
  }
}

private struct ObservationSnapshotForm: View {
  let chart: SavedChart
  let seed: InterpretationSeed
  let facts: [ChartFact]
  let onSaved: () -> Void
  @Environment(\.modelContext) private var modelContext
  @State private var initialThought = ""
  @State private var wantsReminder = false
  @State private var reviewDate =
    Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
  @State private var isSaving = false
  @State private var didSave = false
  @State private var message: String?

  var body: some View {
    Form {
      Section("將保存的單段文字") {
        Text(seed.meaning)
          .textSelection(.enabled)
          .accessibilityIdentifier("observation.preview")
        Text("來源：本機基本解讀；內容版本 1。不是專家審閱認證。")
          .font(.footnote).foregroundStyle(.secondary)
        DisclosureGroup("當時引用依據") {
          ForEach(facts.filter { seed.evidenceFactIDs.contains($0.id) }) { fact in
            Text(fact.displayText)
          }
        }
      }
      Section {
        TextField("當時怎麼想？（選填）", text: $initialThought, axis: .vertical)
          .lineLimit(4...10)
          .accessibilityIdentifier("observation.initialThought")
      } header: {
        Text("初步想法")
      } footer: {
        Text("儲存後不覆寫原始文字與想法。更正或新想法請新增回顧；仍可明確刪除觀察。")
      }
      Section {
        Toggle("設定回顧提醒", isOn: $wantsReminder)
          .accessibilityIdentifier("observation.reminder")
        if wantsReminder {
          DatePicker(
            "回顧時間", selection: $reviewDate, in: Date.now...,
            displayedComponents: [.date, .hourAndMinute])
        }
      } footer: {
        Text("日期由你選擇，不代表命盤事件。通知不含私人文字；通知授權失敗仍會儲存觀察。還原或同步不會自動設定此裝置的通知。")
      }
      Section {
        Text("快照與回顧只供私人反思，不會送給 AI、顯示於 Widget 或包含在命盤分享。主動加密備份會包含這些內容；iCloud 同步須在設定中另行同意。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("確認觀察快照")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("儲存觀察") { Task { await save() } }
          .disabled(isSaving || didSave)
          .accessibilityIdentifier("observation.save")
      }
    }
    .interactiveDismissDisabled(isSaving)
    .alert(didSave ? "觀察已儲存" : "無法儲存觀察", isPresented: messageBinding) {
      Button("好", role: .cancel) { if didSave { onSaved() } }
    } message: {
      Text(message ?? "請稍後再試。")
    }
  }

  private var messageBinding: Binding<Bool> {
    Binding(get: { message != nil }, set: { if !$0 { message = nil } })
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    do {
      let snapshot = try ObservationSnapshot.capture(
        seed: seed, facts: facts, chart: chart, initialThought: initialThought)
      let result = try await ObservationStore.saveObservation(
        chartID: chart.id, snapshot: snapshot, reviewDate: wantsReminder ? reviewDate : nil,
        modelContext: modelContext
      )
      didSave = true
      if let warning = result.reminderWarning { message = warning } else { onSaved() }
    } catch {
      message = (error as? LocalizedError)?.errorDescription ?? "本機資料寫入失敗，請再試一次。"
    }
  }
}
