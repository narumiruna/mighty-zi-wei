import SwiftUI

/// 收藏可只傳 IDs 與當時版本；nil 一律顯示無版本限制，不查目前目錄補認證。
struct InterpretationSourceView: View {
  let seedIDs: [String]
  let factIDs: [String]
  let contentVersion: String?
  var seeds: [InterpretationSeed] = []
  var facts: [ChartFact] = []
  var isAIGenerated = false

  private let catalog = InterpretationSourceCatalog()

  init(
    seedIDs: [String],
    factIDs: [String],
    contentVersion: String?,
    seeds: [InterpretationSeed] = [],
    facts: [ChartFact] = [],
    isAIGenerated: Bool = false
  ) {
    self.seedIDs = seedIDs
    self.factIDs = factIDs
    self.contentVersion = contentVersion
    self.seeds = seeds
    self.facts = facts
    self.isAIGenerated = isAIGenerated
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppDesign.pageSpacing) {
        VStack(alignment: .leading, spacing: 10) {
          Text("本段引用依據")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
          Text("此處依段落及 seed 列出本機來源，不是逐句證明，也不表示命理已獲科學驗證。")
          if isAIGenerated {
            Text("AI 文字僅保存本段引用依據；引用契約不能保證每句語意、因果或組合判斷正確。")
              .accessibilityIdentifier("sources.aiLimitation")
          }
          versionNotice
          Label("本機資料可離線閱讀", systemImage: "internaldrive")
            .font(.footnote)
          Text("只有主動開啟外部來源連結時才會連網；此頁不會呼叫 AI。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if seedIDs.isEmpty {
          Text("未保存解讀 ID，無法對應含義來源。盤面 fact 本身不證明命理含義。")
            .accessibilityIdentifier("sources.missingSeeds")
        }

        ForEach(Array(seedIDs.enumerated()), id: \.offset) { _, identifier in
          seedCard(identifier)
        }

        DisclosureGroup("本段引用的盤面資料（\(factIDs.count) 項）") {
          VStack(alignment: .leading, spacing: 12) {
            if factIDs.isEmpty {
              Text("未保存盤面依據。")
            }
            ForEach(Array(factIDs.enumerated()), id: \.offset) { _, identifier in
              VStack(alignment: .leading, spacing: 4) {
                Text(identifier).font(.caption.monospaced())
                if let fact = facts.first(where: { $0.id == identifier }) {
                  Text(fact.displayText)
                } else {
                  Text("缺少這項盤面資料的原始文字，不能只依 ID 還原位置。")
                    .foregroundStyle(.secondary)
                }
              }
              .textSelection(.enabled)
            }
          }
          .padding(.top, 8)
        }
        .cardStyle()
        .accessibilityIdentifier("sources.facts")
      }
      .frame(maxWidth: AppDesign.readingWidth)
      .frame(maxWidth: .infinity)
      .padding(AppDesign.pageInset)
    }
    .appPageBackground()
    .navigationTitle("解讀來源")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("sources.screen")
  }

  @ViewBuilder
  private var versionNotice: some View {
    if contentVersion == InterpretationSourceCatalog.contentVersion {
      Text("解讀內容版本：\(InterpretationSourceCatalog.contentVersion)")
        .font(.subheadline.weight(.medium))
        .accessibilityIdentifier("sources.version")
    } else {
      Text(catalog.resolve(seedID: "", contentVersion: contentVersion).limitation ?? "缺少來源版本。")
        .font(.subheadline.weight(.medium))
        .accessibilityIdentifier("sources.versionLimitation")
    }
  }

  private func seedCard(_ identifier: String) -> some View {
    let resolution = catalog.resolve(seedID: identifier, contentVersion: contentVersion)
    return VStack(alignment: .leading, spacing: 10) {
      Text(resolution.entry?.title ?? "解讀引用")
        .font(.headline)
      Text(identifier)
        .font(.caption.monospaced())
        .textSelection(.enabled)
      if let entry = resolution.entry {
        Text(entry.expertReview.title)
          .font(.subheadline.weight(.semibold))
        Text(entry.contractStatus.title)
          .font(.footnote)
          .foregroundStyle(.secondary)
        if let seed = seeds.first(where: { $0.id == identifier }) {
          Text(seed.meaning)
            .textSelection(.enabled)
        } else {
          Text("原始解讀語句未隨資料提供；此卡只定位來源，不重新產生歷史文字。")
            .font(.footnote)
        }
        if !Set(entry.requiredFactIDs).isSubset(of: Set(factIDs)) {
          Text("缺少這項 seed 所需的完整盤面依據，不能視為當次引用已驗證。")
            .font(.footnote.weight(.medium))
            .accessibilityIdentifier("sources.incompleteFacts")
        }
        DisclosureGroup("規則與來源定位") {
          entryDetails(entry)
        }
        .accessibilityIdentifier("sources.details.\(identifier)")
      } else if let limitation = resolution.limitation {
        Text(limitation)
          .font(.subheadline)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle()
    .accessibilityIdentifier("sources.seed.\(identifier)")
  }

  private func entryDetails(_ entry: InterpretationSourceCatalog.Entry) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("規則 ID：\(entry.ruleID)\n主張 ID：\(entry.claimID)")
        .font(.caption.monospaced())
        .textSelection(.enabled)
      Text(entry.applicability)
      Text(entry.forbiddenInferences)
      if !catalog.sources(for: entry).contains(where: { $0.kind == .traditionalText }) {
        Text("本項基本語句未建立逐條古籍對應；來源為現行產品文案，不是古籍引文。")
          .font(.footnote)
      }
      Text("必要 facts：\(entry.requiredFactIDs.joined(separator: "、"))")
        .font(.caption.monospaced())
        .textSelection(.enabled)
      ForEach(catalog.sources(for: entry)) { source in
        Divider()
        Text(source.kind.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(source.title).font(.subheadline.weight(.semibold))
        Text(source.repositoryPath)
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Text(source.locator)
        if let revision = source.revision {
          Text(revision).font(.footnote)
        }
        Text(source.scope)
          .font(.footnote)
        if let url = source.externalURL {
          Link(destination: url) {
            Label("開啟外部原文（需要網路）", systemImage: "arrow.up.right.square")
          }
          .accessibilityIdentifier("sources.external.\(source.id)")
          .accessibilityHint("將在瀏覽器開啟維基文庫固定修訂，不傳送命盤資料")
        }
      }
    }
    .padding(.top, 8)
  }
}
