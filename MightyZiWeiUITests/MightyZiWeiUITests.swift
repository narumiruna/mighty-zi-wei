import XCTest

@MainActor
final class MightyZiWeiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
    }

    func test主要流程可排盤儲存並查看解讀() {
        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        let generateButton = app.buttons["birthInput.generate"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["十二宮"].waitForExistence(timeout: 5))
        attachScreenshot(name: "命盤")

        let saveButton = app.buttons["chart.save"]
        XCTAssertTrue(saveButton.exists)
        saveButton.tap()
        XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))

        let interpretationButton = app.buttons["chart.interpretation"]
        scrollToElement(interpretationButton)
        interpretationButton.tap()

        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        for title in ["命盤總覽", "個性", "工作與事業", "財務傾向", "感情與人際"] {
            let heading = app.staticTexts[title]
            scrollToElement(heading)
            XCTAssertTrue(heading.exists)
        }
        attachScreenshot(name: "基本解讀")
    }

    func test深色模式與宮位無障礙標籤() {
        app.terminate()
        XCUIDevice.shared.appearance = .dark
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()

        app.buttons["home.createChart"].tap()
        app.buttons["birthInput.generate"].tap()
        XCTAssertTrue(app.staticTexts["十二宮"].waitForExistence(timeout: 5))

        let palaceButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "命宮")
        ).firstMatch
        XCTAssertTrue(palaceButton.waitForExistence(timeout: 5))
        XCTAssertTrue(palaceButton.label.contains("星曜"))
        attachScreenshot(name: "深色模式命盤")
    }

    func test最大動態字級仍顯示主要操作() {
        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        XCTAssertTrue(createButton.isHittable)
        createButton.tap()
        XCTAssertTrue(app.buttons["birthInput.generate"].waitForExistence(timeout: 5))
        attachScreenshot(name: "最大動態字級輸入畫面")
    }

    private func scrollToElement(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
