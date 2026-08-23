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
