import XCTest
@testable import MightyZiWei

final class ChartFactBuilderTests: XCTestCase {
    func testFactID穩定且依ID可還原顯示文字() throws {
        let chart = try ZiWeiCalculator().calculate(BirthProfile(
            localDate: LocalDate(year: 1990, month: 6, day: 15),
            localTime: LocalTime(hour: 10, minute: 30),
            timeZoneIdentifier: "Asia/Taipei"
        ))

        let facts = ChartFactBuilder().makeFacts(from: chart)
        let factsByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })

        XCTAssertEqual(facts.count, factsByID.count)
        XCTAssertEqual(factsByID["natal.palace.life.branch"]?.value.kind, "branch")
        XCTAssertEqual(factsByID["natal.star.ziWei.palace"]?.subject.identifier, "ziWei")
        XCTAssertEqual(factsByID["natal.transformation.lu.star"]?.displayText, "太陽化祿，位於財帛宮。")
        XCTAssertFalse(factsByID["natal.palace.life.sanFangSiZheng"]?.displayText.isEmpty ?? true)
    }

    func test所有Seeds只引用本次命盤Facts() throws {
        let chart = try ZiWeiCalculator().calculate(BirthProfile(
            localDate: LocalDate(year: 2024, month: 2, day: 10),
            localTime: LocalTime(hour: 0, minute: 30),
            timeZoneIdentifier: "Asia/Taipei"
        ))
        let facts = ChartFactBuilder().makeFacts(from: chart)
        let factIDs = Set(facts.map(\.id))
        let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)

        XCTAssertEqual(Set(seeds.map(\.category)), Set(InterpretationCategory.allCases))
        XCTAssertTrue(seeds.flatMap(\.evidenceFactIDs).allSatisfy(factIDs.contains))
    }
}
