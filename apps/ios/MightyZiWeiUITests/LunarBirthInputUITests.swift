import XCTest

@MainActor
final class LunarBirthInputUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestResetData",
    ]
    app.launch()
    openBirthInput()
  }

  func testInvalidLunarDraftSurvivesErrorsAndModeSwitches() {
    selectMode("農曆")
    fillLunarDate(year: "2023", month: "2", day: "30", leap: true)
    tapPrimary()
    let error = app.descendants(matching: .any)["birthInput.error"].firstMatch
    XCTAssertTrue(error.waitForExistence(timeout: 3))
    XCTAssertTrue(error.label.contains("小月沒有三十日"))
    XCTAssertFalse(app.navigationBars["確認農曆轉換"].exists)
    selectMode("公曆")
    XCTAssertTrue(app.datePickers["birthInput.gregorian.date"].exists)
    selectMode("農曆")
    XCTAssertEqual(app.textFields["birthInput.lunar.year"].value as? String, "2023")
    XCTAssertEqual(app.textFields["birthInput.lunar.day"].value as? String, "30")
    XCTAssertEqual(app.switches["birthInput.lunar.leapMonth"].value as? String, "1")
  }

  func testUnavailableLeapMonthIsExplicitlyRejectedAndPreserved() {
    selectMode("農曆")
    fillLunarDate(year: "2024", month: "2", day: "1", leap: true)
    tapPrimary()
    let error = app.descendants(matching: .any)["birthInput.error"].firstMatch
    XCTAssertTrue(error.waitForExistence(timeout: 3))
    XCTAssertTrue(error.label.contains("沒有你指定的閏月"))
    XCTAssertFalse(app.staticTexts["命盤總覽"].exists)
    scrollToBirthTop()
    let year = app.textFields["birthInput.lunar.year"]
    app.scrollToVisibleContent(year)
    XCTAssertEqual(year.value as? String, "2024")
  }

  func testConversionRequiresConfirmationAndCancelKeepsTheDraft() {
    selectMode("農曆")
    fillLunarDate(year: "2024", month: "1", day: "1")
    tapPrimary()
    assertConfirmation(date: "2024/02/10")
    XCTAssertFalse(app.staticTexts["命盤總覽"].exists)
    app.buttons["birthInput.lunar.cancel"].tap()
    XCTAssertTrue(app.navigationBars["排一張命盤"].waitForExistence(timeout: 3))
    scrollToBirthTop()
    let year = app.textFields["birthInput.lunar.year"]
    app.scrollToVisibleContent(year)
    XCTAssertEqual(year.value as? String, "2024")
    tapPrimary()
    assertConfirmation(date: "2024/02/10")
    confirmConversion()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
  }

  func testAdjacentHourComparisonAlsoRequiresTheConvertedDateConfirmation() {
    selectMode("農曆")
    fillLunarDate(year: "2023", month: "2", day: "1", leap: true)
    let compare = app.buttons["birthInput.compareHours"]
    app.scrollToVisibleContent(compare)
    compare.tap()
    assertConfirmation(date: "2023/03/22")
    XCTAssertFalse(app.navigationBars["時辰比較"].exists)
    confirmConversion()
    XCTAssertTrue(app.navigationBars["時辰比較"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["目前輸入"].exists)
  }

  func testEnglishDeviceLocaleStillShowsAbsoluteLunarYearAndCivilDate() {
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestResetData"]
    app.launch()
    openBirthInput()
    selectMode("農曆")
    fillLunarDate(year: "2024", month: "1", day: "1")
    tapPrimary()
    assertConfirmation(date: "2024/02/10")
    let input = app.staticTexts["birthInput.lunar.confirmation.input"]
    XCTAssertTrue(input.label.contains("2024 年"))
    XCTAssertFalse(app.staticTexts["命盤總覽"].exists)
  }

  func testLunarAndGregorianEntriesUseTheExistingDuplicateChartPolicy() {
    tapPrimary()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    app.buttons["chart.save"].tap()
    XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    selectMode("農曆")
    fillLunarDate(year: "1989", month: "12", day: "5")
    tapPrimary()
    assertConfirmation(date: "1990/01/01")
    confirmConversion()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    app.buttons["chart.save"].tap()
    XCTAssertTrue(app.staticTexts["已有相同出生資料的命盤"].waitForExistence(timeout: 3))
  }

  private func openBirthInput() {
    let create = app.buttons["home.createChart"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    create.tap()
    XCTAssertTrue(app.buttons["birthInput.generate"].waitForExistence(timeout: 5))
  }

  private func scrollToBirthTop() {
    for _ in 0..<6 {
      if app.segmentedControls["birthInput.mode"].isHittable { return }
      app.swipeDown()
    }
  }

  private func selectMode(_ title: String) {
    scrollToBirthTop()
    let mode = app.segmentedControls["birthInput.mode"]
    app.scrollToVisibleContent(mode)
    mode.buttons[title].tap()
  }

  private func fillLunarDate(year: String, month: String, day: String, leap: Bool = false) {
    replaceText("birthInput.lunar.year", with: year)
    replaceText("birthInput.lunar.month", with: month)
    replaceText("birthInput.lunar.day", with: day)
    let toggle = app.switches["birthInput.lunar.leapMonth"]
    app.scrollToVisibleContent(toggle)
    if (toggle.value as? String == "1") != leap {
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
    XCTAssertEqual(toggle.value as? String, leap ? "1" : "0")
  }

  private func replaceText(_ identifier: String, with text: String) {
    let field = app.textFields[identifier]
    app.scrollToVisibleContent(field)
    field.tap()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(text)
    XCTAssertEqual(field.value as? String, text)
    let done = app.buttons["birthInput.lunar.done"]
    if done.waitForExistence(timeout: 2) { done.tap() }
  }

  private func tapPrimary() {
    let primary = app.buttons["birthInput.generate"]
    app.scrollToVisibleContent(primary)
    primary.tap()
  }

  private func assertConfirmation(date: String) {
    XCTAssertTrue(app.navigationBars["確認農曆轉換"].waitForExistence(timeout: 3))
    let summary = app.descendants(matching: .any)["birthInput.localTimeCheck"].firstMatch
    XCTAssertTrue(summary.waitForExistence(timeout: 3))
    XCTAssertTrue(summary.label.contains(date), summary.label)
    XCTAssertTrue(summary.label.contains("12:00"), summary.label)
    XCTAssertTrue(summary.label.contains("Asia/Taipei"), summary.label)
  }

  private func confirmConversion() {
    let confirm = app.buttons["birthInput.lunar.confirm"]
    app.scrollToVisibleContent(confirm)
    confirm.tap()
  }
}
