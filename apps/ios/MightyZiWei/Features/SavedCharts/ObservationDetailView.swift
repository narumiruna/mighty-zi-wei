import SwiftData
import SwiftUI

struct ObservationDetailView: View {
  let observation: SavedObservation
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var charts: [SavedChart]
  @Query private var observations: [SavedObservation]
  @Query(sort: \SavedObservationReview.createdAt) private var allReviews: [SavedObservationReview]
  @State private var addsReview = false
  @State private var confirmsDeletion = false
  @State private var reviewToDelete: SavedObservationReview?
  @State private var errorMessage: String?

  private var reviews: [SavedObservationReview] {
    allReviews.filter { $0.observationID == observation.id }
  }

  private var parentExists: Bool {
    charts.contains { $0.id == observation.chartID }
      && observations.contains { $0.id == observation.id }
  }

  var body: some View {
    List {
      if !parentExists {
        Label("這份觀察或所屬命盤已刪除。", systemImage: "info.circle")
      } else if let snapshot = observation.snapshot {
        ObservationOriginalSections(snapshot: snapshot, createdAt: observation.createdAt)
        Section {
          Button("新增回顧", systemImage: "square.and.pencil") { addsReview = true }
            .accessibilityIdentifier("observation.addReview")
          if reviews.isEmpty {
            Text("還沒有後續回顧。回顧不會覆寫原始想法。")
              .foregroundStyle(.secondary)
          }
          ForEach(reviews) { review in
            VStack(alignment: .leading, spacing: 8) {
              Text(review.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
              Text(review.outcome?.title ?? "無法辨識的標記").font(.headline)
              Text(review.content).textSelection(.enabled)
            }
            .accessibilityIdentifier("observation.review")
            .swipeActions {
              Button("刪除回顧", role: .destructive) { reviewToDelete = review }
            }
          }
        } header: {
          Text("後續回顧")
        } footer: {
          Text("符合／不符合／尚無法判斷只是這次的主觀觀察，不計算命理準確率。若想更正，請新增一則回顧。")
        }
        if let date = observation.reviewDate {
          Section("自行設定的回顧時間") {
            Text(date, format: .dateTime.year().month().day().hour().minute())
            if observation.reminderIdentifier == nil {
              Text("這台裝置未設定此觀察的通知；仍可手動回顧。")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Section {
          DisclosureGroup("當時來源與依據") {
            Text(snapshot.source.title)
            Text(snapshot.versionDescription)
            ForEach(snapshot.seeds) { seed in
              Text(seed.meaning)
            }
            ForEach(snapshot.facts) { fact in
              Text(fact.displayText)
            }
            Text("以上為保存當時的文字與引用，只供歷史回顧，不重新用於目前解讀或 AI。")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      } else {
        Label("無法讀取快照，原始資料仍保留。你可以重試或明確刪除。", systemImage: "exclamationmark.triangle")
      }
    }
    .navigationTitle("觀察與回顧")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("刪除觀察", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
          .disabled(!parentExists)
          .accessibilityIdentifier("observation.delete")
      }
    }
    .sheet(isPresented: $addsReview) { ObservationReviewEditor(observation: observation) }
    .confirmationDialog("刪除原始觀察與所有回顧？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
      Button("永久刪除觀察與回顧", role: .destructive) { deleteObservation() }
    } message: {
      Text("將一併刪除 \(reviews.count) 則回顧並取消提醒，無法復原。刪除紀錄會在已同意的同步範圍內同步。")
    }
    .confirmationDialog(
      "永久刪除這則回顧？", isPresented: reviewDeletionBinding, titleVisibility: .visible
    ) {
      Button("刪除回顧", role: .destructive) { deleteReview() }
    } message: {
      Text("不會刪除或修改原始想法與其他回顧。")
    }
    .alert("操作未完成", isPresented: errorBinding) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "請稍後再試。")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }
  private var reviewDeletionBinding: Binding<Bool> {
    Binding(get: { reviewToDelete != nil }, set: { if !$0 { reviewToDelete = nil } })
  }

  private func deleteObservation() {
    do {
      let reminder = try ObservationStore.removeObservation(observation, modelContext: modelContext)
      try modelContext.save()
      ReviewReminderScheduler().cancel(identifier: reminder)
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = "無法刪除觀察，原始資料與提醒仍保留。"
    }
  }

  private func deleteReview() {
    guard let reviewToDelete else { return }
    do {
      ObservationStore.removeReview(reviewToDelete, modelContext: modelContext)
      try modelContext.save()
      self.reviewToDelete = nil
    } catch {
      modelContext.rollback()
      errorMessage = "無法刪除回顧，請再試一次。"
    }
  }
}

struct ObservationOriginalSections: View {
  let snapshot: ObservationSnapshot
  let createdAt: Date

  var body: some View {
    Section("原始觀察") {
      Text(snapshot.selectedText).textSelection(.enabled)
        .accessibilityIdentifier("observation.originalText")
      Text(createdAt, format: .dateTime.year().month().day().hour().minute())
        .font(.caption).foregroundStyle(.secondary)
    }
    Section("當時的初步想法") {
      Text(snapshot.initialThought.isEmpty ? "當時沒有填寫初步想法。" : snapshot.initialThought)
        .textSelection(.enabled)
        .accessibilityIdentifier("observation.originalThought")
    }
  }
}
