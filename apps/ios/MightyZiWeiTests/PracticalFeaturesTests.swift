import SwiftData
import SwiftUI
import XCTest
@testable import MightyZiWei

@MainActor
final class PracticalFeaturesTests: XCTestCase {
    func testApp鎖啟用後預設鎖定且背景立即遮罩() throws {
        let suite = "AppLockStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "privacy.app-lock.enabled")
        let store = AppLockStore(defaults: defaults)

        XCTAssertTrue(store.isEnabled)
        XCTAssertTrue(store.isLocked)
        store.handleScenePhase(.background)
        XCTAssertTrue(store.showsPrivacyShield)
        XCTAssertTrue(store.isLocked)
    }

    func test命盤標籤釘選與姓名標籤建立日期搜尋() throws {
        let chart = try makeSavedChart(name: "小明")
        chart.createdAt = makeDate(2026, 8, 26)
        chart.updateTags([" 家人 ", "朋友", "家人", " "])
        chart.setPinned(true)

        XCTAssertEqual(chart.tags, ["家人", "朋友"])
        XCTAssertTrue(chart.isPinned)
        XCTAssertTrue(chart.matchesSearch("小明", calendar: testCalendar))
        XCTAssertTrue(chart.matchesSearch("朋友", calendar: testCalendar))
        XCTAssertTrue(chart.matchesSearch("2026/08/26", calendar: testCalendar))
        XCTAssertFalse(chart.matchesSearch("個案", calendar: testCalendar))
        XCTAssertTrue(
            SavedChartCreatedDateFilter.sevenDays.includes(
                chart.createdAt,
                now: makeDate(2026, 8, 30),
                calendar: testCalendar
            )
        )
    }

    func test相同出生資料可辨識但不同資料不會誤判() throws {
        let first = try makeSavedChart(name: "甲")
        let duplicate = try makeSavedChart(name: "乙")
        let differentProfile = BirthProfile(
            localDate: LocalDate(year: 1991, month: 7, day: 16),
            localTime: LocalTime(hour: 11, minute: 20),
            timeZoneIdentifier: "Asia/Taipei"
        )
        let different = try SavedChart.make(
            name: "丙",
            profile: differentProfile,
            chart: ZiWeiCalculator().calculate(differentProfile)
        )

        XCTAssertTrue(first.hasSameBirthProfile(as: duplicate))
        XCTAssertFalse(first.hasSameBirthProfile(as: different))
    }

    func test觀察筆記保留內容連結命盤依據與自訂回顧時間() {
        let reviewDate = Date.now.addingTimeInterval(7_776_000)
        let note = SavedInsight(
            chartID: UUID(),
            kind: .note,
            locationID: "palace.life",
            title: "命宮觀察",
            content: "三個月後回顧。",
            marker: .observe,
            evidenceFactIDs: ["natal.palace.life.branch"],
            reviewDate: reviewDate
        )

        XCTAssertEqual(note.linkedContentTitle, "命宮")
        XCTAssertEqual(note.evidenceFactIDs, ["natal.palace.life.branch"])
        XCTAssertEqual(note.reviewDate, reviewDate)
    }

