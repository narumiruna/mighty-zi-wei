import XCTest

@testable import MightyZiWei

final class InterpretationEvidenceResolverTests: XCTestCase {
  private func seed(_ id: String, facts: [String]) -> InterpretationSeed {
    InterpretationSeed(id: id, category: .overview, meaning: "傾向", evidenceFactIDs: facts)
  }

  func test輸入重複依序回報Fact再Seed() {
    XCTAssertThrowsError(
      try InterpretationEvidenceResolver(
        factIDs: ["甲", "甲"], seeds: [seed("一", facts: ["甲"]), seed("一", facts: ["甲"])])
    ) { XCTAssertEqual($0 as? InterpretationEvidenceResolver.ResolutionError, .duplicateFact("甲")) }
    XCTAssertThrowsError(
      try InterpretationEvidenceResolver(
        factIDs: ["甲"], seeds: [seed("一", facts: ["甲"]), seed("一", facts: ["甲"])])
    ) { XCTAssertEqual($0 as? InterpretationEvidenceResolver.ResolutionError, .duplicateSeed("一")) }
  }

  func test選取順序去重與空選取由呼叫端決定() throws {
    let resolver = try InterpretationEvidenceResolver(
      factIDs: ["甲", "乙", "丙"],
      seeds: [seed("一", facts: ["乙", "甲"]), seed("二", facts: ["甲", "丙"])])
    XCTAssertEqual(try resolver.resolve(seedIDs: ["一", "二"]), ["乙", "甲", "丙"])
    XCTAssertEqual(try resolver.resolve(seedIDs: ["二", "一"]), ["甲", "丙", "乙"])
    XCTAssertEqual(try resolver.resolve(seedIDs: []), [])
    XCTAssertNoThrow(try resolver.validate(factIDs: []))
    for identifier in ["未知", "", " "] {
      XCTAssertThrowsError(try resolver.resolve(seedIDs: [identifier])) {
        XCTAssertEqual(
          $0 as? InterpretationEvidenceResolver.ResolutionError, .unknownSeed(identifier))
      }
    }
    XCTAssertThrowsError(try resolver.resolve(seedIDs: ["一", "一"])) {
      XCTAssertEqual($0 as? InterpretationEvidenceResolver.ResolutionError, .duplicateSeed("一"))
    }
    XCTAssertThrowsError(try resolver.resolve(seedIDs: ["一"], category: .career)) {
      XCTAssertEqual(
        $0 as? InterpretationEvidenceResolver.ResolutionError, .seedCategoryMismatch("一"))
    }
    XCTAssertThrowsError(try resolver.validate(factIDs: ["甲", "甲"])) {
      XCTAssertEqual($0 as? InterpretationEvidenceResolver.ResolutionError, .duplicateFact("甲"))
    }
    XCTAssertThrowsError(try resolver.validate(factIDs: ["未知"])) {
      XCTAssertEqual($0 as? InterpretationEvidenceResolver.ResolutionError, .unknownFact("未知"))
    }
  }

  func testSeed內空白重複或未知Fact均拒絕() throws {
    for evidence in [[], ["甲", "甲"], [""], [" "], ["未知"]] {
      let resolver = try InterpretationEvidenceResolver(
        factIDs: ["甲"], seeds: [seed("一", facts: evidence)])
      XCTAssertThrowsError(try resolver.resolve(seedIDs: ["一"])) {
        XCTAssertEqual(
          $0 as? InterpretationEvidenceResolver.ResolutionError, .invalidSeedEvidence("一"))
      }
    }
  }
}
