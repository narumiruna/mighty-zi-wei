import XCTest

@MainActor
protocol ChartWorkflowUITest: AnyObject {
  var app: XCUIApplication! { get set }
}

extension ChartWorkflowUITest {
  var localizationArguments: [String] {
    ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestResetData"]
  }

  func relaunchMockAI(extraArguments: [String] = []) {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments =
      localizationArguments + [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL", "-UITestMockAI",
      ] + extraArguments
    app.launch()
  }

  func createDefaultChart(name: String? = nil) {
    let generateButton = openBirthInput()
    if let name {
      let nameField = app.textFields["名稱或暱稱（選填）"]
      XCTAssertTrue(nameField.waitForExistence(timeout: 3))
      nameField.tap()
      nameField.typeText("\(name)\n")
    }
    scrollToElement(generateButton)
    XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
    let overview = app.staticTexts["命盤總覽"]
    generateButton.tap()
    if !overview.waitForExistence(timeout: 5), generateButton.exists {
      generateButton.tap()
    }
    XCTAssertTrue(overview.waitForExistence(timeout: 5))
  }

  func openBirthInput() -> XCUIElement {
    let create = app.buttons["home.createChart"]
    let generate = app.buttons["birthInput.generate"]
    let destination = app.navigationBars["排一張命盤"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    create.tap()
    if !destination.waitForExistence(timeout: 5), create.isHittable {
      create.tap()
    }
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
    // 最大字級的 Form 會延後建立畫面外的主要操作，留待捲動後驗證。
    return generate
  }

  func openInterpretation() {
    let interpretation = app.buttons["chart.interpretation"]
    let destination = app.navigationBars["命盤解讀"]
    scrollToElement(interpretation)
    interpretation.tap()
    if !destination.waitForExistence(timeout: 5), interpretation.exists {
      interpretation.tap()
    }
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
  }

  func presentInterpretationPreview(organizeButton: XCUIElement) {
    let preview = app.navigationBars["確認 AI 整理"]
    organizeButton.tap()
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
  }

  func startInterpretationOrganization(organizeButton: XCUIElement) {
    presentInterpretationPreview(organizeButton: organizeButton)
    let confirm = app.buttons["interpretation.confirmOrganize"]
    let loading = app.staticTexts["雲端模型正在整理，完成驗證前不會顯示內容。"]
    confirm.tap()
    XCTAssertTrue(loading.waitForExistence(timeout: 5))
  }

  func interpretationSourceLabel(_ title: String) -> XCUIElement {
    app.staticTexts.matching(
      NSPredicate(
        format: "identifier == %@ AND label CONTAINS %@", "interpretation.source.current", title)
    ).firstMatch
  }

  func waitForLabel(_ element: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
    wait(for: element, predicate: NSPredicate(format: "label == %@", label), timeout: timeout)
  }

  func waitForLabelContaining(_ element: XCUIElement, text: String, timeout: TimeInterval) -> Bool {
    wait(for: element, predicate: NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
  }

  func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    wait(for: element, predicate: NSPredicate(format: "exists == false"), timeout: timeout)
  }

  private func wait(
    for element: XCUIElement, predicate: NSPredicate, timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  func scrollToElement(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    app.scrollToVisibleContent(element, file: file, line: line)
  }

  func assertVisibleInContentViewport(
    _ element: XCUIElement, navigationTitle: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    app.assertVisibleInContentViewport(
      element, navigationTitle: navigationTitle, file: file, line: line)
  }
}
