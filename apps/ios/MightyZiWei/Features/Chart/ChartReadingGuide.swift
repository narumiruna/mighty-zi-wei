import Foundation

struct ChartReadingGuide: Sendable {
  static let contentVersion = "1"

  enum Step: Int, CaseIterable, Codable, Sendable {
    case lifePalace
    case mainStars
    case relatedPalaces
    case evidence

    var title: String {
      switch self {
      case .lifePalace: "找到命宮"
      case .mainStars: "確認本宮主星"
      case .relatedPalaces: "分清三方四正"
      case .evidence: "查看解讀依據"
      }
    }

    var instruction: String {
      switch self {
      case .lifePalace:
        "先在盤面找到命宮，讀取宮位干支。這一步只認識位置，不判斷性格。"
      case .mainStars:
        "只看實際落在命宮的十四主星。其他宮的星曜不能改寫成本宮星曜。"
      case .relatedPalaces:
        "以命宮為本宮，分開查看對宮與兩個三合宮。關係集合不等於支持、牽制或因果已成立。"
      case .evidence:
        "盤面 fact 說明位置，seed 記錄現行產品語句。來源可追溯不等於專家審閱或逐句證明。"
      }
    }
  }

  enum ProgressStatus: String, Codable, Sendable {
    case reading
    case paused
    case completed
  }

  struct Progress: Codable, Equatable, Sendable {
    private(set) var step: Step = .lifePalace
    private(set) var status: ProgressStatus = .reading

    mutating func next() {
      guard status != .completed else { return }
      if let next = Step(rawValue: step.rawValue + 1) {
        step = next
        status = .reading
      } else {
        status = .completed
      }
    }

    mutating func previous() {
      step = Step(rawValue: max(0, step.rawValue - 1)) ?? .lifePalace
      status = .reading
    }

    mutating func pause() {
      guard status != .completed else { return }
      status = .paused
    }

    mutating func reopen() {
      if status == .completed {
        self = Self()
      } else {
        status = .reading
      }
    }

    mutating func restart() { self = Self() }
  }

  let chart: ZiWeiChart
  let facts: [ChartFact]

  init(chart: ZiWeiChart) {
    self.chart = chart
    facts = ChartFactBuilder().makeFacts(from: chart)
  }

  var lifeMainStars: [StarPlacement] {
    chart.stars.filter { $0.palace == .life && $0.star.category == .main }
  }

  var hasCompleteMainStarPositions: Bool {
    let expected = Set(Star.allCases.filter { $0.category == .main })
    let placements = chart.stars.filter { $0.star.category == .main }
    return placements.count == expected.count && Set(placements.map(\.star)) == expected
  }

  var isEmptyLifePalace: Bool {
    hasCompleteMainStarPositions && lifeMainStars.isEmpty
  }

  var mainStarNotice: String {
    if !hasCompleteMainStarPositions {
      return "十四主星位置資料不完整，不能由缺少資料推定空宮；目前只列已有位置。"
    }
    if isEmptyLifePalace {
      return "完整十四主星位置顯示：命宮沒有十四主星，稱為空宮。不代表沒有其他星曜，也不表示沒有意義；對宮主星仍屬於對宮。"
    }
    return "這些是命宮實際主星。本步只列位置，不用單一星曜定論。"
  }

  var lifeRelation: PalaceRelation? {
    guard let relation = chart.relations.first(where: { $0.palace == .life }),
      relation.trines.count == 2,
      Set([relation.palace, relation.opposite] + relation.trines).count == 4
    else { return nil }
    return relation
  }

  var evidenceSeeds: [InterpretationSeed] {
    guard hasCompleteMainStarPositions, !lifeMainStars.isEmpty else { return [] }
    let identifiers = Set(lifeMainStars.map { "natal.star.\($0.star.rawValue).palace" })
    return InterpretationSeedBuilder().makeSeeds(from: facts).filter { seed in
      seed.category == .personality
        && !seed.evidenceFactIDs.isEmpty
        && Set(seed.evidenceFactIDs).isSubset(of: identifiers)
    }
  }

  func highlightedPalaces(for step: Step) -> [PalaceKind] {
    guard step == .relatedPalaces, let relation = lifeRelation else { return [.life] }
    return [.life, relation.opposite] + relation.trines
  }

  func role(for palace: PalaceKind, step: Step) -> String {
    guard step == .relatedPalaces, let relation = lifeRelation else { return "本宮" }
    if palace == .life { return "本宮" }
    if palace == relation.opposite { return "對宮" }
    if palace == relation.trines.first { return "三合宮一" }
    return "三合宮二"
  }

  func evidenceFacts(for step: Step) -> [ChartFact] {
    let identifiers: Set<String>
    switch step {
    case .lifePalace:
      identifiers = ["natal.palace.life.branch"]
    case .mainStars:
      let placements =
        isEmptyLifePalace
        ? chart.stars.filter { $0.star.category == .main } : lifeMainStars
      identifiers = Set(placements.map { "natal.star.\($0.star.rawValue).palace" })
    case .relatedPalaces:
      identifiers = Set(
        ["natal.palace.life.sanFangSiZheng"]
          + highlightedPalaces(for: step).map { "natal.palace.\($0.rawValue).branch" }
      )
    case .evidence:
      if evidenceSeeds.isEmpty {
        return evidenceFacts(for: .mainStars)
      }
      identifiers = Set(evidenceSeeds.flatMap(\.evidenceFactIDs))
    }
    return facts.filter { identifiers.contains($0.id) }
  }
}
