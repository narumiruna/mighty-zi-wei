import XCTest

@MainActor
final class ObservationUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.appearance = .light
    launch()
  }

  override func tearDown() async throws {
    app.terminate()
    XCUIDevice.shared.appearance = .light
  }

  func test單段確認新增回顧保留初步想法且可獨立刪除() {
    openJournal()
    tap(app.buttons["journal.startObservation"])
    tap(app.buttons["observation.select.seed.overview.baseline"])
    let preview = app.staticTexts["observation.preview"].firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    let originalText = preview.label
    XCTAssertFalse(originalText.isEmpty)
    XCTAssertTrue(app.staticTexts["初步想法"].exists)
    let thought = element("observation.initialThought")
    tap(thought)
    thought.typeText("這是儲存當時的想法")
    tap(app.buttons["observation.save"])
    let observation = element("journal.observation")
    XCTAssertTrue(observation.waitForExistence(timeout: 5))
    tap(observation)
    XCTAssertEqual(app.staticTexts["observation.originalText"].label, originalText)
    XCTAssertEqual(app.staticTexts["observation.originalThought"].firstMatch.label, "這是儲存當時的想法")
    tap(app.buttons["observation.addReview"])
    XCTAssertTrue(app.navigationBars["新增回顧"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["observation.originalThought"].firstMatch.label, "這是儲存當時的想法")
    let content = element("observation.reviewContent")
    tap(content)
    content.typeText("回顧時有不同的觀察")
    tap(app.buttons["observation.saveReview"])
    let review = element("observation.review")
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["回顧時有不同的觀察"].exists)
    XCTAssertTrue(app.staticTexts["尚無法判斷"].exists)
    XCTAssertEqual(app.staticTexts["observation.originalThought"].firstMatch.label, "這是儲存當時的想法")
    review.swipeLeft()
    tap(app.buttons["刪除回顧"].firstMatch)
    tap(app.buttons["刪除回顧"].firstMatch)
    XCTAssertTrue(app.staticTexts["還沒有後續回顧。回顧不會覆寫原始想法。"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["observation.originalText"].label, originalText)
    tap(app.buttons["observation.delete"])
    tap(app.buttons["永久刪除觀察與回顧"])
    XCTAssertTrue(app.buttons["journal.startObservation"].waitForExistence(timeout: 5))
    XCTAssertFalse(element("journal.observation").exists)
  }

  func test取消觀察不寫入資料且暗色最大文字仍可完成() {
    app.terminate()
    XCUIDevice.shared.appearance = .dark
    launch(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    openJournal()
    tap(app.buttons["journal.startObservation"])
    XCTAssertTrue(app.navigationBars["選取一段解讀"].waitForExistence(timeout: 5))
    tap(app.buttons["取消"])
    XCTAssertFalse(element("journal.observation").exists)
    tap(app.buttons["journal.startObservation"])
    tap(app.buttons["observation.select.seed.overview.baseline"])
    XCTAssertTrue(app.buttons["observation.save"].waitForExistence(timeout: 5))
    tap(app.buttons["observation.save"])
    XCTAssertTrue(element("journal.observation").waitForExistence(timeout: 5))
  }

  func test舊同步開關之外必須另行確認觀察且取消不啟用() {
    app.terminate()
    launch(extra: ["-UITestLegacyICloudEnabled", "-UITestMockICloudUnavailable"])
    tap(app.buttons["設定"])
    XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
    let toggle = app.switches["settings.icloud.observations.toggle"]
    scroll(to: toggle)
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    // 同意狀態可能來自先前 UI 測試，先明確關閉，不接觸真實 CloudKit。
    if toggle.value as? String == "1" { tap(toggle) }
    XCTAssertEqual(toggle.value as? String, "0")
    tap(toggle)
    let confirmation = app.alerts["另行同意同步觀察與回顧？"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    XCTAssertTrue(
      confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "原始想法")).firstMatch
        .exists)
    tap(confirmation.buttons["取消"])
    XCTAssertEqual(toggle.value as? String, "0")
    tap(toggle)
    tap(app.alerts.buttons["同意並同步觀察"])
    XCTAssertEqual(toggle.value as? String, "1")
    let disclosure = app.staticTexts["settings.icloud.observations.disclosure"]
    XCTAssertTrue(disclosure.label.contains("已另行同意"))
  }

  private func launch(extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments =
      ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestResetData"] + extra
    app.launch()
  }

  private func openJournal() {
    tap(app.buttons["home.createChart"])
    tap(app.buttons["birthInput.generate"])
    XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    tap(app.buttons["chart.save"])
    XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 5))
    tap(app.buttons["chart.journal"])
    XCTAssertTrue(app.buttons["journal.startObservation"].waitForExistence(timeout: 5))
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func tap(_ element: XCUIElement) {
    scroll(to: element)
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    XCTAssertTrue(element.isHittable)
    if element.elementType == .switch {
      element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    } else {
      element.tap()
    }
  }

  private func scroll(to element: XCUIElement) {
    if element.isHittable {
      let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
      if app.navigationBars.allElementsBoundByIndex.contains(where: { $0.frame.contains(center) })
        || app.alerts.firstMatch.exists || app.sheets.firstMatch.exists
      {
        return
      }
    }
    app.scrollToVisibleContent(element)
  }
}
