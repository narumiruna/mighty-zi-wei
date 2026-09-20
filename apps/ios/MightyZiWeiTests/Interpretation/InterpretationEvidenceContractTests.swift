import XCTest

@testable import MightyZiWei

final class InterpretationEvidenceContractTests: XCTestCase {
  private var facts: [ChartFact] {
    ["甲", "乙", "丙"].map {
      ChartFact(
        id: $0, category: .star,
        subject: .init(kind: "star", identifier: "ziWei"),
        value: .init(kind: "palace", identifier: "life"), displayText: "命盤依據。"
      )
    }
  }

  private func seed(
    _ id: String, category: InterpretationCategory = .overview, evidence: [String]
  ) -> InterpretationSeed {
    InterpretationSeed(
      id: "seed.\(id)", category: category, meaning: "可能的傾向。", evidenceFactIDs: evidence)
  }

  private func sections(
    content: String = "可能的傾向。", seedIDs: [String] = ["一", "二"],
    factIDs: [String] = ["乙", "甲", "丙"]
  ) -> [InterpretationSection] {
    InterpretationCategory.allCases.map {
      InterpretationSection(
        id: $0.rawValue, category: $0, title: $0.title, content: content,
        evidenceSeedIDs: ($0 == .overview ? seedIDs : [$0.rawValue]).map { "seed.\($0)" },
        evidenceFactIDs: $0 == .overview ? factIDs : ["甲"]
      )
    }
  }

  private var seeds: [InterpretationSeed] {
    [seed("一", evidence: ["乙", "甲"]), seed("二", evidence: ["甲", "丙"])]
      + InterpretationCategory.allCases.filter { $0 != .overview }.map {
        seed($0.rawValue, category: $0, evidence: ["甲"])
      }
  }

  private func answer(
    content: String = "可能的傾向。", seedIDs: [String] = ["一", "二"],
    factIDs: [String] = ["乙", "甲", "丙"]
  ) -> ChartConversationAnswer {
    ChartConversationAnswer(
      status: .answered, content: content, evidenceSeedIDs: seedIDs.map { "seed.\($0)" },
      evidenceFactIDs: factIDs)
  }

  func test三種驗證保留Seed順序並只去除跨Seed重複Fact() throws {
    XCTAssertEqual(
      try InterpretationValidator().validate(sections: sections(), facts: facts, seeds: seeds)
        .first?.evidenceFactIDs, ["乙", "甲", "丙"])
    XCTAssertEqual(
      try ConversationAnswerValidator().validate(answer(), facts: facts, seeds: seeds)
        .evidenceFactIDs, ["乙", "甲", "丙"])
    let archived = PersistedInterpretationEvidenceValidator()
    XCTAssertTrue(
      archived.isValid(
        seedIDs: ["seed.一", "seed.二"], factIDs: ["乙", "甲", "丙"], seeds: seeds,
        validFactIDs: ["甲", "乙", "丙"]))
    XCTAssertFalse(
      archived.isValid(
        seedIDs: ["seed.一", "seed.二"], factIDs: ["甲", "乙", "丙"], seeds: seeds,
        validFactIDs: ["甲", "乙", "丙"]))
    XCTAssertThrowsError(
      try InterpretationValidator().validate(
        sections: sections(factIDs: ["甲", "乙", "丙"]), facts: facts, seeds: seeds)
    ) {
      XCTAssertEqual($0 as? InterpretationValidator.ValidationError, .evidenceMismatch(.overview))
    }
    XCTAssertThrowsError(
      try ConversationAnswerValidator().validate(
        answer(factIDs: ["甲", "乙", "丙"]), facts: facts, seeds: seeds)
    ) { XCTAssertEqual($0 as? ConversationAnswerValidator.ValidationError, .evidenceMismatch) }
  }

  func test解讀輸入重複優先於段落而對話內容優先於輸入重複() {
    XCTAssertThrowsError(
      try InterpretationValidator().validate(
        sections: [], facts: facts + facts, seeds: seeds + seeds)
    ) { XCTAssertEqual($0 as? InterpretationValidator.ValidationError, .duplicateEvidence("甲")) }
    XCTAssertThrowsError(
      try InterpretationValidator().validate(sections: [], facts: facts, seeds: seeds + seeds)
    ) { XCTAssertEqual($0 as? InterpretationValidator.ValidationError, .duplicateSeed("seed.一")) }
    XCTAssertThrowsError(
      try ConversationAnswerValidator().validate(
        answer(content: "你一定會成功。", seedIDs: [], factIDs: []),
        facts: facts + facts, seeds: seeds + seeds)
    ) { XCTAssertEqual($0 as? ConversationAnswerValidator.ValidationError, .unsafeContent) }
    XCTAssertThrowsError(
      try ConversationAnswerValidator().validate(
        answer(content: " \n ", seedIDs: [], factIDs: []), facts: facts + facts, seeds: seeds)
    ) { XCTAssertEqual($0 as? ConversationAnswerValidator.ValidationError, .emptyContent) }
  }

