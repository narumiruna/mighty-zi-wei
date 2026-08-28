import XCTest

@MainActor
final class MightyZiWeiRedesignUITests: XCTestCase {
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

    func test標準最大字級會改用線性命盤避免宮格溢位() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryXXXL"
        ]
        app.launch()

        createDefaultChart()
        let parentsPalace = app.buttons["chart.palace.parents"]
        scrollToElement(parentsPalace)
        XCTAssertTrue(parentsPalace.isHittable)
        XCTAssertTrue(parentsPalace.label.contains("宮位干支"))
    }

    func test減少動態效果時主要流程不依賴動畫() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        ]
        app.launch()

        createDefaultChart()
        XCTAssertTrue(app.buttons["chart.interpretation"].isHittable)
        openInterpretation()
        XCTAssertTrue(interpretationSourceLabel("基本解讀").waitForExistence(timeout: 5))
    }

    func test解讀第一屏顯示版本且AI整理可返回停止與完成() {
        relaunchMockAI()
        createDefaultChart()
        openInterpretation()
        XCTAssertTrue(
            app.descendants(matching: .any)["interpretation.source"]
                .waitForExistence(timeout: 5)
        )
        let currentSource = interpretationSourceLabel("基本解讀")
        assertVisibleInContentViewport(currentSource, navigationTitle: "命盤解讀")
        XCTAssertFalse(app.buttons["interpretation.source.ai"].exists)
        XCTAssertTrue(app.staticTexts["基本解讀"].exists)

        let organize = app.buttons["用 AI 整理文字"]
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.tap()
        XCTAssertTrue(app.navigationBars["確認 AI 整理"].waitForExistence(timeout: 5))
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

        scrollToTop()
        let basicSource = app.buttons["interpretation.source.basic"]
        let aiSource = app.buttons["interpretation.source.ai"]
        XCTAssertTrue(basicSource.waitForExistence(timeout: 3))
        XCTAssertTrue(aiSource.waitForExistence(timeout: 3))
        XCTAssertEqual(aiSource.value as? String, "目前版本")
        basicSource.tap()
        XCTAssertEqual(basicSource.value as? String, "目前版本")
        XCTAssertTrue(interpretationSourceLabel("基本解讀").exists)
        aiSource.tap()
        XCTAssertEqual(aiSource.value as? String, "目前版本")
        XCTAssertTrue(interpretationSourceLabel("雲端 AI 整理").exists)
    }

    func test出生主要操作與命盤主要操作依核准順序排列() {
        let generate = openBirthInput()
        XCTAssertTrue(generate.isHittable)
        let compareHours = app.buttons["birthInput.compareHours"]
        scrollToElement(compareHours)
        XCTAssertGreaterThan(compareHours.frame.minY, generate.frame.minY)
        scrollToElement(generate)
        generate.tap()
        XCTAssertTrue(app.staticTexts["命盤總覽"].waitForExistence(timeout: 5))

        let interpretation = app.buttons["chart.interpretation"]
        let assistant = app.buttons["chart.askAI"]
        let palaceHeading = app.staticTexts["自由探索十二宮"]
        let toolsHeading = app.staticTexts["命盤工具"]
        XCTAssertTrue(interpretation.waitForExistence(timeout: 5))
        XCTAssertTrue(assistant.waitForExistence(timeout: 5))
        XCTAssertTrue(palaceHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(toolsHeading.waitForExistence(timeout: 5))
        XCTAssertLessThan(interpretation.frame.minY, assistant.frame.minY)
        XCTAssertLessThan(assistant.frame.maxY, palaceHeading.frame.minY)
        XCTAssertLessThan(palaceHeading.frame.minY, toolsHeading.frame.minY)
    }

    func test已儲存空狀態可直接開始排盤() {
        app.tabBars.buttons["已儲存"].tap()
        XCTAssertTrue(app.navigationBars["已儲存命盤"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["還沒有已儲存命盤"].exists)
        let create = app.buttons["savedCharts.createChart"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(app.buttons["birthInput.generate"].waitForExistence(timeout: 5))
    }

    func test已儲存篩選工具列摘要與搜尋組合空狀態() {
        createDefaultChart(name: "篩選測試")
        app.buttons["chart.save"].tap()
        XCTAssertTrue(app.staticTexts["命盤已儲存在這台裝置。"].waitForExistence(timeout: 3))
        app.tabBars.buttons["已儲存"].tap()
        XCTAssertTrue(app.navigationBars["已儲存命盤"].waitForExistence(timeout: 5))

        let rowMenu = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "savedCharts.rowMenu."
        )).firstMatch
        XCTAssertTrue(rowMenu.waitForExistence(timeout: 5))
        rowMenu.tap()
        app.buttons["編輯標籤"].tap()
        let tagField = app.textFields["例如：家人、朋友、個案"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 3))
        tagField.tap()
        tagField.typeText("家人")
        app.buttons["儲存"].tap()

        let filter = app.buttons["savedCharts.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        selectMenuOption("家人", submenu: "標籤")
        let summary = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            "savedCharts.filterSummary",
            "篩選：#家人"
        )).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue((filter.value as? String)?.contains("#家人") == true)

        let search = app.searchFields["搜尋姓名、標籤或建立日期"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("完全不存在")
        let combinedEmpty = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            "savedCharts.empty.searchAndFilter",
            "找不到符合搜尋與篩選的命盤"
        )).firstMatch
        XCTAssertTrue(combinedEmpty.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["找不到符合搜尋與篩選的命盤"].exists)
        dismissKeyboardIfPresent()
        let clearAll = app.buttons["清除全部條件"]
        scrollToElement(clearAll)
        clearAll.tap()
        XCTAssertTrue(app.staticTexts["篩選測試"].waitForExistence(timeout: 5))

        search.tap()
        search.typeText("仍然不存在")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            "savedCharts.empty.search",
            "找不到搜尋結果"
        )).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["找不到搜尋結果"].exists)
        dismissKeyboardIfPresent()
        app.buttons["清除搜尋"].tap()
        XCTAssertTrue(app.staticTexts["篩選測試"].waitForExistence(timeout: 5))
    }

    func test未儲存命盤的收藏顯示停用原因() {
        createDefaultChart()
        openInterpretation()

        let bookmark = app.buttons["收藏"].firstMatch
        scrollToElement(bookmark)
        XCTAssertFalse(bookmark.isEnabled)
        let reason = app.staticTexts["先儲存命盤才能收藏"].firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 3))
    }

    func testAPI設定取消會丟棄全部畫面草稿() {
        createDefaultChart()
        openInterpretation()
        let configure = app.buttons["interpretation.configureAI"]
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        configure.tap()
        XCTAssertTrue(app.navigationBars["AI API 設定"].waitForExistence(timeout: 5))

        let endpoint = app.textFields["ai.endpoint"]
        let model = app.textFields["ai.model"]
        let apiKey = app.secureTextFields["ai.apiKey"]
        let originalEndpoint = endpoint.value as? String
        let originalModel = model.value as? String
        let originalAPIKey = apiKey.value as? String
        replaceText(in: endpoint, with: "https://draft.example/v1")
        replaceText(in: model, with: "draft-model")
        apiKey.tap()
        apiKey.typeText("draft-only-key")
        app.buttons["取消"].tap()

        XCTAssertTrue(app.navigationBars["命盤解讀"].waitForExistence(timeout: 5))
        configure.tap()
        XCTAssertTrue(app.navigationBars["AI API 設定"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["ai.endpoint"].value as? String, originalEndpoint)
        XCTAssertEqual(app.textFields["ai.model"].value as? String, originalModel)
        XCTAssertEqual(app.secureTextFields["ai.apiKey"].value as? String, originalAPIKey)
    }

    func testiCloud首次啟用可預覽取消後再成功同步() {
        openSettings()
        let toggle = app.switches["settings.icloud.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollToElement(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        presentICloudEnablePreview(toggle: toggle)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "不會同步：API 設定"
        )).firstMatch.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(waitForNonExistence(app.buttons["啟用並同步"], timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts.matching(
            identifier: "settings.icloud.status"
        ).firstMatch.exists)

        presentICloudEnablePreview(toggle: toggle)
        app.buttons["啟用並同步"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let status = app.staticTexts.matching(
            identifier: "settings.icloud.status"
        ).firstMatch
        XCTAssertTrue(waitForLabelContaining(status, text: "同步完成", timeout: 5))
        XCTAssertTrue(app.buttons["settings.icloud.sync"].exists)
    }

    func test有部分遠端寫入的iCloud失敗保持啟用並可重試() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockICloudPartialFailure"
        ]
        app.launch()

        openSettings()
        let toggle = app.switches["settings.icloud.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollToElement(toggle)
        presentICloudEnablePreview(toggle: toggle)
        app.buttons["啟用並同步"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let status = app.staticTexts.matching(
            identifier: "settings.icloud.status"
        ).firstMatch
        XCTAssertTrue(waitForLabelContaining(
            status,
            text: "iCloud 可能已收到部分資料",
            timeout: 5
        ))
        XCTAssertTrue(app.buttons["重試同步"].isHittable)
    }

    private func relaunchMockAI() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = localizationArguments + [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-UITestMockAI"
        ]
        app.launch()
    }

    private func createDefaultChart(name: String? = nil) {
        let generateButton = openBirthInput()
        if let name {
            let nameField = app.textFields["名稱或暱稱（選填）"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.tap()
            nameField.typeText("\(name)\n")
        }
        scrollToElement(generateButton)
        let overview = app.staticTexts["命盤總覽"]
        generateButton.tap()
        if !overview.waitForExistence(timeout: 5), generateButton.exists {
            generateButton.tap()
        }
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
    }

    private func openBirthInput() -> XCUIElement {
        let create = app.buttons["home.createChart"]
        let generate = app.buttons["birthInput.generate"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        return generate
    }

    private func openInterpretation() {
        let interpretation = app.buttons["chart.interpretation"]
        let destination = app.navigationBars["命盤解讀"]
        scrollToElement(interpretation)
        interpretation.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
    }

    private func presentInterpretationPreview(organizeButton: XCUIElement) {
        let preview = app.navigationBars["確認 AI 整理"]
        organizeButton.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    private func startInterpretationOrganization(organizeButton: XCUIElement) {
        presentInterpretationPreview(organizeButton: organizeButton)
        let confirm = app.buttons["interpretation.confirmOrganize"]
        let loading = app.staticTexts["雲端模型正在整理，完成驗證前不會顯示內容。"]
        confirm.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
    }

    private func waitForLabelContaining(
        _ element: XCUIElement,
        text: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
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

    private func interpretationSourceLabel(_ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "interpretation.source.current",
            title
        )).firstMatch
    }

    private func assertVisibleInContentViewport(
        _ element: XCUIElement,
        navigationTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let navigationBar = app.navigationBars[navigationTitle]
        let bottom = app.tabBars.firstMatch.exists
            ? app.tabBars.firstMatch.frame.minY
            : app.frame.maxY
        XCTAssertGreaterThanOrEqual(
            element.frame.minY,
            navigationBar.frame.maxY,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            bottom,
            file: file,
            line: line
        )
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func dismissKeyboardIfPresent() {
        if app.keyboards.firstMatch.exists {
            app.typeKey(.escape, modifierFlags: [])
            _ = waitForNonExistence(app.keyboards.firstMatch, timeout: 2)
        }
    }

    private func selectMenuOption(_ title: String, submenu: String) {
        let option = app.buttons[title]
        if !option.waitForExistence(timeout: 2) {
            let submenuButton = app.buttons[submenu]
            XCTAssertTrue(submenuButton.waitForExistence(timeout: 2))
            submenuButton.tap()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    private func presentICloudEnablePreview(toggle: XCUIElement) {
        let confirm = app.buttons["啟用並同步"]
        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
    }

    private func openSettings() {
        let settings = app.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["設定"].waitForExistence(timeout: 5), settings.exists {
            settings.tap()
        }
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
    }

    private func scrollToTop() {
        for _ in 0..<6 {
            app.swipeDown()
        }
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
}
