import XCTest

@testable import MightyZiWei

final class DualChartInteractionReferenceBuilderTests: XCTestCase {
  func test只並列四個指定宮位及十四主星事實() throws {
    let first = try makeChart(year: 1990, month: 6, day: 15, hour: 10)
    let second = try makeChart(year: 1992, month: 8, day: 20, hour: 18)
    let reference = DualChartInteractionReferenceBuilder().make(
      firstChart: first,
      secondChart: second
    )

    XCTAssertEqual(reference.comparisons.map(\.palaceKind), [.life, .spouse, .travel, .friends])
    XCTAssertTrue(reference.hasCompleteComparedPalaceFacts)

    for comparison in reference.comparisons {
      let firstFacts = try XCTUnwrap(comparison.firstChart)
      let secondFacts = try XCTUnwrap(comparison.secondChart)
      XCTAssertEqual(firstFacts.palace.kind, comparison.palaceKind)
      XCTAssertEqual(secondFacts.palace.kind, comparison.palaceKind)
      XCTAssertTrue(firstFacts.mainStars.allSatisfy { $0.star.category == .main })
      XCTAssertTrue(secondFacts.mainStars.allSatisfy { $0.star.category == .main })
      XCTAssertEqual(
        firstFacts.mainStars,
        first.stars.filter { $0.star.category == .main && $0.palace == comparison.palaceKind }
      )
      XCTAssertEqual(
        secondFacts.mainStars,
        second.stars.filter { $0.star.category == .main && $0.palace == comparison.palaceKind }
      )
    }
  }

  func test明確標示資料不足且不產生相容性判定() throws {
    let first = try makeChart(year: 1990, month: 6, day: 15, hour: 10)
    let second = try makeChart(year: 1992, month: 8, day: 20, hour: 18)
    let reference = DualChartInteractionReferenceBuilder().make(
      firstChart: first,
      secondChart: second
    )
    let limitations = reference.limitations.joined(separator: " ")

    XCTAssertTrue(limitations.contains("資料不足"))
    XCTAssertTrue(limitations.contains("不能用來判定相容性"))
    XCTAssertTrue(limitations.contains("適配度"))
    XCTAssertTrue(limitations.contains("關係結果"))
  }

  func test缺少任一命盤時保留範圍並指出缺少資料() throws {
    let first = try makeChart(year: 1990, month: 6, day: 15, hour: 10)
    let reference = DualChartInteractionReferenceBuilder().make(
      firstChart: first,
      secondChart: nil
    )

    XCTAssertFalse(reference.hasCompleteComparedPalaceFacts)
    XCTAssertEqual(reference.comparisons.count, 4)
    XCTAssertTrue(
      reference.comparisons.allSatisfy { $0.firstChart != nil && $0.secondChart == nil })
    XCTAssertTrue(reference.limitations.contains("缺少第二張命盤資料。"))
  }

  private func makeChart(
    year: Int,
    month: Int,
    day: Int,
    hour: Int
  ) throws -> ZiWeiChart {
    try ZiWeiCalculator().calculate(
      BirthProfile(
        localDate: LocalDate(year: year, month: month, day: day),
        localTime: LocalTime(hour: hour, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))
  }
}
