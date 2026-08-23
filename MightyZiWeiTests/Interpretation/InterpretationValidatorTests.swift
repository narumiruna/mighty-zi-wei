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

    func test接受五個分類與已知依據() throws {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        let result = try InterpretationValidator().validate(sections: sections, facts: [fact])

        XCTAssertEqual(result.count, InterpretationCategory.allCases.count)
    }

    func test拒絕未知依據() {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [category == .career ? "unknown" : fact.id]
            )
        }

        XCTAssertThrowsError(try InterpretationValidator().validate(sections: sections, facts: [fact]))
    }

    func test拒絕重複依據與空白內容() {
        let duplicateEvidence = makeSections { category in
            category == .overview ? [fact.id, fact.id] : [fact.id]
        }
        XCTAssertThrowsError(
            try InterpretationValidator().validate(sections: duplicateEvidence, facts: [fact])
        )

        let emptyContent = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .personality ? "   " : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }
        XCTAssertThrowsError(
            try InterpretationValidator().validate(sections: emptyContent, facts: [fact])
        )
    }

    func test接受否定式專業建議免責文字() throws {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .wealth
                    ? "財帛宮適合用來觀察資源安排傾向，但不構成任何投資建議。"
                    : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        let result = try InterpretationValidator().validate(sections: sections, facts: [fact])

        XCTAssertEqual(result.count, InterpretationCategory.allCases.count)
    }

    func test接受否定式確定語氣() throws {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .career
                    ? "接近四十歲不一定會限制你的工作選擇。"
                    : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        XCTAssertNoThrow(
            try InterpretationValidator().validate(sections: sections, facts: [fact])
        )
        XCTAssertNoThrow(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .answered,
                    content: "年齡不一定會限制你的工作選擇，也無法保證單一路線最合適。",
                    evidenceFactIDs: [fact.id]
                ),
                facts: [fact]
            )
        )
    }

    func test接受一般提及專業詞彙() throws {
        let content = "命盤不能替代診斷或治療；買進與賣出仍應依現實資訊自行判斷。"
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .overview ? content : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        XCTAssertNoThrow(
            try InterpretationValidator().validate(sections: sections, facts: [fact])
        )
        XCTAssertNoThrow(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .answered,
                    content: content,
                    evidenceFactIDs: [fact.id]
                ),
                facts: [fact]
            )
        )
    }

    func test仍拒絕實際專業建議() {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .wealth
                    ? "以下是適合你的投資建議。"
                    : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        XCTAssertThrowsError(
            try InterpretationValidator().validate(sections: sections, facts: [fact])
        )
    }

    func test拒絕確定式預測() {
        let sections = InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: category == .wealth ? "你一定會獲利。" : "你可能傾向先掌握整體方向。",
                evidenceFactIDs: [fact.id]
            )
        }

        XCTAssertThrowsError(try InterpretationValidator().validate(sections: sections, facts: [fact]))
    }

    func test對話回答必須引用已知且不重複的依據() throws {
        let answer = ChartConversationAnswer(
            status: .answered,
            content: "你可能傾向先掌握整體方向。",
            evidenceFactIDs: [fact.id]
        )

        XCTAssertEqual(
            try ConversationAnswerValidator().validate(answer, facts: [fact]),
            answer
        )

        XCTAssertThrowsError(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .answered,
                    content: answer.content,
                    evidenceFactIDs: ["unknown"]
                ),
                facts: [fact]
            )
        )
        XCTAssertThrowsError(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .answered,
                    content: answer.content,
                    evidenceFactIDs: [fact.id, fact.id]
                ),
                facts: [fact]
            )
        )
    }

    func test不支援的對話回答不得附加命盤依據() throws {
        let unsupported = ChartConversationAnswer(
            status: .unsupported,
            content: "目前命盤資料不足以回答這個問題。",
            evidenceFactIDs: []
        )

        let validated = try ConversationAnswerValidator().validate(unsupported, facts: [fact])
        XCTAssertEqual(validated.status, .unsupported)
        XCTAssertTrue(validated.evidenceFactIDs.isEmpty)
        XCTAssertTrue(validated.content.contains("目前命盤資料不足"))
        XCTAssertThrowsError(
            try ConversationAnswerValidator().validate(
                ChartConversationAnswer(
                    status: .unsupported,
                    content: unsupported.content,
                    evidenceFactIDs: [fact.id]
                ),
                facts: [fact]
            )
        )
    }

    func test對話回答拒絕空白與不安全內容() {
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
                        evidenceFactIDs: [fact.id]
                    ),
                    facts: [fact]
                )
            )
        }
    }

    private func makeSections(
        evidence: (InterpretationCategory) -> [String]
    ) -> [InterpretationSection] {
        InterpretationCategory.allCases.map { category in
            InterpretationSection(
                id: category.rawValue,
                category: category,
                title: category.title,
                content: "你可能傾向先掌握整體方向。",
                evidenceFactIDs: evidence(category)
            )
        }
    }
}
