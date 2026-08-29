import XCTest
@testable import MightyZiWei

final class InterpretationSeedBuilderTests: XCTestCase {
    func test五個分類都有基本解讀與有效依據() {
        let facts = [
            fact(id: "natal.bureau", subject: "bureau", value: "woodThree"),
            fact(id: "natal.palace.life.branch", subject: "life", value: "yin"),
            fact(id: "natal.palace.career.branch", subject: "career", value: "wu"),
            fact(id: "natal.palace.wealth.branch", subject: "wealth", value: "xu"),
            fact(id: "natal.palace.spouse.branch", subject: "spouse", value: "zi")
        ]

        let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)

        XCTAssertEqual(Set(seeds.map(\.category)), Set(InterpretationCategory.allCases))
        XCTAssertTrue(seeds.allSatisfy { !$0.evidenceFactIDs.isEmpty })
    }

    func test星曜規則只引用App提供的事實() {
        let starFact = ChartFact(
            id: "natal.star.ziWei.palace",
            category: .star,
            subject: .init(kind: "star", identifier: "ziWei"),
            value: .init(kind: "palace", identifier: "life"),
            displayText: "紫微位於命宮。"
        )

        let seeds = InterpretationSeedBuilder().makeSeeds(from: [starFact])
        let starSeed = seeds.first { $0.id.contains("ziWei") }

        XCTAssertEqual(starSeed?.category, .personality)
        XCTAssertEqual(starSeed?.evidenceFactIDs, [starFact.id])
    }

    func test基本解讀先說個人化傾向再提供情境核對問題() throws {
        let facts = [
            fact(id: "natal.palace.life.branch", subject: "life", value: "yin"),
            starFact(id: "ziWei", palace: "life", text: "紫微位於命宮。"),
            starFact(id: "tianJi", palace: "fortune", text: "天機位於福德宮。")
        ]
        let seeds = InterpretationSeedBuilder().makeSeeds(from: facts)
        let interpretation = RuleBasedInterpreter().interpret(facts: facts, seeds: seeds)
        let section = try XCTUnwrap(
            interpretation.sections.first { $0.category == .personality }
        )

        XCTAssertTrue(section.content.hasPrefix("紫微位於命宮。你可能傾向先形成自己的判斷"))
        XCTAssertTrue(section.content.contains("其他已驗證線索："))
        XCTAssertTrue(section.content.contains("天機位於福德宮。"))
        XCTAssertFalse(section.content.contains("輪流出現"))
        XCTAssertFalse(section.content.contains("互相支持"))
        XCTAssertTrue(section.content.contains("拿生活來核對："))
        XCTAssertEqual(
            section.evidenceSeedIDs,
            ["seed.personality.ziWei.life", "seed.personality.tianJi.fortune"]
        )
        XCTAssertEqual(
            section.evidenceFactIDs,
            ["natal.star.ziWei.palace", "natal.star.tianJi.palace"]
        )
        XCTAssertFalse(section.evidenceSeedIDs.contains("seed.personality.baseline"))
    }

    func test只有Baseline線索時使用中性核對問題() throws {
        let lifeFact = fact(
            id: "natal.palace.life.branch",
            subject: "life",
            value: "yin"
        )
        let baseline = InterpretationSeed(
            id: "seed.personality.baseline",
            category: .personality,
            meaning: "命宮可先用來觀察你面對選擇時的實際反應。",
            evidenceFactIDs: [lifeFact.id]
        )

        let interpretation = RuleBasedInterpreter().interpret(
            facts: [lifeFact],
            seeds: [baseline]
        )
        let section = try XCTUnwrap(
            interpretation.sections.first { $0.category == .personality }
        )

        XCTAssertTrue(section.content.contains("上面的觀察和你近期哪一次真實經驗最接近"))
        XCTAssertTrue(section.content.contains("哪一次不符合"))
        XCTAssertFalse(section.content.contains("形成判斷"))
        XCTAssertFalse(section.content.contains("蒐集資訊"))
        XCTAssertFalse(section.content.contains("觀察他人反應"))
    }

    private func starFact(
        id: String,
        palace: String,
        text: String
    ) -> ChartFact {
        ChartFact(
            id: "natal.star.\(id).palace",
            category: .star,
            subject: .init(kind: "star", identifier: id),
            value: .init(kind: "palace", identifier: palace),
            displayText: text
        )
    }

    private func fact(id: String, subject: String, value: String) -> ChartFact {
        ChartFact(
            id: id,
            category: .palace,
            subject: .init(kind: "palace", identifier: subject),
            value: .init(kind: "branch", identifier: value),
            displayText: "測試事實"
        )
    }
}
