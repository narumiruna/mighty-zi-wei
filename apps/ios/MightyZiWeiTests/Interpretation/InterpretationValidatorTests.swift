import XCTest
@testable import MightyZiWei

final class InterpretationValidatorTests: XCTestCase {
    private let fact = ChartFact(
        id: "natal.star.ziwei.palace",
        category: .star,
        subject: .init(kind: "star", identifier: "ziWei"),
        value: .init(kind: "palace", identifier: "life"),
        displayText: "紫微位於命宮。"
    )

    func test接受五個分類與線索完全對應的命盤依據() throws {
        let result = try InterpretationValidator().validate(
            sections: makeSections(),
            facts: [fact],
            seeds: makeSeeds()
        )

        XCTAssertEqual(result.count, InterpretationCategory.allCases.count)
    }

    func test拒絕未知重複與分類錯誤的解讀線索() {
        let unknown = makeSections(seedIDs: { category in
            category == .career ? ["unknown"] : ["seed.\(category.rawValue)"]
        })
        XCTAssertThrowsError(try validate(unknown))

        let duplicate = makeSections(seedIDs: { category in
            let identifier = "seed.\(category.rawValue)"
            return category == .overview ? [identifier, identifier] : [identifier]
        })
        XCTAssertThrowsError(try validate(duplicate))

        let wrongCategory = makeSections(seedIDs: { category in
            category == .career ? ["seed.personality"] : ["seed.\(category.rawValue)"]
        })
        XCTAssertThrowsError(try validate(wrongCategory))
    }

    func test拒絕線索與命盤依據不一致() {
        let unknownFact = makeSections(
            evidence: { category in
                category == .career ? ["unknown"] : [self.fact.id]
            }
        )
        XCTAssertThrowsError(try validate(unknownFact))

        let missingFact = makeSections(
            evidence: { category in
                category == .career ? [] : [self.fact.id]
            }
        )
        XCTAssertThrowsError(try validate(missingFact))

        let duplicateFact = makeSections(
            evidence: { category in
                category == .overview ? [self.fact.id, self.fact.id] : [self.fact.id]
            }
        )
        XCTAssertThrowsError(try validate(duplicateFact))
    }

    func test拒絕空白與確定式或專業建議() {
        for content in ["   ", "你一定會成功。", "以下是適合你的投資建議。"] {
            let sections = makeSections(content: { category in
                category == .wealth ? content : "你可能傾向先掌握整體方向。"
            })
            XCTAssertThrowsError(try validate(sections))
        }
    }

    func test接受否定式確定語氣與專業建議免責文字() {
        let sections = makeSections(content: { category in
            switch category {
            case .career:
                "接近四十歲不一定會限制你的工作選擇。"
            case .wealth:
                "這是資源安排傾向，不構成任何投資建議。"
            default:
                "你可能傾向先掌握整體方向。"
            }
        })

        XCTAssertNoThrow(try validate(sections))
    }

    func test對話回答必須引用線索及其完整命盤依據() throws {
        let seed = try XCTUnwrap(makeSeeds().first)
        let answer = ChartConversationAnswer(
            status: .answered,
            content: "你可能傾向先掌握整體方向。",
            evidenceSeedIDs: [seed.id],
            evidenceFactIDs: [fact.id]
        )

        XCTAssertEqual(
            try ConversationAnswerValidator().validate(
                answer,
                facts: [fact],
                seeds: [seed]
            ),
            answer
        )

        for invalid in [
            ChartConversationAnswer(
                status: .answered,
                content: answer.content,
                evidenceSeedIDs: ["unknown"],
                evidenceFactIDs: [fact.id]
            ),
            ChartConversationAnswer(
                status: .answered,
                content: answer.content,
                evidenceSeedIDs: [seed.id, seed.id],
                evidenceFactIDs: [fact.id]
            ),
            ChartConversationAnswer(
                status: .answered,
                content: answer.content,
                evidenceSeedIDs: [seed.id],
                evidenceFactIDs: ["unknown"]
            ),
            ChartConversationAnswer(
                status: .answered,
                content: answer.content,
                evidenceSeedIDs: [seed.id],
                evidenceFactIDs: []
            )
        ] {
            XCTAssertThrowsError(
                try ConversationAnswerValidator().validate(
                    invalid,
                    facts: [fact],
                    seeds: [seed]
                )
            )
        }
    }

    func test不支援回答保留具體替代方向且不得附加依據() throws {
        let content = "目前不能診斷健康；可以改問壓力下的反應傾向。"
        let unsupported = ChartConversationAnswer(
            status: .unsupported,
            content: content,
            evidenceFactIDs: []
        )

        let validated = try ConversationAnswerValidator().validate(
            unsupported,
            facts: [fact],
            seeds: makeSeeds()
        )
        XCTAssertEqual(validated.content, content)
        XCTAssertTrue(validated.evidenceSeedIDs.isEmpty)
        XCTAssertTrue(validated.evidenceFactIDs.isEmpty)

        XCTAssertThrowsError(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .unsupported,
                    content: content,
                    evidenceSeedIDs: ["seed.overview"],
                    evidenceFactIDs: [fact.id]
                ),
                facts: [fact],
                seeds: makeSeeds()
            )
        )
    }

    func test對話回答拒絕空白過長與不安全內容() {
        let seed = makeSeeds()[0]
        for content in [
            "   ",
            "你一定會成功。",
            "以下是適合你的投資建議。",
            String(repeating: "字", count: 2_001)
        ] {
            XCTAssertThrowsError(
                try ConversationAnswerValidator().validate(
                    ChartConversationAnswer(
                        status: .answered,
                        content: content,
                        evidenceSeedIDs: [seed.id],
                        evidenceFactIDs: [fact.id]
                    ),
                    facts: [fact],
                    seeds: [seed]
                )
            )
        }
    }

    private func validate(_ sections: [InterpretationSection]) throws -> [InterpretationSection] {
        try InterpretationValidator().validate(
            sections: sections,
            facts: [fact],
            seeds: makeSeeds()
        )
    }

    private func makeSeeds() -> [InterpretationSeed] {
        InterpretationCategory.allCases.map { category in
            InterpretationSeed(
                id: "seed.\(category.rawValue)",
                category: category,
                meaning: "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }
    }

    private func makeSections(
        seedIDs: (InterpretationCategory) -> [String] = { ["seed.\($0.rawValue)"] },
        evidence: (InterpretationCategory) -> [String]? = { _ in nil },
        content: (InterpretationCategory) -> String = { _ in "你可能傾向先掌握整體方向。" }
    ) -> [InterpretationSection] {
        InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: content(category),
                evidenceSeedIDs: seedIDs(category),
                evidenceFactIDs: evidence(category) ?? [fact.id]
            )
        }
    }
}