  func test解讀分類優先於無效Seed依據且對話不限制分類() throws {
    let invalid = [seed("一", category: .career, evidence: [])]
    XCTAssertThrowsError(
      try InterpretationValidator().validate(sections: sections(), facts: facts, seeds: invalid)
    ) {
      XCTAssertEqual(
        $0 as? InterpretationValidator.ValidationError, .seedCategoryMismatch("seed.一"))
    }
    let mixed = [seed("一", category: .career, evidence: ["乙", "甲"]), seeds[1]]
    XCTAssertNoThrow(
      try ConversationAnswerValidator().validate(answer(), facts: facts, seeds: mixed))
  }

  func test空白未知重複Seed與Seed內不完整Fact均拒絕且保留精確錯誤() {
    for identifier in ["未知", " "] {
      XCTAssertThrowsError(
        try InterpretationValidator().validate(
          sections: sections(seedIDs: [identifier]), facts: facts, seeds: seeds)
      ) {
        XCTAssertEqual(
          $0 as? InterpretationValidator.ValidationError, .unknownSeed("seed.\(identifier)"))
      }
    }
    XCTAssertThrowsError(
      try InterpretationValidator().validate(
        sections: sections(seedIDs: ["一", "一"]), facts: facts, seeds: seeds)
    ) { XCTAssertEqual($0 as? InterpretationValidator.ValidationError, .duplicateSeed("seed.一")) }
    for evidence in [[], ["甲", "甲"], ["未知"], [" "]] {
      let invalid = [seed("一", evidence: evidence)]
      XCTAssertThrowsError(
        try InterpretationValidator().validate(sections: sections(), facts: facts, seeds: invalid)
      ) {
        XCTAssertEqual(
          $0 as? InterpretationValidator.ValidationError, .invalidSeedEvidence("seed.一"))
      }
      XCTAssertThrowsError(
        try ConversationAnswerValidator().validate(answer(), facts: facts, seeds: invalid)
      ) {
        XCTAssertEqual(
          $0 as? ConversationAnswerValidator.ValidationError, .invalidSeedEvidence("seed.一"))
      }
    }
  }

  func test封存版本判定優先於無效引用且Legacy空引用仍可還原() {
    let validator = PersistedInterpretationEvidenceValidator()
    for (version, expected) in [
      (nil, PersistedInterpretationEvidenceValidator.ReadingStatus.archivedWithoutVersion),
      ("未知", .unavailableVersion("未知")),
      (InterpretationContentVersion.current.rawValue, .invalidReferences),
    ] {
      XCTAssertEqual(
        validator.readingStatus(
          contentVersion: version, seedIDs: ["未知"], factIDs: [], seeds: seeds,
          validFactIDs: ["甲"]), expected)
    }
    XCTAssertTrue(validator.isValid(seedIDs: [], factIDs: [], seeds: seeds, validFactIDs: []))
    XCTAssertFalse(
      validator.isValid(seedIDs: [], factIDs: [], seeds: seeds + seeds, validFactIDs: []))
  }

  func test所有免責語句接受但後續不安全宣稱仍拒絕() {
    let disclaimers = [
      "未必一定會", "不一定會", "不是一定會", "並非一定會", "不代表一定會", "不表示一定會",
      "無法保證", "不是保證", "並非保證", "不代表保證", "不等於保證", "不能視為保證", "不能保證", "不應保證", "不保證",
      "無法替你診斷", "不能替你診斷", "不會替你診斷", "無法判定診斷結果是", "不能判定診斷結果是", "不會宣稱診斷結果是",
      "無法提供治療方案", "不能提供治療方案", "不提供治療方案",
      "不構成任何投資建議", "不構成投資建議", "不是投資建議", "並非投資建議", "不可視為投資建議",
      "不構成任何法律建議", "不構成法律建議", "不是法律建議", "並非法律建議", "不可視為法律建議",
      "無法提供健康診斷", "不能提供健康診斷", "不提供健康診斷", "無法提供投資建議", "不能提供投資建議", "不提供投資建議",
      "無法提供法律建議", "不能提供法律建議", "不提供法律建議",
    ]
    for disclaimer in disclaimers {
      XCTAssertNoThrow(
        try InterpretationValidator().validate(
          sections: sections(content: disclaimer), facts: facts, seeds: seeds), disclaimer)
      XCTAssertNoThrow(
        try ConversationAnswerValidator().validate(
          answer(content: disclaimer), facts: facts, seeds: seeds), disclaimer)
      XCTAssertThrowsError(
        try InterpretationValidator().validate(
          sections: sections(content: disclaimer + "，你必定會成功。"), facts: facts, seeds: seeds))
      XCTAssertThrowsError(
        try ConversationAnswerValidator().validate(
          answer(content: disclaimer + "，你必定會成功。"), facts: facts, seeds: seeds))
    }
  }
}
