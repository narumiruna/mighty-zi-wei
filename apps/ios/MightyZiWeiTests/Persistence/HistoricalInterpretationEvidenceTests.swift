import XCTest

@testable import MightyZiWei

final class HistoricalInterpretationEvidenceTests: XCTestCase {
  private let validator = PersistedInterpretationEvidenceValidator()
  private let factID = "natal.palace.life.branch"

  private var seed: InterpretationSeed {
    InterpretationSeed(
      id: "seed.personality.baseline", category: .personality,
      meaning: "舊版保存文字不因來源查詢而改寫。", evidenceFactIDs: [factID]
    )
  }

  func test缺少版本不因目前ID有效而回填認證() {
    XCTAssertEqual(status(version: nil), .archivedWithoutVersion)
    XCTAssertNotNil(status(version: nil).limitation)
  }

  func test未知版本保留歷史閱讀狀態且不套用目前契約() {
    XCTAssertEqual(status(version: "999"), .unavailableVersion("999"))
    XCTAssertEqual(status(version: ""), .unavailableVersion(""))
  }

  func test只有明確目前版本及完整引用可核對() {
    XCTAssertEqual(
      status(version: InterpretationContentVersion.current.rawValue), .currentReferences)
    XCTAssertEqual(
      validator.readingStatus(
        contentVersion: "1", seedIDs: [], factIDs: [factID], seeds: [seed], validFactIDs: [factID]
      ),
      .invalidReferences
    )
    XCTAssertEqual(
      validator.readingStatus(
        contentVersion: "1", seedIDs: [seed.id], factIDs: ["unknown"], seeds: [seed],
        validFactIDs: [factID]
      ),
      .invalidReferences
    )
  }

  func testLegacy無Seeds仍可還原但不得冒充目前認證() {
    XCTAssertTrue(
      validator.isValid(seedIDs: [], factIDs: [factID], seeds: [seed], validFactIDs: [factID])
    )
    XCTAssertEqual(
      validator.readingStatus(
        contentVersion: nil, seedIDs: [], factIDs: [factID], seeds: [seed], validFactIDs: [factID]
      ),
      .archivedWithoutVersion
    )
  }

  func test對話輪次保存內容版本且舊資料保持無版本() throws {
    let current = ChartConversationTurn(
      question: "問題",
      answer: "回答",
      evidenceSeedIDs: [seed.id],
      evidenceFactIDs: [factID],
      interpretationContentVersion: InterpretationContentVersion.current.rawValue
    )
    let encoded = try JSONEncoder().encode(current)
    XCTAssertEqual(
      try JSONDecoder().decode(ChartConversationTurn.self, from: encoded)
        .interpretationContentVersion,
      InterpretationContentVersion.current.rawValue
    )
    var legacyObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "interpretationContentVersion")
    let legacy = try JSONDecoder().decode(
      ChartConversationTurn.self,
      from: JSONSerialization.data(withJSONObject: legacyObject)
    )
    XCTAssertNil(legacy.interpretationContentVersion)
  }

  func test重複ID或不完整Seeds不可供目前引用使用() {
    XCTAssertFalse(
      validator.isValid(
        seedIDs: [seed.id], factIDs: [factID, factID], seeds: [seed], validFactIDs: [factID]
      )
    )
    XCTAssertFalse(
      validator.isValid(
        seedIDs: [seed.id], factIDs: [factID], seeds: [seed, seed], validFactIDs: [factID]
      )
    )
    let incomplete = InterpretationSeed(
      id: seed.id, category: seed.category, meaning: seed.meaning,
      evidenceFactIDs: [factID, "unknown"]
    )
    XCTAssertFalse(
      validator.isValid(
        seedIDs: [seed.id], factIDs: [factID], seeds: [incomplete], validFactIDs: [factID]
      )
    )
  }

  private func status(version: String?) -> PersistedInterpretationEvidenceValidator.ReadingStatus {
    validator.readingStatus(
      contentVersion: version, seedIDs: [seed.id], factIDs: [factID],
      seeds: [seed], validFactIDs: [factID]
    )
  }
}
