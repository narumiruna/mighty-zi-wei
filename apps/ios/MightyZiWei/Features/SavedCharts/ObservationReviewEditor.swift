import SwiftData
import SwiftUI

struct ObservationReviewEditor: View {
  let observation: SavedObservation
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var content = ""
  @State private var outcome: SavedObservationReview.Outcome = .uncertain
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        if let snapshot = observation.snapshot {
          ObservationOriginalSections(snapshot: snapshot, createdAt: observation.createdAt)
        }
        Section {
          Picker("這次觀察", selection: $outcome) {
            ForEach(SavedObservationReview.Outcome.allCases) { outcome in
              Text(outcome.title).tag(outcome)
            }
          }
          .accessibilityIdentifier("observation.reviewOutcome")
          TextField("寫下實際觀察、不同之處或尚待確認的內容", text: $content, axis: .vertical)
            .lineLimit(5...12)
            .accessibilityIdentifier("observation.reviewContent")
        } header: {
          Text("這次的新回顧")
        } footer: {
          Text("這會新增獨立紀錄，不覆寫上方原文與初步想法。符合與否不是命理準確率。")
        }
      }
      .navigationTitle("新增回顧")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("儲存回顧") { save() }
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("observation.saveReview")
        }
      }
      .alert("無法儲存回顧", isPresented: errorBinding) {
        Button("好", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "請稍後再試。")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    do {
      try ObservationStore.addReview(
        observation: observation, content: content, outcome: outcome, modelContext: modelContext
      )
      dismiss()
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? "本機資料寫入失敗，請再試一次。"
    }
  }
}
