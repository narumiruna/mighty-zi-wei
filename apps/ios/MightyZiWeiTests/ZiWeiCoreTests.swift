import Foundation
import XCTest

@testable import MightyZiWei

final class ZiWeiCoreTests: XCTestCase {
  private let fixtureNames = [
    "chart_001_normal",
    "chart_002_zi_hour",
    "chart_003_lunar_new_year",
    "chart_004_leap_month",
    "chart_005_historical_dst",
    "chart_006_1900_boundary",
    "chart_007_2099_boundary",
    "chart_008_hour_yin",
    "chart_009_hour_mao",
    "chart_010_hour_chen",
    "chart_011_hour_wei",
    "chart_012_hour_shen",
    "chart_013_hour_you",
    "chart_014_hour_xu",
    "chart_015_hour_hai",
  ]

  func testGoldenFixtures() throws {
    for name in fixtureNames {
      let fixture = try loadFixture(named: name)
      XCTAssertEqual(fixture.schemaVersion, 1, name)
      XCTAssertFalse(fixture.sourceReference.isEmpty, name)

      let chart = try ZiWeiCalculator().calculate(fixture.input)
      XCTAssertEqual(chart.ruleSet, fixture.ruleSet, name)
      XCTAssertEqual(chart.lunarDate, fixture.expected.lunarDate, name)
      XCTAssertEqual(chart.hourBranch.rawValueName, fixture.expected.hourBranch, name)
      XCTAssertEqual(
        chart.lifePalace.stemBranch.branch.rawValueName, fixture.expected.lifeBranch, name)
      XCTAssertEqual(
        chart.bodyPalace.stemBranch.branch.rawValueName, fixture.expected.bodyBranch, name)
      XCTAssertEqual(chart.fiveElementBureau.rawValue, fixture.expected.fiveElementBureau, name)

      XCTAssertEqual(chart.palaces.count, 12, name)
      for expectedPalace in fixture.expected.palaces {
        let kind = try XCTUnwrap(PalaceKind(rawValue: expectedPalace.kind), name)
        let palace = chart.palace(kind)
        XCTAssertEqual(palace.stemBranch.stem.rawValueName, expectedPalace.stem, name)
        XCTAssertEqual(palace.stemBranch.branch.rawValueName, expectedPalace.branch, name)
      }

      XCTAssertEqual(chart.stars.count, 28, name)
      for (starName, branchName) in fixture.expected.stars {
        let star = try XCTUnwrap(Star(rawValue: starName), name)
        XCTAssertEqual(
          chart.placement(of: star).branch.rawValueName, branchName, "\(name): \(starName)")
      }

      XCTAssertEqual(chart.transformations.count, 4, name)
      for (kindName, starName) in fixture.expected.transformations {
        let kind = try XCTUnwrap(TransformationKind(rawValue: kindName), name)
        let transformation = try XCTUnwrap(chart.transformations.first { $0.kind == kind }, name)
        XCTAssertEqual(transformation.star.rawValue, starName, "\(name): \(kindName)")
        XCTAssertEqual(transformation.branch, chart.placement(of: transformation.star).branch, name)
      }

      assertRelations(chart, fixtureName: name)
    }
  }

