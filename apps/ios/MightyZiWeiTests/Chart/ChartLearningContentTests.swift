import XCTest
@testable import MightyZiWei

final class ChartLearningContentTests: XCTestCase {
    func test十二宮都有新手可理解的學習內容() {
        XCTAssertEqual(PalaceKind.allCases.count, 12)

        for kind in PalaceKind.allCases {
            let content = ChartLearningCatalog.palace(kind)
            XCTAssertFalse(content.focusTitle.isEmpty, "\(kind) 缺少焦點標題")
            XCTAssertFalse(content.purpose.isEmpty, "\(kind) 缺少用途說明")
            XCTAssertFalse(content.relatedLabel.isEmpty, "\(kind) 缺少生活化名稱")
        }
    }

    func test所有支援星曜都有關鍵詞與漸進學習內容() {
        for star in Star.allCases {
            let content = ChartLearningCatalog.star(star)
            XCTAssertFalse(content.keywords.isEmpty, "\(star) 缺少關鍵詞")
            XCTAssertFalse(content.summary.isEmpty, "\(star) 缺少摘要")
            XCTAssertFalse(content.strengths.isEmpty, "\(star) 缺少優勢說明")
            XCTAssertFalse(content.cautions.isEmpty, "\(star) 缺少留意事項")
        }
    }

    func test宮位摘要只採用目前主星的已驗證Seed() {
        let fact = makeStarFact(star: .ziWei, palace: .life)
        let unrelatedFact = makeStarFact(star: .wuQu, palace: .wealth)
        let seeds = [
            InterpretationSeed(
                id: "seed.personality.ziwei.life",
                category: .personality,
                meaning: "你可能重視自主與整體方向。",
                evidenceFactIDs: [fact.id]
            ),
            InterpretationSeed(
                id: "seed.wealth.wuqu.wealth",
                category: .wealth,
                meaning: "這段不應出現在命宮摘要。",
                evidenceFactIDs: [unrelatedFact.id]
            )
        ]

        let summary = PalaceLearningSummaryBuilder().make(
            palaceKind: .life,
            mainStars: [.ziWei],
            facts: [fact, unrelatedFact],
            seeds: seeds
        )

        XCTAssertEqual(summary, "你可能重視自主與整體方向。")
        XCTAssertFalse(summary.contains("不應出現"))
    }

    func test雙主星摘要最多使用兩段已驗證內容() {
        let stars: [Star] = [.ziWei, .tanLang, .wuQu]
        let facts = stars.map { makeStarFact(star: $0, palace: .life) }
        let seeds = zip(stars, facts).map { pair in
            let (star, fact) = pair
            return InterpretationSeed(
                id: "seed.\(star.rawValue)",
                category: .personality,
                meaning: "\(star.displayName)的已驗證傾向。",
                evidenceFactIDs: [fact.id]
            )
        }

        let summary = PalaceLearningSummaryBuilder().make(
            palaceKind: .life,
            mainStars: stars,
            facts: facts,
            seeds: seeds
        )

        XCTAssertTrue(summary.contains("紫微"))
        XCTAssertTrue(summary.contains("貪狼"))
        XCTAssertFalse(summary.contains("武曲"))
    }

    func test無主星與缺少Seed時提供誠實的部分狀態() {
        let noMainStar = PalaceLearningSummaryBuilder().make(
            palaceKind: .life,
            mainStars: [],
            facts: [],
            seeds: []
        )
        XCTAssertTrue(noMainStar.contains("沒有主星"))
        XCTAssertTrue(noMainStar.contains("不代表"))

        let fact = makeStarFact(star: .ziWei, palace: .life)
        let missingMeaning = PalaceLearningSummaryBuilder().make(
            palaceKind: .life,
            mainStars: [.ziWei],
            facts: [fact],
            seeds: []
        )
        XCTAssertTrue(missingMeaning.contains("紫微"))
        XCTAssertTrue(missingMeaning.contains("更多規則資料"))
    }

    private func makeStarFact(star: Star, palace: PalaceKind) -> ChartFact {
        ChartFact(
            id: "natal.star.\(star.rawValue).palace",
            category: .star,
            subject: .init(kind: "star", identifier: star.rawValue),
            value: .init(kind: "palace", identifier: palace.rawValue),
            displayText: "\(star.displayName)位於\(palace.displayName)。"
        )
    }
}
