import XCTest

@testable import MightyZiWei

final class InterpretationSourceCatalogTests: XCTestCase {
  func test內容版本獨立且十二時辰現行十九Seeds皆能定位() throws {
    let catalog = InterpretationSourceCatalog()
    XCTAssertEqual(InterpretationContentVersion.current.rawValue, "1")
    XCTAssertEqual(InterpretationSourceCatalog.contentVersion, "1")
    for hour in stride(from: 0, to: 24, by: 2) {
      let chart = try ZiWeiCalculator().calculate(
        BirthProfile(
          localDate: LocalDate(year: 1990, month: 6, day: 15),
          localTime: LocalTime(hour: hour, minute: 0),
          timeZoneIdentifier: "Asia/Taipei"
        ))
      let facts = ChartFactBuilder().makeFacts(from: chart)
      let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)
      XCTAssertEqual(seeds.count, 19)
      for seed in seeds {
        let entry = try XCTUnwrap(catalog.resolve(seedID: seed.id, contentVersion: "1").entry)
        XCTAssertEqual(entry.seedID, seed.id)
        XCTAssertEqual(entry.requiredFactIDs, seed.evidenceFactIDs)
        XCTAssertEqual(entry.contentVersion, "1")
        XCTAssertEqual(entry.expertReview, .pending)
        XCTAssertEqual(entry.contractStatus, .currentProductRule)
        XCTAssertFalse(catalog.sources(for: entry).isEmpty)
      }
      XCTAssertEqual(chart.ruleSet, .taiwanTraditionalSanheV1)
    }
  }

  func test所有合法主星落宮維持精確分類且Rule與ClaimIDs穩定() throws {
    let catalog = InterpretationSourceCatalog()
    var ruleIDs: Set<String> = []
    var claimIDs: Set<String> = []
    for star in Star.allCases where star.category == .main {
      for palace in PalaceKind.allCases {
        let fact = ChartFact(
          id: "natal.star.\(star.rawValue).palace", category: .star,
          subject: .init(kind: "star", identifier: star.rawValue),
          value: .init(kind: "palace", identifier: palace.rawValue),
          displayText: "\(star.displayName)位於\(palace.displayName)。"
        )
        let seed = try XCTUnwrap(InterpretationSeedBuilder().makeSeeds(from: [fact]).first)
        let result = catalog.resolve(seedID: seed.id, contentVersion: "1")
        let entry = try XCTUnwrap(result.entry)
        XCTAssertEqual(result, catalog.resolve(seedID: seed.id, contentVersion: "1"))
        XCTAssertTrue(ruleIDs.insert(entry.ruleID).inserted)
        XCTAssertTrue(claimIDs.insert(entry.claimID).inserted)
        XCTAssertEqual(entry.requiredFactIDs, [fact.id])
        XCTAssertTrue(entry.applicability.contains(palace.displayName))
        XCTAssertTrue(entry.forbiddenInferences.contains("不得"))
      }
    }
    XCTAssertEqual(ruleIDs.count, 14 * 12)
    XCTAssertEqual(claimIDs.count, 14 * 12)
  }

  func test未知ID大小寫錯誤輔煞與分類衝突不得冒充現行規則() {
    let catalog = InterpretationSourceCatalog()
    let identifiers = [
      "", "seed.unknown.baseline", "seed.personality.ziwei.life",
      "seed.overview.ziWei.life", "seed.personality.zuoFu.life",
      "seed.personality.ziWei.unknown", "seed.personality.ziWei.life.extra",
      "seed.personality..ziWei.life", "seed.personality.baseline.",
      "seed.transformation.lu", "seed.personality.ziWei+tanLang.life",
    ]
    for identifier in identifiers {
      let result = catalog.resolve(seedID: identifier, contentVersion: "1")
      XCTAssertEqual(result, .unknownSeed(identifier))
      XCTAssertNil(result.entry)
      XCTAssertTrue(result.limitation?.contains("缺少來源資料") == true)
    }
  }

  func test歷史無版本與未知版本不會套用目前來源() {
    let catalog = InterpretationSourceCatalog()
    let identifier = "seed.personality.ziWei.life"
    let legacy = catalog.resolve(seedID: identifier, contentVersion: nil)
    XCTAssertEqual(legacy, .unversioned)
    XCTAssertNil(legacy.entry)
    XCTAssertTrue(legacy.limitation?.contains("來源版本未保存") == true)
    for version in ["", "0", "2", "01", "future"] {
      let result = catalog.resolve(seedID: identifier, contentVersion: version)
      XCTAssertEqual(result, .unknownVersion(version))
      XCTAssertNil(result.entry)
    }
  }

  func test缺少來源紀錄時回報不完整而非已核對() {
    let catalog = InterpretationSourceCatalog(
      sources: InterpretationSourceRecord.builtIn.filter { $0.id != "traditional.star.ziWei" }
    )
    let result = catalog.resolve(seedID: "seed.personality.ziWei.life", contentVersion: "1")
    XCTAssertEqual(result, .missingSources(["traditional.star.ziWei"]))
    XCTAssertNil(result.entry)
    XCTAssertTrue(result.limitation?.contains("來源目錄不完整") == true)
    XCTAssertEqual(
      InterpretationSourceCatalog(sources: []).resolve(
        seedID: "seed.overview.baseline", contentVersion: "1"
      ),
      .missingSources(["product.seed-builder", "contract.validator", "editorial.boundaries"])
    )
  }

  func test古籍轉譯契約與專家狀態分開且不虛構紙本頁碼() throws {
    let catalog = InterpretationSourceCatalog()
    let entry = try XCTUnwrap(
      catalog.resolve(seedID: "seed.personality.ziWei.life", contentVersion: "1").entry
    )
    let sources = catalog.sources(for: entry)
    XCTAssertEqual(
      Set(sources.map(\.kind)), [.productRule, .contract, .modernTranslation, .traditionalText])
    let traditional = try XCTUnwrap(sources.first { $0.kind == .traditionalText })
    XCTAssertEqual(traditional.locator, "諸星問答論 > 問紫微所主若何？")
    XCTAssertTrue(traditional.revision?.contains("oldid=7913704") == true)
    XCTAssertTrue(traditional.scope.contains("未提供紙本頁碼"))
    XCTAssertTrue(traditional.externalURL?.absoluteString.contains("oldid=7913704") == true)
    let translation = try XCTUnwrap(sources.first { $0.kind == .modernTranslation })
    XCTAssertTrue(translation.scope.contains("仍待審"))
    let contract = try XCTUnwrap(sources.first { $0.id == "contract.validator" })
    XCTAssertTrue(contract.scope.contains("不能證明 AI 每句語意"))
    XCTAssertEqual(entry.expertReview.title, "專家審閱：待審")
    XCTAssertEqual(entry.contractStatus.title, "現行產品規則，非專家認證")
    XCTAssertTrue(sources.allSatisfy { !$0.repositoryPath.hasPrefix("/") && !$0.locator.isEmpty })
    XCTAssertTrue(
      sources.filter { $0.externalURL != nil }.allSatisfy { $0.kind == .traditionalText })
  }

  func testBaseline不虛構逐條古籍來源且目錄來源ID不重複() throws {
    let catalog = InterpretationSourceCatalog()
    let entry = try XCTUnwrap(
      catalog.resolve(seedID: "seed.overview.baseline", contentVersion: "1").entry
    )
    XCTAssertFalse(catalog.sources(for: entry).contains { $0.kind == .traditionalText })
    XCTAssertEqual(Set(catalog.sources.map(\.id)).count, catalog.sources.count)
    XCTAssertEqual(entry.ruleID, "rule.overview.baseline")
    XCTAssertEqual(entry.claimID, "product.overview.baseline")
    XCTAssertEqual(entry.requiredFactIDs, ["natal.bureau"])
  }
}