  func testZiHourUsesCivilDateWithoutEarlyRollover() throws {
    let profile = BirthProfile(
      localDate: LocalDate(year: 2000, month: 1, day: 1),
      localTime: LocalTime(hour: 23, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let chart = try ZiWeiCalculator().calculate(profile)
    XCTAssertEqual(chart.hourBranch, .zi)
    XCTAssertEqual(
      chart.lunarDate, LunarDate(cyclicalYear: 16, month: 11, day: 25, isLeapMonth: false))
  }

  func testHourBranchBoundaries() throws {
    XCTAssertEqual(try CalendarNormalizer.hourBranch(for: LocalTime(hour: 22, minute: 59)), .hai)
    XCTAssertEqual(try CalendarNormalizer.hourBranch(for: LocalTime(hour: 23, minute: 0)), .zi)
    XCTAssertEqual(try CalendarNormalizer.hourBranch(for: LocalTime(hour: 0, minute: 59)), .zi)
    XCTAssertEqual(try CalendarNormalizer.hourBranch(for: LocalTime(hour: 1, minute: 0)), .chou)
  }

  func testRejectsInvalidAndNonexistentLocalTimes() {
    XCTAssertThrowsError(
      try CalendarNormalizer.normalize(
        BirthProfile(
          localDate: LocalDate(year: 2021, month: 2, day: 29),
          localTime: LocalTime(hour: 12, minute: 0),
          timeZoneIdentifier: "Asia/Taipei"
        ))
    ) { error in
      XCTAssertEqual(error as? BirthProfileValidationError, .invalidDate)
    }

    XCTAssertThrowsError(
      try CalendarNormalizer.normalize(
        BirthProfile(
          localDate: LocalDate(year: 2021, month: 3, day: 14),
          localTime: LocalTime(hour: 2, minute: 30),
          timeZoneIdentifier: "America/New_York"
        ))
    ) { error in
      XCTAssertEqual(error as? BirthProfileValidationError, .nonexistentLocalTime)
    }

    XCTAssertThrowsError(
      try CalendarNormalizer.normalize(
        BirthProfile(
          localDate: LocalDate(year: 1899, month: 12, day: 31),
          localTime: LocalTime(hour: 12, minute: 0),
          timeZoneIdentifier: "Asia/Taipei"
        ))
    ) { error in
      XCTAssertEqual(error as? BirthProfileValidationError, .dateOutOfRange)
    }
  }

  func testRepeatedLocalTimeUsesFirstOccurrence() throws {
    let normalized = try CalendarNormalizer.normalize(
      BirthProfile(
        localDate: LocalDate(year: 1945, month: 9, day: 30),
        localTime: LocalTime(hour: 1, minute: 30),
        timeZoneIdentifier: "America/New_York"
      ))
    XCTAssertTrue(normalized.isRepeatedLocalTime)
    XCTAssertEqual(normalized.instant.timeIntervalSince1970, -765_397_800, accuracy: 0.1)
  }

  func testAllFourTransformationTables() {
    let expected: [[Star]] = [
      [.lianZhen, .poJun, .wuQu, .taiYang],
      [.tianJi, .tianLiang, .ziWei, .taiYin],
      [.tianTong, .tianJi, .wenChang, .lianZhen],
      [.taiYin, .tianTong, .tianJi, .juMen],
      [.tanLang, .taiYin, .youBi, .tianJi],
      [.wuQu, .tanLang, .tianLiang, .wenQu],
      [.taiYang, .wuQu, .taiYin, .tianTong],
      [.juMen, .taiYang, .wenQu, .wenChang],
      [.tianLiang, .ziWei, .zuoFu, .wuQu],
      [.poJun, .juMen, .taiYin, .tanLang],
    ]
    for stem in HeavenlyStem.allCases {
      let table = ZiWeiRules.transformationStars(yearStem: stem)
      XCTAssertEqual(TransformationKind.allCases.map { table[$0]! }, expected[stem.rawValue])
    }
  }

  func testChartCodableRoundTrip() throws {
    let fixture = try loadFixture(named: "chart_001_normal")
    let chart = try ZiWeiCalculator().calculate(fixture.input)
    let data = try JSONEncoder().encode(chart)
    let decoded = try JSONDecoder().decode(ZiWeiChart.self, from: data)
    XCTAssertEqual(decoded.ruleSet, chart.ruleSet)
    XCTAssertEqual(decoded.birthProfile, chart.birthProfile)
    XCTAssertEqual(decoded.stars, chart.stars)
    XCTAssertEqual(decoded.palaces, chart.palaces)
  }

  private func assertRelations(_ chart: ZiWeiChart, fixtureName: String) {
    let palaceByBranch = Dictionary(
      uniqueKeysWithValues: chart.palaces.map { ($0.stemBranch.branch.rawValue, $0.kind) })
    for palace in chart.palaces {
      let relation = chart.relation(of: palace.kind)
      let branch = palace.stemBranch.branch.rawValue
      XCTAssertEqual(
        relation.trines, [palaceByBranch[(branch + 4) % 12]!, palaceByBranch[(branch + 8) % 12]!],
        fixtureName)
      XCTAssertEqual(relation.opposite, palaceByBranch[(branch + 6) % 12], fixtureName)
    }
  }

  private func loadFixture(named name: String) throws -> GoldenFixture {
    let bundle = Bundle(for: ZiWeiCoreTests.self)
    let url =
      bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? bundle.url(forResource: name, withExtension: "json")
    return try JSONDecoder().decode(
      GoldenFixture.self, from: Data(contentsOf: try XCTUnwrap(url, name)))
  }
}

private struct GoldenFixture: Decodable {
  let schemaVersion: Int
  let ruleSet: RuleSetIdentity
  let sourceReference: String
  let input: BirthProfile
  let expected: Expected

  struct Expected: Decodable {
    let lunarDate: LunarDate
    let hourBranch: String
    let lifeBranch: String
    let bodyBranch: String
    let fiveElementBureau: String
    let palaces: [ExpectedPalace]
    let stars: [String: String]
    let transformations: [String: String]
  }

  struct ExpectedPalace: Decodable {
    let kind: String
    let stem: String
    let branch: String
  }
}

extension HeavenlyStem {
  fileprivate var rawValueName: String {
    ["jia", "yi", "bing", "ding", "wu", "ji", "geng", "xin", "ren", "gui"][rawValue]
  }
}

extension EarthlyBranch {
  fileprivate var rawValueName: String {
    ["zi", "chou", "yin", "mao", "chen", "si", "wu", "wei", "shen", "you", "xu", "hai"][rawValue]
  }
}
