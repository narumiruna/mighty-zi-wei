import XCTest

@MainActor
final class MightyZiWeiUITests: XCTestCase {
    private var app: XCUIApplication!

    private let localizationArguments = [
        "-AppleLanguages", "(zh-Hant)",
        "-AppleLocale", "zh_TW",
        "-UITestResetData"
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
        let compareHours = app.buttons["birthInput.compareHours"]
        XCTAssertTrue(compareHours.exists)
        compareHours.tap()
        XCTAssertTrue(app.navigationBars["時辰比較"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["目前輸入"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
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

        let journalButton = app.buttons["chart.journal"]
        scrollToElement(journalButton)
        journalButton.tap()
        XCTAssertTrue(app.buttons["journal.addNote"].waitForExistence(timeout: 5))
        app.buttons["journal.addNote"].tap()
        let noteContent = app.textFields["journal.noteContent"]
        XCTAssertTrue(noteContent.waitForExistence(timeout: 5))
        noteContent.tap()
        noteContent.typeText("之後再觀察這個傾向")
        app.buttons["journal.saveNote"].tap()
        XCTAssertTrue(app.staticTexts["之後再觀察這個傾向"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let shareButton = app.buttons["chart.share"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
        shareButton.tap()
        XCTAssertTrue(app.navigationBars["隱私分享"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["包含名稱"].value as? String, "0")
        XCTAssertEqual(app.switches["包含完整出生資料"].value as? String, "0")
        app.buttons["關閉"].tap()

        let interpretationButton = app.buttons["chart.interpretation"]
        scrollToElement(interpretationButton)
        interpretationButton.tap()

        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        let configureAIButton = app.buttons["設定 AI API"]
        XCTAssertTrue(configureAIButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)
        let bookmark = app.buttons["收藏"].firstMatch
        scrollToElement(bookmark)
        bookmark.tap()
        XCTAssertTrue(app.buttons["已收藏"].firstMatch.waitForExistence(timeout: 3))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
        scrollToElement(journalButton)
        journalButton.tap()
        let savedBookmark = app.descendants(matching: .any)["journal.bookmark"].firstMatch
        XCTAssertTrue(savedBookmark.waitForExistence(timeout: 5))
        savedBookmark.tap()
        XCTAssertTrue(app.navigationBars["收藏內容"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["journal.bookmarkDetail.content"]
                .waitForExistence(timeout: 5)
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        scrollToElement(interpretationButton)
        interpretationButton.tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        scrollToElement(configureAIButton)
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

        app.tabBars.buttons["問命盤"].tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.tabBars.buttons["問命盤"].waitForExistence(timeout: 5))
        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let generateButton = app.buttons["birthInput.generate"]
        if !generateButton.waitForExistence(timeout: 5), createButton.exists {
            createButton.tap()
        }
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        scrollToElement(generateButton)
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        app.buttons["chart.startExploring"].tap()
        XCTAssertTrue(app.navigationBars["命宮"].waitForExistence(timeout: 5))

        let contextualQuestion = app.buttons["palace.question.0"]
        scrollToElement(contextualQuestion)
        contextualQuestion.tap()

        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
        let composer = app.textFields["assistant.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "關於你的核心性格，我有哪些值得自我觀察的傾向？")
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)
        app.buttons["assistant.send"].tap()

        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["命盤助理"].exists)
        XCTAssertTrue(app.staticTexts["關於你的核心性格，我有哪些值得自我觀察的傾向？"].exists)

        composer.tap()
        composer.typeText("可以再說清楚一點嗎？")
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.loading"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["assistant.stop"].tap()
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
            "-UITestMockSpeech",
            "-UITestForceDarkMode"
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

        let personality = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "interpretation.category.personality",
                "個性"
            )
        ).firstMatch
        scrollToElement(personality)
        personality.tap()
        let categoryReadButton = app.buttons.matching(
            NSPredicate(format: "label == %@", "朗讀")
        ).element(boundBy: 1)
        scrollToElement(categoryReadButton)
        categoryReadButton.tap()
        let categoryPauseButton = app.buttons["暫停"].firstMatch
        XCTAssertTrue(categoryPauseButton.waitForExistence(timeout: 5))
        scrollToElement(personality)
        personality.tap()
        let collapsedPauseButton = app.buttons["暫停"].firstMatch
        let collapsedStopButton = app.buttons["停止"].firstMatch
        XCTAssertTrue(collapsedPauseButton.waitForExistence(timeout: 5))
        XCTAssertTrue(collapsedStopButton.waitForExistence(timeout: 5))
        collapsedStopButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let askAIButton = app.buttons["chart.askAI"]
        scrollToElement(askAIButton)
        askAIButton.tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))

        let microphone = app.buttons["voice.input.toggle"]
        let composer = app.textFields["assistant.composer"]
        let sendButton = app.buttons["assistant.send"]
        let suggestion = app.buttons["assistant.suggestion.0"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        microphone.tap()

        XCTAssertTrue(["取消語音輸入", "停止語音輸入"].contains(microphone.label))
        if microphone.label == "取消語音輸入" {
            XCTAssertEqual(microphone.value as? String, "正在準備語音辨識")
        }
        XCTAssertFalse(composer.isEnabled)
        XCTAssertFalse(suggestion.isEnabled)
        XCTAssertTrue(waitForLabel(microphone, label: "停止語音輸入", timeout: 5))
        XCTAssertEqual(microphone.value as? String, "正在收音")
        XCTAssertEqual(composer.value as? String, "語音輸入的命盤問題")
        XCTAssertFalse(composer.isEnabled)
        XCTAssertFalse(sendButton.isEnabled)
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)

        microphone.tap()
        XCTAssertTrue(waitForLabel(microphone, label: "開始語音輸入", timeout: 5))
        XCTAssertTrue(composer.isEnabled)
        XCTAssertEqual(composer.value as? String, "語音輸入的命盤問題。")
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)

        sendButton.tap()
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
            "UICTContentSizeCategoryL",
            "-UITestForceDarkMode"
        ]
        app.launch()

        app.buttons["home.createChart"].tap()
        let generateButton = app.buttons["birthInput.generate"]
        scrollToElement(generateButton)
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        let lifePalaceButton = app.buttons["chart.palace.life"]
        XCTAssertTrue(lifePalaceButton.waitForExistence(timeout: 5))
        XCTAssertTrue(lifePalaceButton.label.contains("命宮"))
        XCTAssertTrue(lifePalaceButton.label.contains("宮位干支"))
        XCTAssertTrue(lifePalaceButton.label.contains("主星"))
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

        app.tabBars.buttons["問命盤"].tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
        let microphone = app.buttons["voice.input.toggle"]
        scrollToElement(microphone)
        XCTAssertTrue(microphone.isHittable)
        attachScreenshot(name: "最大動態字級命盤助理")
    }

    func test實用功能的出生檢查個資揭露與本機對話保存() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockAI"
        ]
        app.launch()

