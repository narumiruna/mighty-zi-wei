import XCTest

@MainActor
final class MightyZiWeiUITests: XCTestCase {
    private var app: XCUIApplication!

    private let localizationArguments = [
        "-AppleLanguages", "(zh-Hant)",
        "-AppleLocale", "zh_TW"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.terminate()
        app.launch()
    }

    func test主要流程可排盤查看宮位儲存並查看解讀() {
        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        attachScreenshot(name: "首頁")
        createButton.tap()

        let generateButton = app.buttons["birthInput.generate"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
        assert命盤完整顯示在畫面內()
        XCTAssertFalse(app.staticTexts["天梁"].exists)
        let fiveElementBureau = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "五行局")
        ).firstMatch
        XCTAssertFalse(fiveElementBureau.exists)
        attachScreenshot(name: "命盤")

        let chartData = app.buttons["chart.data"]
        XCTAssertTrue(chartData.waitForExistence(timeout: 5))
        chartData.tap()
        XCTAssertTrue(fiveElementBureau.waitForExistence(timeout: 3))
        chartData.tap()

        let lifePalaceButton = app.buttons["chart.palace.life"]
        XCTAssertTrue(lifePalaceButton.isHittable)
        lifePalaceButton.tap()

        XCTAssertTrue(app.navigationBars["命宮"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["天梁"].exists)
        XCTAssertFalse(app.staticTexts["擎羊"].exists)

        let otherStars = app.descendants(matching: .any)["palace.otherStars"]
        XCTAssertTrue(otherStars.waitForExistence(timeout: 5))
        otherStars.tap()
        XCTAssertTrue(app.staticTexts["擎羊"].waitForExistence(timeout: 3))
        attachScreenshot(name: "宮位詳情")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

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
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()

        app.buttons["home.createChart"].tap()
        app.buttons["birthInput.generate"].tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        let lifePalaceButton = app.buttons["chart.palace.life"]
        XCTAssertTrue(lifePalaceButton.waitForExistence(timeout: 5))
        XCTAssertTrue(lifePalaceButton.label.contains("命宮"))
        XCTAssertFalse(lifePalaceButton.label.contains("星曜"))
        attachScreenshot(name: "深色模式命盤")
    }

    func test最大動態字級仍可瀏覽命盤與主要操作() {
        app.terminate()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        XCTAssertTrue(createButton.isHittable)
        createButton.tap()

        let generateButton = app.buttons["birthInput.generate"]
        scrollToElement(generateButton)
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
        let parentsPalaceButton = app.buttons["chart.palace.parents"]
        scrollToElement(parentsPalaceButton)
        parentsPalaceButton.tap()
        XCTAssertTrue(app.navigationBars["父母宮"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let interpretationButton = app.buttons["chart.interpretation"]
        scrollToElement(interpretationButton)
        XCTAssertTrue(interpretationButton.isHittable)
        attachScreenshot(name: "最大動態字級命盤")
    }

    private func assert命盤完整顯示在畫面內() {
        let palaceButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "chart.palace.")
        )
        XCTAssertEqual(palaceButtons.count, 12)

        let visibleFrame = app.frame.insetBy(dx: -1, dy: -1)
        for index in 0..<palaceButtons.count {
            let palaceFrame = palaceButtons.element(boundBy: index).frame
            XCTAssertTrue(
                visibleFrame.contains(palaceFrame),
                "第 \(index + 1) 個宮位超出初始畫面：\(palaceFrame)"
            )
        }
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
