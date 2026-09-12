import XCTest

@MainActor
final class ChartReadingGuideUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func test四步可跳過續讀完成再開且不遮蔽主要閱讀入口() {
    launch()
    createChart()
    XCTAssertTrue(app.buttons["chart.interpretation"].isHittable)
    XCTAssertTrue(app.buttons["chart.askAI"].isHittable)
    let tabCount = app.tabBars.buttons.count
    openGuide()
    assertStep(1)
    XCTAssertFalse(app.buttons["guide.previous"].exists)
    XCTAssertTrue(app.staticTexts["guide.storage"].label.contains("本次命盤畫面"))
    app.buttons["guide.next"].tap()
    assertStep(2)
    app.buttons["guide.skip"].tap()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.tabBars.buttons.count, tabCount)
    app.scrollToVisibleContent(app.buttons["chart.interpretation"])
    XCTAssertTrue(app.buttons["chart.interpretation"].isHittable)
    XCTAssertTrue(app.buttons["chart.askAI"].exists)
    openGuide()
    assertStep(2)
    app.buttons["guide.previous"].tap()
    assertStep(1)
    for step in 2...4 {
      app.buttons["guide.next"].tap()
      assertStep(step)
    }
    XCTAssertEqual(app.buttons["guide.next"].label, "完成導覽")
    app.buttons["guide.next"].tap()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    openGuide()
    assertStep(1)
  }

  func test已存命盤離開畫面後仍可續讀() {
    launch()
    createChart(name: "導覽續讀測試")
    app.buttons["chart.save"].tap()
    XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 5))
    openGuide()
    XCTAssertTrue(app.staticTexts["guide.storage"].label.contains("這台裝置"))
    app.buttons["guide.next"].tap()
    app.buttons["guide.next"].tap()
    assertStep(3)
    app.buttons["guide.skip"].tap()
    app.tabBars.buttons["已儲存"].tap()
    let saved = app.staticTexts["導覽續讀測試"].firstMatch
    XCTAssertTrue(saved.waitForExistence(timeout: 5))
    saved.tap()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    openGuide()
    assertStep(3)
  }

  func test最大動態字級深色與減少動態效果使用可讀線性替代() {
    launch(
      size: "UICTContentSizeCategoryAccessibilityXXXL",
      extra: ["-UITestForceDarkMode", "-UIAccessibilityReduceMotionEnabled", "YES"]
    )
    createChart()
    openGuide()
    assertStep(1)
    XCTAssertTrue(app.descendants(matching: .any)["guide.linearMap"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["guide.squareMap"].exists)
    XCTAssertTrue(app.buttons["guide.next"].isHittable)
    app.buttons["guide.next"].tap()
    assertStep(2)
    app.buttons["guide.next"].tap()
    assertStep(3)
    let opposite = app.descendants(matching: .any)["guide.palace.travel"].firstMatch
    app.scrollToVisibleContent(opposite)
    XCTAssertTrue(opposite.label.contains("對宮"))
    XCTAssertTrue(app.buttons["guide.next"].isHittable)
    app.buttons["guide.next"].tap()
    assertStep(4)
    XCTAssertTrue(app.buttons["guide.skip"].isHittable)
  }

  func test一般字級盤面標示三方四正且每步只有一個主要前進操作() {
    launch()
    createChart()
    openGuide()
    XCTAssertTrue(app.descendants(matching: .any)["guide.squareMap"].exists)
    XCTAssertEqual(app.buttons.matching(identifier: "guide.next").count, 1)
    app.buttons["guide.next"].tap()
    app.buttons["guide.next"].tap()
    assertStep(3)
    for palace in ["life", "travel", "wealth", "career"] {
      XCTAssertTrue(app.staticTexts["guide.palace.\(palace)"].exists)
    }
    XCTAssertEqual(app.buttons.matching(identifier: "guide.next").count, 1)
    XCTAssertFalse(app.buttons["assistant.send"].exists)
  }

  private func launch(size: String = "UICTContentSizeCategoryL", extra: [String] = []) {
    app.launchArguments =
      [
        "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestResetData",
        "-UIPreferredContentSizeCategoryName", size,
      ] + extra
    app.launch()
  }

  private func createChart(name: String? = nil) {
    let create = app.buttons["home.createChart"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    create.tap()
    let generate = app.buttons["birthInput.generate"]
    XCTAssertTrue(app.navigationBars["排一張命盤"].waitForExistence(timeout: 5))
    if let name {
      let field = app.textFields["名稱或暱稱（選填）"]
      field.tap()
      field.typeText("\(name)\n")
    }
    app.scrollToVisibleContent(generate)
    generate.tap()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
  }

  private func openGuide() {
    let guide = app.buttons["chart.readingGuide"]
    app.scrollToVisibleContent(guide)
    guide.tap()
    XCTAssertTrue(app.navigationBars["四步讀盤導覽"].waitForExistence(timeout: 5))
  }

  private func assertStep(_ number: Int, file: StaticString = #filePath, line: UInt = #line) {
    let heading = app.staticTexts["guide.step"]
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label BEGINSWITH %@", "第 \(number) 步"), object: heading
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
  }
}
