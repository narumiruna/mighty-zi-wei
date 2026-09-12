import XCTest

@MainActor
final class InterpretationSourceUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func test未設定API仍可主動展開本機來源且預設不顯示來源卡() {
    launch()
    createChart()
    openInterpretation()
    XCTAssertFalse(app.buttons["本段引用依據與來源"].exists)
    XCTAssertFalse(app.navigationBars["解讀來源"].exists)
    openSources()
    XCTAssertTrue(app.staticTexts["本機資料可離線閱讀"].exists)
    XCTAssertTrue(app.staticTexts["解讀內容版本：1"].exists)
    XCTAssertTrue(app.staticTexts["專家審閱：待審"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["現行產品規則，非專家認證"].firstMatch.exists)
    XCTAssertFalse(app.staticTexts["sources.aiLimitation"].exists)

    let details = app.buttons["規則與來源定位"].firstMatch
    app.scrollToVisibleContent(details)
    details.tap()
    let sourcePath = app.staticTexts[
      "apps/ios/MightyZiWei/Interpretation/InterpretationSeedBuilder.swift"
    ].firstMatch
    app.scrollToVisibleContent(sourcePath)
    XCTAssertTrue(sourcePath.exists)
    XCTAssertFalse(app.buttons["停止"].exists)
  }

  func testAI整理來源標為段落引用而非逐句驗證() {
    launch(extra: ["-UITestMockAI"])
    createChart()
    openInterpretation()
    let organize = app.buttons["interpretation.organizeWithAI"]
    XCTAssertTrue(organize.waitForExistence(timeout: 5))
    organize.tap()
    let confirm = app.buttons["interpretation.confirmOrganize"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.staticTexts["已確認回傳格式、內容安全與引用的命盤依據。"].waitForExistence(timeout: 8))
    openSources()
    let limitation = app.staticTexts["sources.aiLimitation"]
    XCTAssertTrue(limitation.waitForExistence(timeout: 5))
    XCTAssertTrue(limitation.label.contains("不能保證每句語意"))
    XCTAssertFalse(app.staticTexts["逐句驗證通過"].exists)
    XCTAssertFalse(app.buttons["停止"].exists)
  }

  func test問答依據使用同一來源卡且展開不會開始另一個請求() {
    launch(extra: ["-UITestMockAI"])
    createChart()
    let assistant = app.buttons["chart.askAI"]
    app.scrollToVisibleContent(assistant)
    assistant.tap()
    let composer = app.textFields["assistant.composer"]
    XCTAssertTrue(composer.waitForExistence(timeout: 5))
    composer.tap()
    composer.typeText("有哪些可以自我觀察的傾向？")
    if app.keyboards.firstMatch.exists { app.typeKey(.escape, modifierFlags: []) }
    let send = app.buttons["assistant.send"]
    app.scrollToVisibleContent(send)
    send.tap()
    XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["本段引用依據與來源"].exists)
    let evidence = app.buttons["為什麼這樣說"].firstMatch
    app.scrollToVisibleContent(evidence)
    evidence.tap()
    let sources = app.buttons["本段引用依據與來源"].firstMatch
    app.scrollToVisibleContent(sources)
    sources.tap()
    XCTAssertTrue(app.navigationBars["解讀來源"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["sources.aiLimitation"].exists)
    XCTAssertFalse(app.buttons["assistant.stop"].exists)
  }

  func test無版本收藏可以閱讀來源限制返回並刪除() {
    launch()
    createChart()
    app.buttons["chart.save"].tap()
    XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 5))
    openInterpretation()
    let bookmark = app.buttons["收藏"].firstMatch
    app.scrollToVisibleContent(bookmark)
    bookmark.tap()
    XCTAssertTrue(app.buttons["已收藏"].firstMatch.waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    let journal = app.buttons["chart.journal"]
    app.scrollToVisibleContent(journal)
    journal.tap()
    let row = app.buttons["journal.bookmark"].firstMatch
    app.scrollToVisibleContent(row)
    row.tap()
    let content = app.staticTexts["journal.bookmarkDetail.content"]
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    XCTAssertFalse(content.label.isEmpty)
    let sources = app.buttons["journal.bookmarkDetail.sources"]
    app.scrollToVisibleContent(sources)
    sources.tap()
    XCTAssertTrue(app.navigationBars["解讀來源"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["sources.versionLimitation"].label.contains("來源版本未保存"))
    XCTAssertFalse(app.staticTexts["專家審閱：待審"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.scrollToVisibleContent(row)
    row.swipeLeft()
    app.buttons["刪除"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["在命盤解讀或 AI 回答點選「收藏」後，會顯示在這裡。"].waitForExistence(timeout: 5)
    )
  }

  private func launch(extra: [String] = []) {
    app.launchArguments =
      [
        "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestResetData",
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
      ] + extra
    app.launch()
  }

  private func createChart() {
    let create = app.buttons["home.createChart"]
    XCTAssertTrue(create.waitForExistence(timeout: 5))
    create.tap()
    let generate = app.buttons["birthInput.generate"]
    XCTAssertTrue(generate.waitForExistence(timeout: 5))
    app.scrollToVisibleContent(generate)
    generate.tap()
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
  }

  private func openInterpretation() {
    let interpretation = app.buttons["chart.interpretation"]
    app.scrollToVisibleContent(interpretation)
    interpretation.tap()
    XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
  }

  private func openSources() {
    let evidence = app.buttons["查看完整判讀依據"].firstMatch
    app.scrollToVisibleContent(evidence)
    evidence.tap()
    let sources = app.buttons["本段引用依據與來源"].firstMatch
    XCTAssertTrue(sources.waitForExistence(timeout: 3))
    app.scrollToVisibleContent(sources)
    sources.tap()
    XCTAssertTrue(app.navigationBars["解讀來源"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["本段引用依據"].exists)
  }
}
