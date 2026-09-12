import XCTest

@testable import MightyZiWei

@MainActor
final class ChartReadingGuideTests: XCTestCase {
  func test四步前後移動有界線且最後一步才完成() {
    var progress = ChartReadingGuide.Progress()
    XCTAssertEqual(ChartReadingGuide.Step.allCases.count, 4)
    progress.previous()
    XCTAssertEqual(progress.step, .lifePalace)
    for step in [ChartReadingGuide.Step.mainStars, .relatedPalaces, .evidence] {
      progress.next()
      XCTAssertEqual(progress.step, step)
      XCTAssertEqual(progress.status, .reading)
    }
    progress.next()
    XCTAssertEqual(progress.status, .completed)
    progress.next()
    XCTAssertEqual(progress.step, .evidence)
    progress.previous()
    XCTAssertEqual(progress.step, .relatedPalaces)
    XCTAssertEqual(progress.status, .reading)
  }

  func test跳過續讀完成重開與從頭開始() {
    var progress = ChartReadingGuide.Progress()
    progress.next()
    progress.pause()
    XCTAssertEqual(progress.status, .paused)
    XCTAssertEqual(progress.step, .mainStars)
    progress.reopen()
    XCTAssertEqual(progress.status, .reading)
    XCTAssertEqual(progress.step, .mainStars)
    progress.restart()
    XCTAssertEqual(progress, .init())
    for _ in 0..<4 { progress.next() }
    progress.pause()
    XCTAssertEqual(progress.status, .completed)
    progress.reopen()
    XCTAssertEqual(progress, .init())
  }

  func test已存命盤可由全新Store續讀() throws {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let identity = ChartReadingGuideProgressStore.Identity(chartID: UUID(), chart: try makeChart())
    let store = ChartReadingGuideProgressStore(defaults: defaults)
    var progress = ChartReadingGuide.Progress()
    progress.next()
    progress.next()
    progress.pause()
    store.save(progress, for: identity, isSaved: true)
    let relaunched = ChartReadingGuideProgressStore(defaults: defaults)
    XCTAssertEqual(relaunched.load(for: identity, isSaved: true), progress)
    XCTAssertEqual(relaunched.load(for: identity, isSaved: true).step, .relatedPalaces)
  }

