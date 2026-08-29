import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class EncryptedBackupServiceTests: XCTestCase {
  func test備份往返只保留來源資料與通用Insight() throws {
    let savedChart = try makeSavedChart()
    let insight = makeInsight(chartID: savedChart.id)

    let backup = try EncryptedBackupService.makeBackup(
      savedCharts: [savedChart],
      insights: [insight]
    )
    let payload = try EncryptedBackupService.restore(
      from: backup.data,
      encodedRecoveryKey: backup.recoveryKey.encoded
    )

    XCTAssertEqual(backup.recoveryKey.rawRepresentation.count, 32)
    XCTAssertEqual(payload.schemaVersion, 1)
    XCTAssertEqual(payload.charts, [try BackupChartDTO(savedChart: savedChart)])
    XCTAssertEqual(payload.insights, [insight])

    let restored = try XCTUnwrap(payload.makeSavedCharts().first)
    XCTAssertEqual(restored.id, savedChart.id)
    XCTAssertEqual(restored.name, savedChart.name)
    XCTAssertEqual(try restored.birthProfile(), try savedChart.birthProfile())
    XCTAssertEqual(restored.ruleSetID, savedChart.ruleSetID)
    XCTAssertEqual(restored.ruleSetVersion, savedChart.ruleSetVersion)
    XCTAssertEqual(restored.appSchemaVersion, savedChart.appSchemaVersion)
    XCTAssertEqual(restored.createdAt, savedChart.createdAt)
    XCTAssertEqual(restored.updatedAt, savedChart.updatedAt)
    XCTAssertNil(restored.chartCacheData)

    let restoredInsight = try XCTUnwrap(payload.makeSavedInsights().first)
    XCTAssertEqual(restoredInsight.id, insight.id)
    XCTAssertEqual(restoredInsight.locationID, insight.locationID)
    XCTAssertEqual(restoredInsight.marker, .resonates)
    XCTAssertEqual(restoredInsight.evidenceSeedIDs, insight.evidenceSeedIDs)
    XCTAssertEqual(restoredInsight.evidenceFactIDs, insight.evidenceFactIDs)
  }

  func testPayload不含敏感設定對話Endpoint或命盤Cache() throws {
    let savedChart = try makeSavedChart()
    let payload = try BackupPayload(
      savedCharts: [savedChart],
      insights: [makeInsight(chartID: savedChart.id)]
    )
    let data = try BackupJSONCoding.encoder().encode(payload)
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let charts = try XCTUnwrap(root["charts"] as? [[String: Any]])
    let chart = try XCTUnwrap(charts.first)
    let insights = try XCTUnwrap(root["insights"] as? [[String: Any]])
    let insight = try XCTUnwrap(insights.first)

    XCTAssertEqual(Set(root.keys), ["charts", "insights", "schemaVersion"])
    XCTAssertEqual(
      Set(chart.keys),
      [
        "appSchemaVersion",
        "birthProfile",
        "createdAt",
        "id",
        "name",
        "tags",
        "isPinned",
        "ruleSetID",
        "ruleSetVersion",
        "updatedAt",
      ])
    XCTAssertEqual(
      Set(insight.keys),
      [
        "body",
        "chartID",
        "createdAt",
        "evidenceFactIDs",
        "evidenceSeedIDs",
        "id",
        "kind",
        "locationID",
        "marker",
        "title",
        "updatedAt",
      ])

    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains("chartCacheData"))
    XCTAssertFalse(json.contains("apiKey"))
    XCTAssertFalse(json.contains("conversation"))
    XCTAssertFalse(json.contains("endpoint"))
    XCTAssertFalse(json.contains("這段衍生命盤快取不得匯出"))
  }

  func testDeterministicJSONEncoder對相同Payload產生相同資料() throws {
    let savedChart = try makeSavedChart()
    let payload = try BackupPayload(
      savedCharts: [savedChart],
      insights: [makeInsight(chartID: savedChart.id)]
    )

    let first = try BackupJSONCoding.encoder().encode(payload)
    let second = try BackupJSONCoding.encoder().encode(payload)

    XCTAssertEqual(first, second)
    XCTAssertTrue(try XCTUnwrap(String(data: first, encoding: .utf8)).hasPrefix("{\"charts\":"))
  }

  func test每次備份都產生隨機256BitRecoveryKey與Nonce() throws {
    let savedChart = try makeSavedChart()

    let first = try EncryptedBackupService.makeBackup(savedCharts: [savedChart])
    let second = try EncryptedBackupService.makeBackup(savedCharts: [savedChart])

    XCTAssertEqual(first.recoveryKey.rawRepresentation.count, 32)
    XCTAssertEqual(second.recoveryKey.rawRepresentation.count, 32)
    XCTAssertNotEqual(first.recoveryKey, second.recoveryKey)
    XCTAssertNotEqual(first.data, second.data)
  }

  func test拒絕不支援的封裝Schema與演算法() throws {
    let backup = try EncryptedBackupService.makeBackup(savedCharts: [try makeSavedChart()])
    let envelope = try BackupJSONCoding.decoder().decode(
      EncryptedBackupEnvelope.self,
      from: backup.data
    )
    let wrongSchema = EncryptedBackupEnvelope(
      schemaVersion: 2,
      algorithm: envelope.algorithm,
      sealedPayload: envelope.sealedPayload
    )
    let wrongAlgorithm = EncryptedBackupEnvelope(
      schemaVersion: envelope.schemaVersion,
      algorithm: "AES-128-GCM",
      sealedPayload: envelope.sealedPayload
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: BackupJSONCoding.encoder().encode(wrongSchema),
        recoveryKey: backup.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .unsupportedEnvelopeSchema(2))
    }
    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: BackupJSONCoding.encoder().encode(wrongAlgorithm),
        recoveryKey: backup.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .unsupportedAlgorithm("AES-128-GCM"))
    }
  }

  func test拒絕不支援的PayloadSchema() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    object["schemaVersion"] = 2
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .unsupportedPayloadSchema(2))
    }
  }

  func test拒絕錯誤格式或長度的RecoveryKey() throws {
    XCTAssertThrowsError(try BackupRecoveryKey(encoded: "不是 Base64")) { error in
      XCTAssertEqual(error as? BackupError, .invalidRecoveryKey)
    }
    XCTAssertThrowsError(try BackupRecoveryKey(rawRepresentation: Data(repeating: 0, count: 31))) {
      error in
      XCTAssertEqual(error as? BackupError, .invalidRecoveryKey)
    }
  }

  func test拒絕錯誤RecoveryKey() throws {
    let backup = try EncryptedBackupService.makeBackup(savedCharts: [try makeSavedChart()])
    let wrongKey = BackupRecoveryKey()

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backup.data,
        recoveryKey: wrongKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .authenticationFailed)
    }
  }

  func test拒絕遭竄改的密文() throws {
    let backup = try EncryptedBackupService.makeBackup(savedCharts: [try makeSavedChart()])
    let envelope = try BackupJSONCoding.decoder().decode(
      EncryptedBackupEnvelope.self,
      from: backup.data
    )
    var tamperedPayload = envelope.sealedPayload
    let lastIndex = tamperedPayload.index(before: tamperedPayload.endIndex)
    tamperedPayload[lastIndex] ^= 0x01
    let tamperedEnvelope = EncryptedBackupEnvelope(
      schemaVersion: envelope.schemaVersion,
      algorithm: envelope.algorithm,
      sealedPayload: tamperedPayload
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: BackupJSONCoding.encoder().encode(tamperedEnvelope),
        recoveryKey: backup.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .authenticationFailed)
    }
  }

  func test拒絕超過10MiB的輸入() {
    let oversized = Data(
      repeating: 0,
      count: EncryptedBackupService.maximumInputSize + 1
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: oversized,
        recoveryKey: BackupRecoveryKey()
      )
    ) { error in
      XCTAssertEqual(
        error as? BackupError,
        .inputTooLarge(maximumBytes: EncryptedBackupService.maximumInputSize)
      )
    }
  }

  func test重複筆記或收藏錯誤使用正體中文() {
    let error = BackupError.duplicateInsightID(UUID())

    XCTAssertEqual(error.errorDescription, "備份包含重複的筆記或收藏識別碼。")
    XCTAssertFalse(error.errorDescription?.contains("insight") == true)
  }

  func test拒絕重複ChartID() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    let charts = try XCTUnwrap(object["charts"] as? [[String: Any]])
    object["charts"] = [try XCTUnwrap(charts.first), try XCTUnwrap(charts.first)]
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      guard case .duplicateChartID = error as? BackupError else {
        return XCTFail("預期拒絕重複 chart ID，實際為 \(error)")
      }
    }
  }

  func test拒絕同一命盤與來源位置的重複收藏() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var first = try XCTUnwrap(
      try XCTUnwrap(object["insights"] as? [[String: Any]]).first
    )
    first["kind"] = SavedInsight.Kind.bookmark.rawValue
    var duplicate = first
    duplicate["id"] = UUID().uuidString
    object["insights"] = [first, duplicate]
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      guard case .duplicateBookmarkLocation(let chartID, let locationID) = error as? BackupError
      else {
        return XCTFail("預期拒絕重複收藏位置，實際為 \(error)")
      }
      XCTAssertEqual(chartID.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
      XCTAssertEqual(locationID, "palace.life")
    }
  }

  func test還原前警告會說明整本內容與較新資料可能刪除() {
    XCTAssertTrue(BackupRestoreWarning.message.contains("整本筆記與收藏"))
    XCTAssertTrue(BackupRestoreWarning.message.contains("本機較新的內容"))
    XCTAssertTrue(BackupRestoreWarning.message.contains("永久刪除"))
  }

  func test還原會原子更新同ID資料並移除該命盤舊Insight() throws {
    let incomingChart = try makeSavedChart()
    incomingChart.name = "備份名稱"
    let existingChart = try makeSavedChart()
    existingChart.name = "本機舊名稱"
    let staleInsight = SavedInsight(
      chartID: existingChart.id,
      kind: .note,
      locationID: "chart.general",
      title: "舊筆記",
      content: "應由備份內容取代"
    )
    let incomingInsight = SavedInsight.bookmark(
      chartID: incomingChart.id,
      locationID: "interpretation.overview",
      title: "備份收藏",
      content: "保留內容",
      evidenceSeedIDs: ["seed.personality.baseline"],
      evidenceFactIDs: ["natal.palace.life.branch"]
    )
    let payload = try BackupPayload(
      savedCharts: [incomingChart],
      savedInsights: [incomingInsight]
    )
    let container = try ModelContainer(
      for: SavedChart.self,
      SavedInsight.self,
      CloudDeletion.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    context.insert(existingChart)
    context.insert(staleInsight)
    try context.save()

    let result = try BackupRestoreService.restore(
      payload.validated(),
      existingCharts: [existingChart],
      existingInsights: [staleInsight],
      modelContext: context
    )

    XCTAssertEqual(result, BackupRestoreResult(chartCount: 1, insightCount: 1))
    let charts = try context.fetch(FetchDescriptor<SavedChart>())
    let restoredInsights = try context.fetch(FetchDescriptor<SavedInsight>())
    XCTAssertEqual(charts.count, 1)
    XCTAssertEqual(charts.first?.name, "備份名稱")
    XCTAssertNil(charts.first?.chartCacheData)
    XCTAssertEqual(restoredInsights.map(\.title), ["備份收藏"])
    XCTAssertEqual(restoredInsights.first?.evidenceSeedIDs, ["seed.personality.baseline"])
    XCTAssertEqual(restoredInsights.first?.evidenceFactIDs, ["natal.palace.life.branch"])
  }

  func test還原會清除舊刪除標記更新同步版本取消舊提醒並重設捷徑() throws {
    let incomingChart = try makeSavedChart()
    incomingChart.isPinned = true
    let incomingInsight = SavedInsight(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      chartID: incomingChart.id,
      kind: .note,
      locationID: "chart.general",
      title: "備份筆記",
      content: "還原內容"
    )
    let payload = try BackupPayload(
      savedCharts: [incomingChart],
      savedInsights: [incomingInsight]
    )

    let existingChart = try makeSavedChart()
    let existingInsight = SavedInsight(
      id: incomingInsight.id,
      chartID: existingChart.id,
      kind: .note,
      locationID: "chart.general",
      title: "本機筆記",
      content: "舊內容",
      reviewDate: Date(timeIntervalSinceReferenceDate: 500_000_000),
      reminderIdentifier: "review.old-device-request"
    )
    let deletedAt = Date(timeIntervalSinceReferenceDate: 600_000_000)
    let chartDeletion = CloudDeletion(
      entityID: existingChart.id,
      entityType: "SavedChart",
      deletedAt: deletedAt
    )
    let insightDeletion = CloudDeletion(
      entityID: existingInsight.id,
      entityType: "SavedInsight",
      deletedAt: deletedAt
    )
    let container = try ModelContainer(
      for: SavedChart.self,
      SavedInsight.self,
      CloudDeletion.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    context.insert(existingChart)
    context.insert(existingInsight)
    context.insert(chartDeletion)
    context.insert(insightDeletion)
    try context.save()

    let suite = "BackupRestoreShortcutTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var cancelledIdentifiers: [String] = []

    _ = try BackupRestoreService.restore(
      payload.validated(),
      existingCharts: [existingChart],
      existingInsights: [existingInsight],
      modelContext: context,
      restoredAt: Date(timeIntervalSinceReferenceDate: 550_000_000),
      shortcutDefaults: defaults,
      cancelReminder: { identifier in
        if let identifier { cancelledIdentifiers.append(identifier) }
      }
    )

    let restoredChart = try XCTUnwrap(context.fetch(FetchDescriptor<SavedChart>()).first)
    let restoredInsight = try XCTUnwrap(context.fetch(FetchDescriptor<SavedInsight>()).first)
    XCTAssertGreaterThan(restoredChart.updatedAt, deletedAt)
    XCTAssertGreaterThan(restoredInsight.updatedAt, deletedAt)
    XCTAssertTrue(try context.fetch(FetchDescriptor<CloudDeletion>()).isEmpty)
    XCTAssertEqual(cancelledIdentifiers, ["review.old-device-request"])
    XCTAssertNil(restoredInsight.reminderIdentifier)
    XCTAssertEqual(
      defaults.string(forKey: PinnedChartShortcut.key),
      restoredChart.id.uuidString
    )
  }

  func test拒絕不同規則版本以免保留過期收藏依據() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var charts = try XCTUnwrap(object["charts"] as? [[String: Any]])
    charts[0]["ruleSetVersion"] = 0
    object["charts"] = charts
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      guard case .unsupportedChartRuleSet(_, let ruleSetID, let version) = error as? BackupError
      else {
        return XCTFail("預期拒絕不同排盤規則，實際為 \(error)")
      }
      XCTAssertEqual(ruleSetID, RuleSetIdentity.taiwanTraditionalSanheV1.id)
      XCTAssertEqual(version, 0)
    }
  }

  func test舊版備份缺少EvidenceSeedIDs時遷移為空陣列() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var insights = try XCTUnwrap(object["insights"] as? [[String: Any]])
    insights[0].removeValue(forKey: "evidenceSeedIDs")
    object["insights"] = insights
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    let payload = try EncryptedBackupService.restore(
      from: backupData,
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertTrue(try XCTUnwrap(payload.insights.first).evidenceSeedIDs.isEmpty)
  }

  func test拒絕無效EvidenceSeedID() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var insights = try XCTUnwrap(object["insights"] as? [[String: Any]])
    insights[0]["evidenceSeedIDs"] = ["seed.invalid"]
    object["insights"] = insights
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .invalidEvidenceSeedID)
    }
  }

  func test拒絕Seed與Fact皆有效但配對不一致() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var insights = try XCTUnwrap(object["insights"] as? [[String: Any]])
    insights[0]["evidenceFactIDs"] = ["natal.star.ziWei.palace"]
    object["insights"] = insights
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .invalidEvidenceFactID)
    }
  }

  func test拒絕無效EvidenceFactID() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var insights = try XCTUnwrap(object["insights"] as? [[String: Any]])
    insights[0]["evidenceFactIDs"] = ["natal.fake"]
    object["insights"] = insights
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      XCTAssertEqual(error as? BackupError, .invalidEvidenceFactID)
    }
  }

  func test拒絕Insight引用不存在的ChartID() throws {
    let fixture = try makeValidPayloadFixture()
    var object = fixture.object
    var insights = try XCTUnwrap(object["insights"] as? [[String: Any]])
    insights[0]["chartID"] = UUID().uuidString
    object["insights"] = insights
    let backupData = try seal(
      JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      recoveryKey: fixture.recoveryKey
    )

    XCTAssertThrowsError(
      try EncryptedBackupService.restore(
        from: backupData,
        recoveryKey: fixture.recoveryKey
      )
    ) { error in
      guard case .missingInsightChart = error as? BackupError else {
        return XCTFail("預期拒絕無效 insight 引用，實際為 \(error)")
      }
    }
  }

  private func makeSavedChart() throws -> SavedChart {
    let profile = BirthProfile(
      localDate: LocalDate(year: 1990, month: 6, day: 15),
      localTime: LocalTime(hour: 10, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    return SavedChart(
      id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      name: "測試命盤",
      birthProfileData: try BackupJSONCoding.encoder().encode(profile),
      ruleSetID: RuleSetIdentity.taiwanTraditionalSanheV1.id,
      ruleSetVersion: RuleSetIdentity.taiwanTraditionalSanheV1.version,
      appSchemaVersion: SavedChart.schemaVersion,
      chartCacheData: Data("這段衍生命盤快取不得匯出".utf8),
      createdAt: Date(timeIntervalSinceReferenceDate: 123_456_789.125),
      updatedAt: Date(timeIntervalSinceReferenceDate: 123_456_999.875)
    )
  }

  private func makeInsight(chartID: UUID) -> BackupInsightDTO {
    BackupInsightDTO(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      chartID: chartID,
      kind: "note",
      locationID: "palace.life",
      title: "私人筆記",
      body: "這段內容有共鳴。",
      marker: "resonates",
      evidenceSeedIDs: ["seed.personality.baseline"],
      evidenceFactIDs: ["natal.palace.life.branch"],
      createdAt: Date(timeIntervalSinceReferenceDate: 123_456_800.25),
      updatedAt: Date(timeIntervalSinceReferenceDate: 123_456_900.5)
    )
  }

  private func makeValidPayloadFixture() throws -> (
    object: [String: Any],
    recoveryKey: BackupRecoveryKey
  ) {
    let savedChart = try makeSavedChart()
    let payload = try BackupPayload(
      savedCharts: [savedChart],
      insights: [makeInsight(chartID: savedChart.id)]
    )
    let data = try BackupJSONCoding.encoder().encode(payload)
    return (
      try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]),
      BackupRecoveryKey()
    )
  }

  private func seal(
    _ payloadData: Data,
    recoveryKey: BackupRecoveryKey
  ) throws -> Data {
    let sealedBox = try AES.GCM.seal(
      payloadData,
      using: SymmetricKey(data: recoveryKey.rawRepresentation),
      authenticating: EncryptedBackupService.authenticatedData
    )
    let envelope = EncryptedBackupEnvelope(
      schemaVersion: EncryptedBackupEnvelope.currentSchemaVersion,
      algorithm: EncryptedBackupEnvelope.algorithm,
      sealedPayload: try XCTUnwrap(sealedBox.combined)
    )
    return try BackupJSONCoding.encoder().encode(envelope)
  }
}
