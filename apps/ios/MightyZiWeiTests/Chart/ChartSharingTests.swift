import XCTest

@testable import MightyZiWei

final class ChartSharingTests: XCTestCase {
  func test包含任何個資時分享前必須再次確認() {
    let guardPolicy = ChartSharePrivacyGuard()

    XCTAssertFalse(guardPolicy.requiresConfirmation(options: .init()))
    XCTAssertTrue(guardPolicy.requiresConfirmation(options: .init(includesName: true)))
    XCTAssertTrue(guardPolicy.requiresConfirmation(options: .init(includesBirthData: true)))
  }

  func test預設分享隱藏姓名出生日期時間與時區() throws {
    let chart = try makeChart()
    let text = ChartShareBuilder().makeText(
      chart: chart,
      name: "小明",
      options: .init()
    )

    XCTAssertFalse(text.contains("小明"))
    XCTAssertFalse(text.contains("1990/06/15"))
    XCTAssertFalse(text.contains("10:30"))
    XCTAssertFalse(text.contains("Asia/Taipei"))
    XCTAssertTrue(text.contains("命宮"))
    XCTAssertTrue(text.contains("規則集"))
  }

  func test使用者可明確選擇包含個資() throws {
    let chart = try makeChart()
    let text = ChartShareBuilder().makeText(
      chart: chart,
      name: "小明",
      options: .init(includesName: true, includesBirthData: true)
    )

    XCTAssertTrue(text.contains("小明"))
    XCTAssertTrue(text.contains("1990/06/15"))
    XCTAssertTrue(text.contains("10:30"))
    XCTAssertTrue(text.contains("Asia/Taipei"))
  }

  private func makeChart() throws -> ZiWeiChart {
    try ZiWeiCalculator().calculate(
      BirthProfile(
        localDate: LocalDate(year: 1990, month: 6, day: 15),
        localTime: LocalTime(hour: 10, minute: 30),
        timeZoneIdentifier: "Asia/Taipei"
      ))
  }
}