  func test未存命盤只保留實例記憶體不讀寫Defaults() throws {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let identity = ChartReadingGuideProgressStore.Identity(chartID: UUID(), chart: try makeChart())
    let store = ChartReadingGuideProgressStore(defaults: defaults)
    var progress = ChartReadingGuide.Progress()
    progress.next()
    store.save(progress, for: identity, isSaved: false)
    XCTAssertEqual(store.load(for: identity, isSaved: false), progress)
    XCTAssertTrue((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty)
    let reopened = ChartReadingGuideProgressStore(defaults: defaults)
    XCTAssertEqual(reopened.load(for: identity, isSaved: false), .init())
    // 即使同 ID 意外已有磁碟資料，未儲存模式也不能讀取它。
    store.save(progress, for: identity, isSaved: true)
    XCTAssertEqual(reopened.load(for: identity, isSaved: false), .init())
  }

  func test命盤身分內容版本導覽版本Ruleset與排盤資料都隔離() throws {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let chart = try makeChart()
    let chartID = UUID()
    let identity = ChartReadingGuideProgressStore.Identity(chartID: chartID, chart: chart)
    let alternatives = [
      ChartReadingGuideProgressStore.Identity(chartID: UUID(), chart: chart),
      .init(chartID: chartID, chart: chart, interpretationVersion: "2"),
      .init(chartID: chartID, chart: chart, guideVersion: "2"),
      .init(
        chartID: chartID, chart: replacing(chart, ruleSet: .init(id: chart.ruleSet.id, version: 2))),
      .init(
        chartID: chartID, chart: replacing(chart, ruleSet: .init(id: "other-ruleset", version: 1))),
      .init(chartID: chartID, chart: try makeChart(hour: 12)),
    ]
    let store = ChartReadingGuideProgressStore(defaults: defaults)
    var progress = ChartReadingGuide.Progress()
    progress.next()
    for isSaved in [true, false] {
      store.save(progress, for: identity, isSaved: isSaved)
      for alternative in alternatives {
        XCTAssertNotEqual(identity, alternative)
        XCTAssertEqual(store.load(for: alternative, isSaved: isSaved), .init())
      }
      XCTAssertEqual(store.load(for: identity, isSaved: isSaved), progress)
    }
  }

  func test刪除清除該命盤全部版本而不影響其他命盤與設定() throws {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let chart = try makeChart()
    let chartID = UUID()
    let identities = [
      ChartReadingGuideProgressStore.Identity(chartID: chartID, chart: chart),
      .init(chartID: chartID, chart: chart, interpretationVersion: "2"),
      .init(chartID: chartID, chart: chart, guideVersion: "2"),
    ]
    let other = ChartReadingGuideProgressStore.Identity(chartID: UUID(), chart: chart)
    let store = ChartReadingGuideProgressStore(defaults: defaults)
    var progress = ChartReadingGuide.Progress()
    progress.next()
    for identity in identities + [other] { store.save(progress, for: identity, isSaved: true) }
    defaults.set("保留", forKey: "other.preference")
    ChartReadingGuideProgressStore.remove(chartID: chartID, defaults: defaults)
    for identity in identities {
      XCTAssertEqual(store.load(for: identity, isSaved: true), .init())
    }
    XCTAssertEqual(store.load(for: other, isSaved: true), progress)
    XCTAssertEqual(defaults.string(forKey: "other.preference"), "保留")
    ChartReadingGuideProgressStore.remove(chartID: chartID, defaults: defaults)
    XCTAssertEqual(store.load(for: other, isSaved: true), progress)
  }

  func test損毀或未來步驟資料安全重啟() throws {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let identity = ChartReadingGuideProgressStore.Identity(chartID: UUID(), chart: try makeChart())
    let store = ChartReadingGuideProgressStore(defaults: defaults)
    store.save(.init(), for: identity, isSaved: true)
    let key = try XCTUnwrap(defaults.persistentDomain(forName: suite)?.keys.first)
    for invalid in [
      "資料損毀", "{\"step\":99,\"status\":\"reading\"}", "{\"step\":0,\"status\":\"future\"}",
    ] {
      defaults.set(Data(invalid.utf8), forKey: key)
      XCTAssertEqual(store.load(for: identity, isSaved: true), .init())
    }
  }

  func test每步只使用當前命盤的實際位置與關係() throws {
    let guide = ChartReadingGuide(chart: try makeChart())
    let relation = try XCTUnwrap(guide.lifeRelation)
    XCTAssertEqual(guide.highlightedPalaces(for: .lifePalace), [.life])
    XCTAssertEqual(guide.highlightedPalaces(for: .mainStars), [.life])
    XCTAssertEqual(
      guide.highlightedPalaces(for: .relatedPalaces), [.life, relation.opposite] + relation.trines)
    XCTAssertEqual(guide.role(for: relation.opposite, step: .relatedPalaces), "對宮")
    XCTAssertEqual(guide.role(for: relation.trines[0], step: .relatedPalaces), "三合宮一")
    XCTAssertEqual(guide.role(for: relation.trines[1], step: .relatedPalaces), "三合宮二")
    XCTAssertEqual(guide.evidenceFacts(for: .lifePalace).map(\.id), ["natal.palace.life.branch"])
    for step in ChartReadingGuide.Step.allCases {
      XCTAssertTrue(Set(guide.evidenceFacts(for: step)).isSubset(of: Set(guide.facts)))
    }
    let seeds = InterpretationSeedBuilder().makeSeeds(from: guide.facts)
    XCTAssertTrue(guide.evidenceSeeds.allSatisfy { seeds.contains($0) })
    XCTAssertTrue(guide.evidenceSeeds.allSatisfy { $0.category == .personality })
  }

  func test空宮只列完整十四主星位置不借對宮含義() throws {
    let chart = try makeChart()
    let stars = chart.stars.map { placement in
      guard placement.star.category == .main, placement.palace == .life else { return placement }
      return StarPlacement(
        star: placement.star, branch: chart.palace(.travel).stemBranch.branch, palace: .travel
      )
    }
    let guide = ChartReadingGuide(chart: replacing(chart, stars: stars))
    XCTAssertTrue(guide.hasCompleteMainStarPositions)
    XCTAssertTrue(guide.isEmptyLifePalace)
    XCTAssertTrue(guide.lifeMainStars.isEmpty)
    XCTAssertTrue(guide.evidenceSeeds.isEmpty)
    XCTAssertEqual(guide.evidenceFacts(for: .mainStars).count, 14)
    XCTAssertEqual(guide.evidenceFacts(for: .evidence), guide.evidenceFacts(for: .mainStars))
    XCTAssertTrue(guide.mainStarNotice.contains("對宮主星仍屬於對宮"))
    XCTAssertTrue(guide.mainStarNotice.contains("不代表沒有其他星曜"))
  }

  func test不完整星曜資料不能用缺少位置證明空宮() throws {
    let chart = try makeChart()
    let incomplete = chart.stars.filter { $0.star.category != .main }
    let guide = ChartReadingGuide(chart: replacing(chart, stars: incomplete))
    XCTAssertFalse(guide.hasCompleteMainStarPositions)
    XCTAssertFalse(guide.isEmptyLifePalace)
    XCTAssertTrue(guide.evidenceSeeds.isEmpty)
    XCTAssertTrue(guide.mainStarNotice.contains("不能由缺少資料推定空宮"))
  }

  private func makeDefaults() -> (UserDefaults, String) {
    let suite = "ChartReadingGuideTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
  }

  private func makeChart(hour: Int = 10) throws -> ZiWeiChart {
    try ZiWeiCalculator().calculate(
      BirthProfile(
        localDate: LocalDate(year: 1990, month: 6, day: 15),
        localTime: LocalTime(hour: hour, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))
  }

  private func replacing(
    _ chart: ZiWeiChart, stars: [StarPlacement]? = nil, ruleSet: RuleSetIdentity? = nil
  ) -> ZiWeiChart {
    ZiWeiChart(
      ruleSet: ruleSet ?? chart.ruleSet, birthProfile: chart.birthProfile,
      lunarDate: chart.lunarDate,
      hourBranch: chart.hourBranch, fiveElementBureau: chart.fiveElementBureau,
      palaces: chart.palaces, stars: stars ?? chart.stars, transformations: chart.transformations,
      relations: chart.relations
    )
  }
}