        let createChart = app.buttons["home.createChart"]
        XCTAssertTrue(createChart.waitForExistence(timeout: 5))
        createChart.tap()
        let auditCard = app.buttons["birthInput.auditCard"]
        if !auditCard.waitForExistence(timeout: 5), createChart.exists {
            createChart.tap()
        }
        XCTAssertTrue(auditCard.waitForExistence(timeout: 5))
        scrollToElement(auditCard)
        auditCard.tap()
        let timeZoneLabel = app.staticTexts["IANA 時區"]
        if !timeZoneLabel.waitForExistence(timeout: 3) {
            auditCard.tap()
        }
        XCTAssertTrue(timeZoneLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["時辰與換日"].exists)
        XCTAssertTrue(app.staticTexts["規則集"].exists)

        let generateButton = app.buttons["birthInput.generate"]
        scrollToElement(generateButton)
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
        app.buttons["chart.save"].tap()
        XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))

        app.buttons["chart.share"].tap()
        XCTAssertTrue(app.navigationBars["隱私分享"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share.confirm"].waitForExistence(timeout: 3))
        app.buttons["關閉"].tap()

        let askAI = app.buttons["chart.askAI"]
        scrollToElement(askAI)
        askAI.tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "會直接傳送到你設定的第三方 API")
        ).firstMatch.exists)
        app.buttons["assistant.suggestion.0"].tap()
        startQuestionRequest()
        XCTAssertFalse(app.navigationBars["確認傳送內容"].exists)
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForNonExistence(app.keyboards.firstMatch, timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["assistant.saveStatus"].exists)

        let saveConversation = app.buttons["assistant.saveConversation"]
        scrollToElement(saveConversation)
        saveConversation.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.saveConfirmation"]
                .waitForExistence(timeout: 3)
        )

        let composer = app.textFields["assistant.composer"]
        composer.tap()
        composer.typeText("可以再說清楚一點嗎？")
        tapSendQuestion()
        XCTAssertFalse(app.navigationBars["確認傳送內容"].exists)
        XCTAssertTrue(
            app.staticTexts
                .matching(identifier: "assistant.answer.verified")
                .element(boundBy: 1)
                .waitForExistence(timeout: 7)
        )
        let updateConversation = app.buttons["assistant.saveConversation"]
        scrollToElement(updateConversation)
        updateConversation.tap()
        let updateConfirmation = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "assistant.saveConfirmation", "已保存目前 2 輪")
        ).firstMatch
        XCTAssertTrue(updateConfirmation.waitForExistence(timeout: 3))

        app.buttons["assistant.savedConversations"].tap()
        XCTAssertTrue(app.navigationBars["已保存對話"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells.count, 1)
        XCTAssertTrue(app.staticTexts["ui-test-model・2 輪"].waitForExistence(timeout: 3))
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["對話內容"].waitForExistence(timeout: 5))
        let confirmExport = app.buttons["conversation.confirmExport"]
        XCTAssertTrue(confirmExport.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["conversation.export"].exists)
        confirmExport.tap()
        XCTAssertTrue(app.staticTexts["確認匯出個人資料"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "命盤名稱、出生日期與時間、模型與完整問答"
        )).firstMatch.exists)
        app.buttons["我已確認，顯示匯出按鈕"].tap()
        XCTAssertTrue(app.buttons["conversation.export"].waitForExistence(timeout: 3))
    }

    func test問命盤空狀態與第一屏提供清楚主要任務() {
        relaunchMockAI(extraArguments: [
            "-UIAccessibilityDarkerSystemColorsEnabled",
            "YES"
        ])
        app.tabBars.buttons["問命盤"].tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["還沒有可以詢問的命盤"].exists)
        XCTAssertTrue(app.buttons["assistant.createChart"].isHittable)

        app.tabBars.buttons["首頁"].tap()
        createDefaultChart()
        openChartAssistant()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.chartSelector"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.capabilities"].exists
        )
        XCTAssertTrue(app.staticTexts["輸入或選擇一個問題後即可送出。"].exists)
        XCTAssertFalse(app.buttons["assistant.send"].isEnabled)
        attachScreenshot(name: "命盤助理第一屏高對比")
    }

    func test命盤助理第一屏與回答通過系統無障礙稽核() throws {
        relaunchMockAI()
        createDefaultChart()
        openChartAssistant()

        let auditTypes: XCUIAccessibilityAuditType = [
            .contrast,
            .elementDetection,
            .sufficientElementDescription,
            .trait
        ]
        let knownOccludedContrastIssue: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            // XCTest 會把不可操作、畫面外與空白輸入框元素誤報為對比問題。
            guard issue.auditType == .contrast, let element = issue.element else {
                return false
            }
            if !element.isEnabled
                || element.elementType == .textField
                || element.label == "你的問題" {
                return true
            }
            let navigationBottom = self.app.navigationBars["命盤助理"].frame.maxY
            let tabBarTop = self.app.tabBars.firstMatch.frame.minY
            return element.frame.minY < navigationBottom || element.frame.maxY > tabBarTop
        }
        try app.performAccessibilityAudit(
            for: auditTypes,
            knownOccludedContrastIssue
        )

        app.buttons["assistant.suggestion.0"].tap()
        startQuestionRequest()
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(
            for: auditTypes,
            knownOccludedContrastIssue
        )
    }

    func test送出問題不會顯示額外確認頁面() {
        relaunchMockAI()
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        startQuestionRequest()

        XCTAssertFalse(app.navigationBars["確認傳送內容"].exists)
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 10))
    }

    func test只有草稿時切換命盤會先確認且取消不清除內容() {
        relaunchMockAI()
        createDefaultChart(name: "第一張")
        app.buttons["chart.save"].tap()
        XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        createDefaultChart(name: "第二張")
        app.buttons["chart.save"].tap()
        XCTAssertTrue(app.staticTexts["已有相同出生資料的命盤"].waitForExistence(timeout: 3))
        app.buttons["仍要儲存另一張"].tap()
        XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        let composer = app.textFields["assistant.composer"]
        let draft = composer.value as? String
        app.buttons["assistant.chartSelector"].tap()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "第一張")
        ).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["切換命盤並開始新對話？"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        XCTAssertEqual(composer.value as? String, draft)

        app.buttons["assistant.chartSelector"].tap()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "第一張")
        ).firstMatch.tap()
        app.buttons["不保存，直接切換"].tap()
        XCTAssertEqual(composer.value as? String, "尚未輸入")
        XCTAssertTrue(app.buttons["assistant.chartSelector"].label.contains("第一張"))
    }

    func test刪除目前保存副本後會恢復為未保存狀態() {
        relaunchMockAI()
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        startQuestionRequest()
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 10))
        let saveConversation = app.buttons["assistant.saveConversation"]
        scrollToElement(saveConversation)
        saveConversation.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.saveConfirmation"]
                .waitForExistence(timeout: 3)
        )

        app.buttons["assistant.savedConversations"].tap()
        XCTAssertTrue(app.navigationBars["已保存對話"].waitForExistence(timeout: 5))
        app.cells.firstMatch.swipeLeft()
        app.buttons["刪除"].tap()
        XCTAssertTrue(app.staticTexts["尚未保存對話"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let unsavedStatus = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "assistant.saveStatus",
                "本次對話尚未保存"
            )
        ).firstMatch
        XCTAssertTrue(unsavedStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant.saveConversation"].exists)
        XCTAssertTrue(app.otherElements["assistant.answer"].exists)
    }

    func test清除未保存對話會先確認且取消時保留內容() {
        relaunchMockAI()
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        startQuestionRequest()
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 10))

        app.buttons["其他對話操作"].tap()
        app.buttons["清除目前對話"].tap()
        XCTAssertTrue(app.staticTexts["開始新對話？"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.otherElements["assistant.answer"].exists)

        app.buttons["其他對話操作"].tap()
        app.buttons["清除目前對話"].tap()
        app.buttons["不保存，開始新對話"].tap()
        XCTAssertFalse(app.otherElements["assistant.answer"].exists)
        XCTAssertEqual(app.textFields["assistant.composer"].value as? String, "尚未輸入")
        XCTAssertTrue(app.buttons["assistant.suggestion.0"].exists)
    }

    func test問答切換底部分頁後會繼續並顯示完成回答() {
        relaunchMockAI()
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.loading"]
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["首頁"].tap()
        XCTAssertTrue(app.buttons["chart.askAI"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 4)
        app.tabBars.buttons["問命盤"].tap()

        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["assistant.answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.answer.verified"].exists
        )
    }

    func test不支援問題會提供改問方向且只填入追問草稿() {
        relaunchMockAI(extraArguments: ["-UITestMockAIUnsupported"])
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        app.buttons["assistant.send"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.answer.unsupported"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["assistant.answer.verified"].exists
        )
        attachScreenshot(name: "命盤助理不支援狀態")

        let followUp = app.buttons["我的個性有哪些值得留意的地方？"]
        scrollToElement(followUp)
        followUp.tap()
        XCTAssertEqual(
            app.textFields["assistant.composer"].value as? String,
            "我的個性有哪些值得留意的地方？"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.answer.unsupported"].exists
        )
    }

    func test回答失敗與停止都保留問題並提供恢復路徑() {
        relaunchMockAI(extraArguments: ["-UITestMockAIFailure"])
        createDefaultChart()
        openChartAssistant()

        app.buttons["assistant.suggestion.0"].tap()
        let composer = app.textFields["assistant.composer"]
        let question = composer.value as? String
        startQuestionRequest()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.error"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertEqual(composer.value as? String, question)
        XCTAssertTrue(app.buttons["重新確認並送出"].exists)

        relaunchMockAI(extraArguments: ["-UITestMockAISlow"])
        createDefaultChart()
        openChartAssistant()
        app.buttons["assistant.suggestion.0"].tap()
        let retryQuestion = app.textFields["assistant.composer"].value as? String
        startQuestionRequest()
        app.buttons["assistant.stop"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["assistant.cancelled"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(app.textFields["assistant.composer"].value as? String, retryQuestion)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "仍可能產生費用")
        ).firstMatch.exists)
    }

    func test解讀第一屏顯示版本且AI整理可返回停止與完成() {
        relaunchMockAI()
        createDefaultChart()
        let interpretation = app.buttons["chart.interpretation"]
        scrollToElement(interpretation)
        interpretation.tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["interpretation.source"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)

        let organize = app.buttons["用 AI 整理文字"]
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.tap()
        XCTAssertTrue(app.navigationBars["確認 AI 整理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "這是模型指示，App 無法保證 AI 不會改變語意")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["完成回傳格式、內容安全與引用依據檢查後才會顯示"].exists)
        app.buttons["返回閱讀"].tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)

        startInterpretationOrganization(organizeButton: organize)
        app.buttons["停止"].tap()
        XCTAssertTrue(app.staticTexts["已停止整理，保留目前內容。"].waitForExistence(timeout: 5))

        startInterpretationOrganization(organizeButton: organize)
        XCTAssertTrue(
            app.staticTexts["已確認回傳格式、內容安全與引用的命盤依據。"]
                .waitForExistence(timeout: 7)
        )
        XCTAssertTrue(app.staticTexts["雲端 AI 整理"].exists)
    }

    func testAI整理解讀失敗會保留完整基本解讀() {
        relaunchMockAI(extraArguments: ["-UITestMockAIInterpretationFailure"])
        createDefaultChart()
        let interpretation = app.buttons["chart.interpretation"]
        scrollToElement(interpretation)
        interpretation.tap()
        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        app.buttons["用 AI 整理文字"].tap()
        app.buttons["interpretation.confirmOrganize"].tap()

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "API 回應逾時")
        ).firstMatch.waitForExistence(timeout: 7))
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)
        XCTAssertTrue(app.buttons["用 AI 整理文字"].exists)
    }

    private func relaunchMockAI(extraArguments: [String] = []) {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockAI"
        ] + extraArguments
        app.launch()
    }

    private func createDefaultChart(name: String? = nil) {
        let createButton = app.buttons["home.createChart"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let generateButton = app.buttons["birthInput.generate"]
        if !generateButton.waitForExistence(timeout: 5), createButton.exists {
            createButton.tap()
        }
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        if let name {
            let nameField = app.textFields["名稱或暱稱（選填）"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.tap()
            nameField.typeText("\(name)\n")
        }
        scrollToElement(generateButton)
        generateButton.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))
    }

    private func openChartAssistant() {
        let askAssistant = app.buttons["chart.askAI"]
        scrollToElement(askAssistant)
        askAssistant.tap()
        XCTAssertTrue(app.navigationBars["命盤助理"].waitForExistence(timeout: 5))
    }

    private func presentInterpretationPreview(organizeButton: XCUIElement) {
        let preview = app.navigationBars["確認 AI 整理"]
        organizeButton.tap()
        if preview.waitForExistence(timeout: 3) { return }
        organizeButton.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    private func startInterpretationOrganization(organizeButton: XCUIElement) {
        presentInterpretationPreview(organizeButton: organizeButton)
        let confirm = app.buttons["interpretation.confirmOrganize"]
        let loading = app.staticTexts["雲端模型正在整理，完成驗證前不會顯示內容。"]
        confirm.tap()
        if loading.waitForExistence(timeout: 3) { return }
        if confirm.exists {
            confirm.tap()
        }
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
    }

    private func startQuestionRequest() {
        let requestState = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier IN %@",
                ["assistant.loading", "assistant.error", "assistant.answer", "assistant.cancelled"]
            )
        ).firstMatch
        tapSendQuestion()
        if requestState.waitForExistence(timeout: 4) { return }
        tapSendQuestion()
        XCTAssertTrue(requestState.waitForExistence(timeout: 5))
    }

    private func tapSendQuestion() {
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 1) {
            app.typeKey(.escape, modifierFlags: [])
            _ = waitForNonExistence(keyboard, timeout: 2)
        }
        let sendButton = app.buttons["assistant.send"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND hittable == true"),
            object: sendButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
        sendButton.tap()
    }

    private func waitForLabel(
        _ element: XCUIElement,
        label: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNonExistence(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
