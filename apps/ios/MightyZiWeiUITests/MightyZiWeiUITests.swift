import XCTest

@MainActor
final class MightyZiWeiUITests: XCTestCase {
    private var app: XCUIApplication!

    private let localizationArguments = [
        "-AppleLanguages", "(zh-Hant)",
        "-AppleLocale", "zh_TW"
    ]

    override func setUp() async throws {
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
        if !generateButton.waitForExistence(timeout: 5), createButton.exists {
            createButton.tap()
        }
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["你的核心性格"].exists)
        XCTAssertTrue(app.buttons["chart.startExploring"].exists)
        XCTAssertFalse(app.staticTexts["命宮干支"].exists)
        let fiveElementBureau = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "五行局")
        ).firstMatch
        XCTAssertFalse(fiveElementBureau.exists)
        attachScreenshot(name: "命盤")

        let chartData = app.buttons["chart.data"]
        XCTAssertTrue(chartData.waitForExistence(timeout: 5))
        scrollToElement(chartData)
        chartData.tap()
        XCTAssertTrue(fiveElementBureau.waitForExistence(timeout: 5))
        chartData.tap()

        let lifePalaceButton = app.buttons["chart.palace.life"]
        scrollToElement(lifePalaceButton)
        lifePalaceButton.tap()

        XCTAssertTrue(app.navigationBars["命宮"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["你的核心性格"].exists)
        XCTAssertFalse(app.staticTexts["宮位干支"].exists)

        let whyButton = app.buttons["palace.why"]
        XCTAssertTrue(whyButton.waitForExistence(timeout: 5))
        whyButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["palace.why.content"].exists)
        let mainStar = app.staticTexts["palace.star.name.tianLiang"]
        scrollToElement(mainStar)
        XCTAssertTrue(mainStar.exists)

        let otherStars = app.buttons["palace.otherStars"]
        scrollToElement(otherStars)
        otherStars.tap()
        let supportingStar = app.staticTexts["palace.star.name.qingYang"]
        scrollToElement(supportingStar)
        XCTAssertTrue(supportingStar.waitForExistence(timeout: 3))

        let relations = app.buttons["palace.relations"]
        scrollToElement(relations)
        relations.tap()
        let relationExplanation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "三方四正")
        ).firstMatch
        XCTAssertTrue(relationExplanation.waitForExistence(timeout: 3))

        let rawData = app.buttons["palace.data"]
        scrollToElement(rawData)
        rawData.tap()
        XCTAssertEqual(rawData.value as? String, "已展開")
        attachScreenshot(name: "宮位探索")

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
        let configureAIButton = app.buttons["interpretation.configureAI"]
        XCTAssertTrue(configureAIButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)
        configureAIButton.tap()
        XCTAssertTrue(app.navigationBars["AI API 設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ai.endpoint"].exists)
        XCTAssertTrue(app.textFields["ai.model"].exists)
        XCTAssertTrue(app.buttons["ai.test"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))

        for title in ["命盤總覽", "個性", "工作與事業", "財務傾向", "感情與人際"] {
            let heading = app.staticTexts[title]
            scrollToElement(heading)
            XCTAssertTrue(heading.exists)
        }
        attachScreenshot(name: "基本解讀")

        app.tabBars.buttons["AI"].tap()
        XCTAssertTrue(app.navigationBars["命盤 AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant.configureAPI"].waitForExistence(timeout: 5))
    }

    func testAI分頁可針對目前命盤進行多輪問答且不連真實網路() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockAI"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["AI"].waitForExistence(timeout: 5))
        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let generateButton = app.buttons["birthInput.generate"]
        if !generateButton.waitForExistence(timeout: 5), createButton.exists {
            createButton.tap()
        }
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        app.buttons["chart.startExploring"].tap()
        XCTAssertTrue(app.navigationBars["命宮"].waitForExistence(timeout: 5))

        let contextualQuestion = app.buttons["palace.question.0"]
        scrollToElement(contextualQuestion)
        contextualQuestion.tap()

        XCTAssertTrue(app.navigationBars["命盤 AI"].waitForExistence(timeout: 5))
        let composer = app.textFields["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "從命盤來看，你的核心性格可能有什麼特色？")
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["命盤助理"].exists)
        XCTAssertTrue(app.staticTexts["從命盤來看，你的核心性格可能有什麼特色？"].exists)

        composer.tap()
        composer.typeText("可以再說清楚一點嗎？")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.loading"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["停止"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.cancelled"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(composer.value as? String, "可以再說清楚一點嗎？")

        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.otherElements.matching(identifier: "assistant.answer").element(boundBy: 1)
                .waitForExistence(timeout: 5)
        )
    }

    func test語音輸入只填草稿且解讀朗讀可控制() {
        app.terminate()
        XCUIDevice.shared.appearance = .dark
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockAI",
            "-UITestMockSpeech"
        ]
        app.launch()

        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let generateButton = app.buttons["birthInput.generate"]
        if !generateButton.waitForExistence(timeout: 5), createButton.exists {
            createButton.tap()
        }
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        let interpretationButton = app.buttons["chart.interpretation"]
        scrollToElement(interpretationButton)
        interpretationButton.tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))

        let readButton = app.buttons["朗讀"].firstMatch
        scrollToElement(readButton)
        readButton.tap()

        let playbackToggle = app.buttons["暫停"].firstMatch
        XCTAssertTrue(playbackToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(playbackToggle.label, "暫停")
        playbackToggle.tap()
        let resumePlayback = app.buttons["繼續"].firstMatch
        XCTAssertTrue(resumePlayback.waitForExistence(timeout: 5))
        resumePlayback.tap()

        let stopPlayback = app.buttons["停止"].firstMatch
        XCTAssertTrue(stopPlayback.exists)
        stopPlayback.tap()
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))

        let personality = app.buttons["interpretation.category.personality"]
        scrollToElement(personality)
        personality.tap()
        let categoryReadButton = app.buttons.matching(
            NSPredicate(format: "label == %@", "朗讀")
        ).element(boundBy: 1)
        scrollToElement(categoryReadButton)
        categoryReadButton.tap()
        XCTAssertTrue(app.buttons["暫停"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["停止"].firstMatch.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let askAIButton = app.buttons["chart.askAI"]
        scrollToElement(askAIButton)
        askAIButton.tap()
        XCTAssertTrue(app.navigationBars["命盤 AI"].waitForExistence(timeout: 5))

        let microphone = app.buttons["voice.input.toggle"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.tap()

        let composer = app.textFields["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "語音輸入的命盤問題")
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)
        XCTAssertEqual(microphone.label, "停止語音輸入")

        microphone.tap()
        let microphoneStopped = app.buttons["voice.input.toggle"]
        XCTAssertTrue(microphoneStopped.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "語音輸入的命盤問題。")
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)

        app.buttons["assistant.send"].tap()
        let answer = app.otherElements["assistant.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let answerReadButton = app.buttons["朗讀"].firstMatch
        scrollToElement(answerReadButton)
        answerReadButton.tap()
        XCTAssertTrue(app.buttons["暫停"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["停止"].firstMatch.tap()
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
            "UICTContentSizeCategoryAccessibilityXXXL",
            "-UITestMockAI",
            "-UITestMockSpeech"
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
        interpretationButton.tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        let readButton = app.buttons["朗讀"].firstMatch
        scrollToElement(readButton)
        XCTAssertTrue(readButton.isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        attachScreenshot(name: "最大動態字級命盤")

        app.tabBars.buttons["AI"].tap()
        XCTAssertTrue(app.navigationBars["命盤 AI"].waitForExistence(timeout: 5))
        let microphone = app.buttons["voice.input.toggle"]
        scrollToElement(microphone)
        XCTAssertTrue(microphone.isHittable)
    }

    private func scrollToElement(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 10 {
            if element.exists, element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
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
