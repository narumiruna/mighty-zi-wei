import SwiftUI

struct PalaceDetailView: View {
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
  private var transformations: [Transformation] {
    chart.transformations.filter { $0.palace == palaceKind }
  }
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
        palaceJournal
        contextualQuestions
        rawChartData
      }
      .padding()
    }
    .navigationTitle(palace.kind.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      "切換命盤並開始新對話？",
      isPresented: pendingQuestionIsPresented,
      titleVisibility: .visible
    ) {
      Button("返回目前對話") {
        pendingQuestion = nil
        navigation.selectedTab = .ai
      }
      Button(palaceSwitchActionTitle, role: .destructive) {
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
      Text(palaceSwitchMessage)
    }
  }

  private var palaceSwitchActionTitle: String {
    let hasUnpreservedWork =
      !assistantStore.trimmedDraft.isEmpty
      || assistantStore.hasUnsavedChanges
      || assistantStore.isRequesting
    return hasUnpreservedWork ? "不保存，切換並填入問題" : "切換並填入問題"
  }

  private var palaceSwitchMessage: String {
    if !assistantStore.trimmedDraft.isEmpty, assistantStore.turns.isEmpty {
      return "目前問題草稿屬於另一張命盤。你可以先返回；直接切換會捨棄草稿，但不會自動送出新問題。"
    }
    if assistantStore.hasUnsavedChanges || assistantStore.isRequesting {
      return "目前對話屬於另一張命盤。你可以先返回保存；直接切換會清除未保存內容，但不會自動送出新問題。"
    }
    return "目前對話已保存。切換後會清除畫面上的舊脈絡並填入新問題，但不會自動送出。"
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

      Text(
        relatedKinds.map { ChartLearningCatalog.palace($0).relatedLabel }.joined(separator: " · ")
      )
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

  @ViewBuilder
  private var palaceJournal: some View {
    if let chartID = assistantChart.savedChartID {
      NavigationLink {
        ChartJournalView(
          chartID: chartID,
          chartName: assistantChart.name,
          suggestedLocationID: "palace.\(palaceKind.rawValue)",
          suggestedTitle: "\(palaceKind.displayName)筆記"
        )
      } label: {
        Label("記下這個宮位的觀察", systemImage: "square.and.pencil")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("palace.journal")
    }
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
    PalaceQuestionSuggestionBuilder().make(
      palaceKind: palaceKind,
      mainStars: mainStars.map(\.star),
      facts: facts,
      seeds: InterpretationSeedBuilder().makeSeeds(from: facts)
    )
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
    .background(
      .tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
    )
    .accessibilityElement(children: .contain)
  }
}
