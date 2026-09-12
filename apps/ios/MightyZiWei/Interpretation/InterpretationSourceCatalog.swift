import Foundation

/// 解讀內容版本與排盤 ruleset 分開；未知或未保存的歷史版本不得回填。
enum InterpretationContentVersion: String, Codable, Sendable {
  case version1 = "1"

  static let current = Self.version1
}

struct InterpretationSourceCatalog: Sendable {
  static let contentVersion = InterpretationContentVersion.current.rawValue

  enum ExpertReview: String, Sendable {
    case pending

    var title: String { "專家審閱：待審" }
  }

  enum ContractStatus: String, Sendable {
    case currentProductRule

    var title: String { "現行產品規則，非專家認證" }
  }

  struct Entry: Identifiable, Equatable, Sendable {
    let seedID: String
    let ruleID: String
    let claimID: String
    let contentVersion: String
    let title: String
    let requiredFactIDs: [String]
    let sourceIDs: [String]
    let applicability: String
    let forbiddenInferences: String
    let expertReview: ExpertReview
    let contractStatus: ContractStatus

    var id: String { seedID }
  }

  enum Resolution: Equatable, Sendable {
    case current(Entry)
    case unversioned
    case unknownVersion(String)
    case unknownSeed(String)
    case missingSources([String])

    var entry: Entry? {
      guard case .current(let entry) = self else { return nil }
      return entry
    }

    var limitation: String? {
      switch self {
      case .current: nil
      case .unversioned:
        "來源版本未保存。僅保留原有引用，不以目前目錄補上歷史認證。"
      case .unknownVersion(let version):
        "這台裝置沒有內容版本 \(version) 的來源目錄，無法核對當時來源。"
      case .unknownSeed(let identifier):
        "缺少來源資料：找不到解讀 ID「\(identifier)」，不能推定其含義或審閱狀態。"
      case .missingSources(let identifiers):
        "來源目錄不完整，缺少：\(identifiers.joined(separator: "、"))。不能視為來源已核對。"
      }
    }
  }

  let sources: [InterpretationSourceRecord]

  init(sources: [InterpretationSourceRecord] = InterpretationSourceRecord.builtIn) {
    self.sources = sources
  }

  /// 只查本機目錄，不驗證傳入文字的語意，也不生成新 seed。
  func resolve(seedID: String, contentVersion: String?) -> Resolution {
    guard let contentVersion else { return .unversioned }
    guard contentVersion == Self.contentVersion else { return .unknownVersion(contentVersion) }
    guard let entry = entry(for: seedID) else { return .unknownSeed(seedID) }
    let available = Set(sources.map(\.id))
    let missing = entry.sourceIDs.filter { !available.contains($0) }
    guard missing.isEmpty else { return .missingSources(missing) }
    return .current(entry)
  }

  func sources(for entry: Entry) -> [InterpretationSourceRecord] {
    entry.sourceIDs.compactMap { identifier in sources.first { $0.id == identifier } }
  }

  private func entry(for seedID: String) -> Entry? {
    let components = seedID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard components.first == "seed", components.count >= 3,
      let category = InterpretationCategory(rawValue: components[1])
    else { return nil }

    if components.count == 3, components[2] == "baseline" {
      return makeEntry(
        seedID: seedID,
        title: "\(category.title)基本語句",
        factID: baselineFactID(category),
        sourceIDs: ["product.seed-builder", "contract.validator", "editorial.boundaries"],
        applicability: "僅適用於 builder 產生的 \(category.title) baseline，且必須有完整盤面依據。"
      )
    }

    guard components.count == 4,
      let star = Star(rawValue: components[2]), star.category == .main,
      let palace = PalaceKind(rawValue: components[3]), category == expectedCategory(palace)
    else { return nil }
    return makeEntry(
      seedID: seedID,
      title: "\(star.displayName)・\(palace.displayName)・\(category.title)",
      factID: "natal.star.\(star.rawValue).palace",
      sourceIDs: [
        "product.seed-builder", "contract.validator", "editorial.boundaries",
        "translation.star.\(star.rawValue)", "traditional.star.\(star.rawValue)",
      ],
      applicability:
        "僅限 \(star.displayName) 實際位於\(palace.displayName)，並使用 builder 的\(category.title)原始語句；不得挪用其他分類。"
    )
  }

  private func makeEntry(
    seedID: String, title: String, factID: String, sourceIDs: [String], applicability: String
  ) -> Entry {
    let suffix = String(seedID.dropFirst("seed.".count))
    return Entry(
      seedID: seedID,
      ruleID: "rule.\(suffix)",
      claimID: "product.\(suffix)",
      contentVersion: Self.contentVersion,
      title: title,
      requiredFactIDs: [factID],
      sourceIDs: sourceIDs,
      applicability: applicability,
      forbiddenInferences: "不得推論固定人格、確定事件、疾病、婚育或財富結果；不得加入四化、輔煞或組合的新含義。",
      expertReview: .pending,
      contractStatus: .currentProductRule
    )
  }

  private func baselineFactID(_ category: InterpretationCategory) -> String {
    switch category {
    case .overview: "natal.bureau"
    case .personality: "natal.palace.life.branch"
    case .career: "natal.palace.career.branch"
    case .wealth: "natal.palace.wealth.branch"
    case .relationships: "natal.palace.spouse.branch"
    }
  }

  private func expectedCategory(_ palace: PalaceKind) -> InterpretationCategory {
    switch palace {
    case .life, .fortune: .personality
    case .career, .travel: .career
    case .wealth, .property: .wealth
    case .spouse, .friends, .siblings: .relationships
    case .children, .health, .parents: .overview
    }
  }
}