    func test保存AI對話可重新命名搜尋並匯出純文字() throws {
        let conversation = SavedConversation(
            chartID: UUID(),
            chartName: "常用命盤",
            chartDetail: "1990/06/15　10:30",
            modelIdentifier: "example-model",
            title: "工作討論",
            turns: [
                ChartConversationTurn(
                    question: "我的工作風格如何？",
                    answer: "你可能傾向先掌握方向。",
                    evidenceFactIDs: ["natal.palace.life.branch"]
                )
            ]
        )
        let container = try ModelContainer(
            for: SavedConversation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(conversation)
        try context.save()

        conversation.rename(to: "職涯觀察")
        XCTAssertTrue(conversation.matchesSearch("職涯"))
        XCTAssertTrue(conversation.matchesSearch("example-model"))
        XCTAssertTrue(conversation.matchesSearch("工作風格"))
        let exported = conversation.exportText()
        XCTAssertTrue(exported.contains("命盤：常用命盤"))
        XCTAssertTrue(exported.contains("模型：example-model"))
        XCTAssertTrue(exported.contains("natal.palace.life.branch"))
    }

    func testAPI用量上限與安全診斷不含敏感內容() throws {
        let suite = "AIUsageStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AIUsageStore(defaults: defaults, calendar: testCalendar)
        store.monthlyLimit = 2

        try store.reserve(.conversation)
        try store.reserve(.interpretation)
        XCTAssertThrowsError(try store.reserve(.connectionTest))
        store.record(
            error: OpenAIResponsesInterpreter.InterpreterError.unauthorized,
            kind: .conversation
        )

        let diagnostic = try XCTUnwrap(store.lastDiagnostic)
        XCTAssertTrue(diagnostic.contains("authorization_failed"))
        XCTAssertTrue(diagnostic.contains("本月請求：2"))
        XCTAssertFalse(diagnostic.contains("sk-private-secret"))
        XCTAssertFalse(diagnostic.contains("https://private.example"))
        XCTAssertFalse(diagnostic.contains("我的私人問題"))
    }

    func test回答長度會限制在安全範圍並保存() throws {
        let suite = "AIAnswerLengthTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = TestCredentialStore()
        let store = AIConfigurationStore(defaults: defaults, credentialStore: credentials)

        store.setMaximumAnswerCharacters(600)
        try store.save(
            endpoint: "https://example.com/v1",
            model: "model",
            apiKey: ""
        )
        XCTAssertEqual(try store.configuration().maximumAnswerCharacters, 600)
        store.setMaximumAnswerCharacters(9_999)
        XCTAssertEqual(store.maximumAnswerCharacters, 2_000)
    }

    func testCloudKit衝突保留較新版本且刪除時間優先() {
        let resolver = CloudConflictResolver()
        let older = makeDate(2026, 1, 1)
        let newer = makeDate(2026, 2, 1)

        XCTAssertEqual(
            resolver.winner(localUpdatedAt: older, remoteUpdatedAt: newer),
            .remote
        )
        XCTAssertEqual(
            resolver.winner(localUpdatedAt: newer, remoteUpdatedAt: older),
            .local
        )
        XCTAssertTrue(resolver.isDeleted(contentUpdatedAt: older, deletedAt: newer))
        XCTAssertFalse(resolver.isDeleted(contentUpdatedAt: newer, deletedAt: older))
    }

    func test加密備份保留分類與回顧資料但不含提醒識別碼() throws {
        let chart = try makeSavedChart(name: "備份命盤")
        chart.updateTags(["個案"])
        chart.setPinned(true)
        let note = SavedInsight(
            chartID: chart.id,
            kind: .note,
            locationID: "interpretation.career",
            title: "工作觀察",
            content: "稍後回顧",
            reviewDate: makeDate(2027, 1, 1),
            reminderIdentifier: "review.secret-device-id"
        )
        let payload = try BackupPayload(savedCharts: [chart], savedInsights: [note])
        let restoredChart = try XCTUnwrap(payload.validated().makeSavedCharts().first)
        let restoredNote = try XCTUnwrap(payload.validated().makeSavedInsights().first)

        XCTAssertEqual(restoredChart.tags, ["個案"])
        XCTAssertTrue(restoredChart.isPinned)
        XCTAssertEqual(restoredNote.reviewDate, makeDate(2027, 1, 1))
        XCTAssertNil(restoredNote.reminderIdentifier)
        let encoded = try BackupJSONCoding.encoder().encode(payload)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret-device-id"))
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeSavedChart(name: String) throws -> SavedChart {
        let profile = BirthProfile(
            localDate: LocalDate(year: 1990, month: 6, day: 15),
            localTime: LocalTime(hour: 10, minute: 30),
            timeZoneIdentifier: "Asia/Taipei"
        )
        return try SavedChart.make(
            name: name,
            profile: profile,
            chart: ZiWeiCalculator().calculate(profile)
        )
    }
}

private final class TestCredentialStore: APICredentialStoring {
    private var value: String?

    func loadAPIKey() throws -> String? { value }
    func saveAPIKey(_ apiKey: String?) throws { value = apiKey }
}
