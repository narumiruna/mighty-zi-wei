import SwiftData
import SwiftUI
import XCTest
@testable import MightyZiWei

@MainActor
final class PracticalFeaturesTests: XCTestCase {
    private enum ModelContainerTestError: Error {
        case cannotLoad
    }

    func test啟動時本機資料容器載入失敗不會觸發FatalError() {
        let result = AppModelContainerLoader.load {
            throw ModelContainerTestError.cannotLoad
        }

        guard case .failure = result else {
            return XCTFail("資料容器載入失敗時應回傳可處理的錯誤。")
        }
    }

    func testUI測試啟動時可建立記憶體資料容器() {
        let result = AppModelContainerLoader.load(arguments: ["-UITestResetData"])

        guard case .success = result else {
            return XCTFail("應可建立記憶體資料容器。")
        }
    }

    func test重建後重新載入失敗會回報錯誤() {
        let result: Result<Int, any Error> = .failure(ModelContainerTestError.cannotLoad)

        XCTAssertThrowsError(try PersistenceResetReloadValidator().validate(result)) { error in
            XCTAssertEqual(error as? PersistenceResetError, .reloadFailed)
        }
    }

    func test復原操作進行中不會啟動重疊操作() {
        var gate = PersistenceRecoveryGate()

        XCTAssertTrue(gate.begin(.retry))
        XCTAssertTrue(gate.isRunning)
        XCTAssertFalse(gate.begin(.reset))
        XCTAssertEqual(gate.operation?.statusMessage, "正在重新載入本機資料…")

        gate.finish()

        XCTAssertTrue(gate.begin(.reset))
        XCTAssertEqual(gate.operation?.statusMessage, "正在重建本機資料…")
    }

    func test復原畫面不會顯示系統原始錯誤文字() {
        let frameworkError = CocoaError(.fileReadCorruptFile)
        let message = PersistenceRecoveryMessage.resetFailure(for: frameworkError)

        XCTAssertEqual(PersistenceRecoveryMessage.unavailable, "系統目前無法讀取這台裝置的本機資料。")
        XCTAssertEqual(
            PersistenceRecoveryMessage.retryFailure,
            "仍無法讀取本機資料。你可以再次重試，或重建本機資料。"
        )
        XCTAssertEqual(
            PersistenceRecoveryMessage.iCloudRestoration,
            "如果先前已開啟 iCloud 同步，重建成功後會自動同步已存在 iCloud 的命盤、筆記與收藏。對話只儲存在本機，不會復原。"
        )
        XCTAssertEqual(message, "目前無法重建本機資料。請確認裝置有足夠儲存空間後再試。")
        XCTAssertFalse(message.contains(frameworkError.localizedDescription))
        XCTAssertEqual(
            PersistenceRecoveryMessage.resetFailure(for: PersistenceResetError.reloadFailed),
            "本機資料已清除，但仍無法建立新的資料庫。請確認裝置有足夠儲存空間後再試。"
        )
    }

    func test本機資料重建只刪除SwiftData預設資料檔() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AppModelStoreResetterTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeFiles = [
            "default.store",
            "default.store-journal",
            "default.store-shm",
            "default.store-wal"
        ]
        for file in storeFiles {
            try Data("test".utf8).write(to: directory.appending(path: file))
        }
        let preservedFiles = [
            "default.store-backup",
            "default.store-journal-backup",
            "user-export.json"
        ]
        for file in preservedFiles {
            try Data("keep".utf8).write(to: directory.appending(path: file))
        }

        try AppModelStoreResetter(storeDirectory: directory).resetDefaultStoreFiles()

