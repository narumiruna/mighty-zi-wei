import SwiftUI

struct ChartReadingGuideView: View {
  private let guide: ChartReadingGuide
  private let identity: ChartReadingGuideProgressStore.Identity
  private let isSaved: Bool
  private let store: ChartReadingGuideProgressStore

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AccessibilityFocusState private var headingFocused: Bool
  @State private var progress: ChartReadingGuide.Progress

  init(
    chart: ZiWeiChart,
    chartID: UUID?,
    sessionID: UUID,
    store: ChartReadingGuideProgressStore
  ) {
    guide = ChartReadingGuide(chart: chart)
    let identity = ChartReadingGuideProgressStore.Identity(
      chartID: chartID ?? sessionID, chart: chart
    )
    self.identity = identity
    isSaved = chartID != nil
    self.store = store
    var saved = store.load(for: identity, isSaved: chartID != nil)
    saved.reopen()
    _progress = State(initialValue: saved)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
          VStack(alignment: .leading, spacing: 8) {
            Text("第 \(progress.step.rawValue + 1) 步，共 4 步：\(progress.step.title)")
              .font(.title2.bold())
              .accessibilityAddTraits(.isHeader)
              .accessibilityFocused($headingFocused)
              .accessibilityIdentifier("guide.step")
              .id("guide.heading")
            Text(progress.step.instruction)
            Text(isSaved ? "進度只保存在這台裝置，可稍後續讀。" : "尚未儲存命盤；進度只保留在本次命盤畫面，離開或關閉 App 後不保存。")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("guide.storage")
          }

          stepContent
            .id(progress.step)
        }
        .frame(maxWidth: AppDesign.readingWidth)
        .frame(maxWidth: .infinity)
        .padding(AppDesign.pageInset)
      }
      .onChange(of: progress.step) { _, _ in
        // 不依賴動畫；Reduce Motion 與 VoiceOver 都直接移到新步驟標題。
        proxy.scrollTo("guide.heading", anchor: .top)
        headingFocused = true
      }
    }
    .appPageBackground()
    .navigationTitle("四步讀盤導覽")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("guide.screen")
    .safeAreaInset(edge: .bottom) {
      controls
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("稍後再讀") {
          progress.pause()
          saveProgress()
          dismiss()
        }
        .accessibilityHint("跳過導覽，保留目前步驟並回到命盤")
        .accessibilityIdentifier("guide.skip")
      }
    }
    .onAppear {
      progress = store.load(for: identity, isSaved: isSaved)
      progress.reopen()
      saveProgress()
    }
    .transaction { transaction in
      if reduceMotion { transaction.animation = nil }
    }
  }

  private var stepContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      if progress.step == .mainStars {
        Text(guide.mainStarNotice)
          .accessibilityIdentifier("guide.mainStarNotice")
      }
      if progress.step == .relatedPalaces, guide.lifeRelation == nil {
        Text("缺少完整三方四正關係資料，只顯示命宮，不自行補算其他宮位。")
      }

      ChartReadingGuideMap(guide: guide, step: progress.step)

      if progress.step == .evidence {
        evidenceContent
      } else {
        DisclosureGroup("核對本步盤面依據") {
          factList
        }
        .accessibilityIdentifier("guide.facts")
      }
    }
  }

  private var evidenceContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      if guide.evidenceSeeds.isEmpty {
        Text("本步只列盤面 facts，不替空宮、缺少規則或資料不足的情況補上個人化含義。")
          .accessibilityIdentifier("guide.factsOnly")
      } else {
        Text("現行產品語句・專家待審")
          .font(.headline)
        ForEach(guide.evidenceSeeds) { seed in
          Text(seed.meaning)
        }
        NavigationLink {
          InterpretationSourceView(
            seedIDs: guide.evidenceSeeds.map(\.id),
            factIDs: guide.evidenceFacts(for: .evidence).map(\.id),
            contentVersion: InterpretationSourceCatalog.contentVersion,
            seeds: guide.evidenceSeeds,
            facts: guide.evidenceFacts(for: .evidence)
          )
        } label: {
          Label("查看這些語句的來源", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("guide.sources")
      }
      factList
    }
    .cardStyle()
  }

  private var factList: some View {
    VStack(alignment: .leading, spacing: 10) {
      let facts = guide.evidenceFacts(for: progress.step)
      if facts.isEmpty {
        Text("本步缺少可顯示的盤面依據。")
      }
      ForEach(facts) { fact in
        VStack(alignment: .leading, spacing: 4) {
          Text(fact.displayText)
          Text(fact.id)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
      }
    }
    .padding(.top, 8)
  }

  private var controls: some View {
    VStack(spacing: 8) {
      Button {
        progress.next()
        saveProgress()
        if progress.status == .completed { dismiss() }
      } label: {
        Text(progress.step == .evidence ? "完成導覽" : "下一步")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PrimaryActionStyle())
      .accessibilityIdentifier("guide.next")

      if progress.step != .lifePalace {
        Button("上一步") {
          progress.previous()
          saveProgress()
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("guide.previous")
      }
    }
    .frame(maxWidth: AppDesign.readingWidth)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, AppDesign.pageInset)
    .padding(.vertical, 8)
    .background(.regularMaterial)
  }

  private func saveProgress() {
    store.save(progress, for: identity, isSaved: isSaved)
  }
}