        for file in storeFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: file).path))
        }
        for file in preservedFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: file).path))
        }
    }

    func test隱私遮罩在背景或鎖定時都必須顯示() {
        let policy = AppPrivacyShieldPolicy()

        XCTAssertFalse(policy.shouldPresent(showsPrivacyShield: false, isLocked: false))
        XCTAssertTrue(policy.shouldPresent(showsPrivacyShield: true, isLocked: false))
        XCTAssertTrue(policy.shouldPresent(showsPrivacyShield: false, isLocked: true))
    }

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

    func testApp鎖啟用時重建驗證不會解除鎖定() async throws {
        let suite = "AppLockResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "privacy.app-lock.enabled")
        let store = AppLockStore(defaults: defaults)
        var authenticationCount = 0

        let denied = await store.authorizeDataReset(using: {
            authenticationCount += 1
            return false
        })
        let authorized = await store.authorizeDataReset(using: {
            authenticationCount += 1
            return true
        })

        XCTAssertFalse(denied)
        XCTAssertTrue(authorized)
        XCTAssertTrue(store.isLocked)
        XCTAssertEqual(authenticationCount, 2)
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

    func test已選標籤不存在時會自動清除篩選() {
        let policy = SavedChartTagSelectionPolicy()

        XCTAssertEqual(
            policy.validSelection("家人", availableTags: ["家人", "朋友"]),
            "家人"
        )
        XCTAssertNil(policy.validSelection("家人", availableTags: ["朋友"]))
        XCTAssertNil(policy.validSelection("家人", availableTags: []))
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

    func test保存AI對話匯出前會揭露個人資料欄位() {
        let guardPolicy = SavedConversationExportPrivacyGuard()

        XCTAssertEqual(
            guardPolicy.includedFields,
            ["命盤名稱", "出生日期與時間", "模型與完整問答"]
        )
        XCTAssertEqual(
            guardPolicy.fieldSummary,
            "命盤名稱、出生日期與時間、模型與完整問答"
        )
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

    func test命盤整理回答長度會分配到全部必要分類() {
        let budget = InterpretationLengthBudget(totalCharacters: 1_200, sectionCount: 5)

        XCTAssertEqual(budget.maximumSectionCharacters, 240)
        XCTAssertLessThanOrEqual(budget.maximumSectionCharacters * budget.sectionCount, 1_200)
    }

    func test回顧提醒更新使用不同識別碼以保留舊通知直到儲存成功() {
        let insightID = UUID()
        let first = ReviewReminderScheduler.makeIdentifier(insightID: insightID)
        let second = ReviewReminderScheduler.makeIdentifier(insightID: insightID)

        XCTAssertTrue(first.hasPrefix("review.\(insightID.uuidString)."))
        XCTAssertNotEqual(first, second)
    }

    func test重建會辨識待發送與已發送的App回顧提醒() {
        let pendingIdentifiers = ReviewReminderScheduler.reviewReminderIdentifiers(in: [
            "review.pending",
            "other.pending"
        ])
        let deliveredIdentifiers = ReviewReminderScheduler.reviewReminderIdentifiers(in: [
            "other.delivered",
            "review.delivered"
        ])

        XCTAssertEqual(pendingIdentifiers, ["review.pending"])
        XCTAssertEqual(deliveredIdentifiers, ["review.delivered"])
    }

    func test套用遠端筆記時會保留舊提醒直到替代通知儲存成功() {
        let insightID = UUID()
        let chartID = UUID()
        let local = SavedInsight(
            id: insightID,
            chartID: chartID,
            kind: .note,
            locationID: "chart.general",
            title: "舊標題",
            content: "舊內容",
            reviewDate: makeDate(2027, 1, 1),
            reminderIdentifier: "review.old-device-request"
        )
        let remote = SavedInsight(
            id: insightID,
            chartID: chartID,
            kind: .note,
            locationID: "chart.general",
            title: "新標題",
            content: "新內容",
            reviewDate: makeDate(2027, 2, 1),
            updatedAt: makeDate(2026, 9, 1)
        )

        CloudInsightPayload(remote).apply(to: local)

        XCTAssertEqual(local.title, "新標題")
        XCTAssertEqual(local.reviewDate, makeDate(2027, 2, 1))
        XCTAssertEqual(local.reminderIdentifier, "review.old-device-request")
    }

    func test刪除標記會定位原始CloudKit內容紀錄() throws {
        let entityID = UUID()
        let chartReference = try XCTUnwrap(
            CloudContentRecordReference(entityType: "SavedChart", entityID: entityID)
        )
        let insightReference = try XCTUnwrap(
            CloudContentRecordReference(entityType: "SavedInsight", entityID: entityID)
        )

        XCTAssertEqual(chartReference.recordType, "SavedChart")
        XCTAssertEqual(chartReference.recordName, entityID.uuidString)
        XCTAssertEqual(insightReference.recordType, "SavedInsight")
        XCTAssertEqual(insightReference.recordName, entityID.uuidString)
        XCTAssertNil(CloudContentRecordReference(entityType: "Unknown", entityID: entityID))
    }

    func test相同或較舊的刪除標記不會重複上傳() {
        let policy = CloudTombstoneUploadPolicy()
        let older = makeDate(2026, 1, 1)
        let newer = makeDate(2026, 2, 1)

        XCTAssertTrue(policy.shouldUpload(localDeletedAt: older, remoteDeletedAt: nil))
        XCTAssertFalse(policy.shouldUpload(localDeletedAt: older, remoteDeletedAt: older))
        XCTAssertFalse(policy.shouldUpload(localDeletedAt: older, remoteDeletedAt: newer))
        XCTAssertTrue(policy.shouldUpload(localDeletedAt: newer, remoteDeletedAt: older))
    }

    func testCloudKit內容紀錄不存在時仍會把有效刪除標記套用到本機資料() throws {
        let deletedChart = try makeSavedChart(name: "已刪命盤")
        let survivingChart = try makeSavedChart(name: "保留命盤")
        let older = makeDate(2026, 1, 1)
        let newer = makeDate(2026, 2, 1)
        deletedChart.updatedAt = older
        survivingChart.updatedAt = newer
        let childInsight = SavedInsight(
            chartID: deletedChart.id,
            kind: .note,
            locationID: "chart.general",
            title: "隨命盤刪除",
            content: "內容",
            updatedAt: newer
        )
        let independentInsight = SavedInsight(
            chartID: survivingChart.id,
            kind: .note,
            locationID: "chart.general",
            title: "單獨刪除",
            content: "內容",
            updatedAt: older
        )
        let plan = CloudLocalTombstonePlanner().makePlan(
            charts: [deletedChart, survivingChart],
            insights: [childInsight, independentInsight],
            deletions: [
                CloudDeletion(
                    entityID: deletedChart.id,
                    entityType: "SavedChart",
                    deletedAt: newer
                ),
                CloudDeletion(
                    entityID: survivingChart.id,
                    entityType: "SavedChart",
                    deletedAt: older
                ),
                CloudDeletion(
                    entityID: independentInsight.id,
                    entityType: "SavedInsight",
                    deletedAt: newer
                )
            ]
        )

        XCTAssertEqual(plan.chartIDs, [deletedChart.id])
        XCTAssertEqual(plan.insightIDs, [childInsight.id, independentInsight.id])

        let newerRemotePlan = CloudLocalTombstonePlanner().makePlan(
            charts: [deletedChart],
            insights: [],
            deletions: [
                CloudDeletion(
                    entityID: deletedChart.id,
                    entityType: "SavedChart",
                    deletedAt: newer
                )
            ],
            remoteChartUpdatedAt: [
                deletedChart.id: newer.addingTimeInterval(60)
            ]
        )
        XCTAssertTrue(newerRemotePlan.chartIDs.isEmpty)
    }

    func testWidget共享狀態保留所有未來提醒並移除過期日期() throws {
        let suite = "ReviewWidgetStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = makeDate(2026, 8, 26)
        let first = now.addingTimeInterval(3_600)
        let second = now.addingTimeInterval(7_200)
        defaults.set(123, forKey: ReviewReminderScheduler.nextReminderKey)

        ReviewReminderScheduler.storeWidgetReminderDates(
            [now.addingTimeInterval(-60), second, first, first],
            now: now,
            defaults: defaults
        )

        XCTAssertEqual(
            defaults.array(forKey: ReviewReminderScheduler.reminderDatesKey) as? [Double],
            [first.timeIntervalSince1970, second.timeIntervalSince1970]
        )
        XCTAssertNil(defaults.object(forKey: ReviewReminderScheduler.nextReminderKey))

        ReviewReminderScheduler.storeWidgetReminderDates([], now: now, defaults: defaults)

        XCTAssertEqual(
            defaults.array(forKey: ReviewReminderScheduler.reminderDatesKey) as? [Double],
            []
        )
    }

    func test重建後會清除已刪除命盤的釘選捷徑() throws {
        let suite = "PinnedChartResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UUID().uuidString, forKey: PinnedChartShortcut.key)

        PinnedChartShortcut.reconcile(charts: [], defaults: defaults)

        XCTAssertNil(defaults.string(forKey: PinnedChartShortcut.key))
    }

    func test同步會依命盤與位置去除重複收藏並保留最新版本() {
        let chartID = UUID()
        let local = SavedInsight(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            chartID: chartID,
            kind: .bookmark,
            locationID: "interpretation.overview",
            title: "本機收藏",
            content: "較舊內容",
            updatedAt: makeDate(2026, 1, 1)
        )
        let remoteWinner = SavedInsight(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            chartID: chartID,
            kind: .bookmark,
            locationID: "interpretation.overview",
            title: "遠端收藏",
            content: "最新內容",
            updatedAt: makeDate(2026, 3, 1)
        )
        let remoteDuplicate = SavedInsight(
            id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            chartID: chartID,
            kind: .bookmark,
            locationID: "interpretation.overview",
            title: "另一份收藏",
            content: "中間版本",
            updatedAt: makeDate(2026, 2, 1)
        )
        let otherLocation = SavedInsight(
            chartID: chartID,
            kind: .bookmark,
            locationID: "interpretation.career",
            title: "工作收藏",
            content: "不同位置",
            updatedAt: makeDate(2026, 4, 1)
        )

        let plan = CloudBookmarkDeduplicator().makePlan(
            localInsights: [local],
            remoteInsights: [
                CloudInsightPayload(remoteWinner),
                CloudInsightPayload(remoteDuplicate),
                CloudInsightPayload(otherLocation)
            ]
        )

        XCTAssertEqual(plan.duplicateIDs, [local.id, remoteDuplicate.id])
        XCTAssertFalse(plan.duplicateIDs.contains(remoteWinner.id))
        XCTAssertFalse(plan.duplicateIDs.contains(otherLocation.id))
    }

    func test重建衍生命盤快取不會改寫同步內容版本() throws {
        let chart = try makeSavedChart(name: "同步命盤")
        let synchronizedRevision = makeDate(2026, 2, 1)
        chart.chartCacheData = nil
        chart.updatedAt = synchronizedRevision

        _ = try chart.resolvedChart()

        XCTAssertNotNil(chart.chartCacheData)
        XCTAssertEqual(chart.updatedAt, synchronizedRevision)
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

    func test同步協調器讓同時請求共用同一個執行結果() async throws {
        let coordinator = ICloudSyncCoordinator()
        let expected = ICloudSyncResult(uploadedCount: 1, downloadedCount: 2, conflictCount: 3)
        var executionCount = 0
        var release: CheckedContinuation<Void, Never>?

        let first = Task { @MainActor in
            try await coordinator.synchronize {
                executionCount += 1
                await withCheckedContinuation { release = $0 }
                return expected
            }
        }
        while release == nil {
            await Task.yield()
        }
        let second = Task { @MainActor in
            try await coordinator.synchronize {
                executionCount += 1
                return ICloudSyncResult(
                    uploadedCount: 99,
                    downloadedCount: 99,
                    conflictCount: 99
                )
            }
        }
        while coordinator.waitingCallerCount == 0 {
            await Task.yield()
        }
        release?.resume()
        release = nil

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, expected)
        XCTAssertEqual(secondResult, expected)
        XCTAssertEqual(executionCount, 1)
        XCTAssertFalse(coordinator.isSyncing)
    }

    func test同步流程拋錯時會回復所有尚未儲存的SwiftData變更() async throws {
        let chart = try makeSavedChart(name: "同步前")
        let container = try ModelContainer(
            for: SavedChart.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(chart)
        try context.save()
        var didRunRollbackAction = false

        do {
            let _: Void = try await CloudSyncMutationTransaction.run(
                modelContext: context,
                onRollback: { didRunRollbackAction = true }
            ) {
                try chart.rename(to: "尚未完成")
                throw SyncTransactionTestError.expected
            }
            XCTFail("同步錯誤應向呼叫端拋出。")
        } catch SyncTransactionTestError.expected {
            // 預期錯誤。
        }

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SavedChart>()).first)
        XCTAssertEqual(restored.name, "同步前")
        XCTAssertTrue(didRunRollbackAction)
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

private enum SyncTransactionTestError: Error {
    case expected
}

private final class TestCredentialStore: APICredentialStoring {
    private var value: String?

    func loadAPIKey() throws -> String? { value }
    func saveAPIKey(_ apiKey: String?) throws { value = apiKey }
}
