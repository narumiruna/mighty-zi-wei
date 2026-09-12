import SwiftData
import XCTest

@testable import MightyZiWei

@MainActor
final class ObservationBackupTests: XCTestCase {
  func testV3加密往返包含快照回顧而不含通知與完整對話() throws {
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "不得備份的通知識別碼"
    let review = ObservationTestSupport.review(observation: observation)
    let snapshot = try BackupExportSnapshot(
      savedCharts: [chart], savedInsights: [], savedObservations: [observation],
      savedReviews: [review])
    let backup = try EncryptedBackupService.makeBackup(snapshot)
    let restored = try EncryptedBackupService.restore(
      from: backup.data, recoveryKey: backup.recoveryKey)
    XCTAssertEqual(restored.schemaVersion, 3)
    XCTAssertEqual(restored.observations, [try ObservationPayload(observation)])
    XCTAssertEqual(restored.reviews, [try ObservationReviewPayload(review)])
    let json = try XCTUnwrap(String(data: JSONEncoder().encode(restored.payload), encoding: .utf8))
    for forbidden in [
      "reminderIdentifier", "不得備份的通知識別碼", "turnsData", "apiKey", "endpoint", "chartCacheData",
    ] {
      XCTAssertFalse(json.contains(forbidden))
    }
  }

  func testV1V2遷移及還原不刪除新觀察() throws {
    for version in [1, 2] {
      let container = try ObservationTestSupport.container()
      let context = ModelContext(container)
      let chart = try ObservationTestSupport.chart()
      let observation = try ObservationTestSupport.observation(chart: chart)
      let review = ObservationTestSupport.review(observation: observation)
      context.insert(chart)
      context.insert(observation)
      context.insert(review)
      try context.save()
      let payload = try BackupPayload(
        schemaVersion: version, charts: [BackupChartDTO(savedChart: chart)], insights: [])
      var object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
      object.removeValue(forKey: "observations")
      object.removeValue(forKey: "reviews")
      let decoded = try JSONDecoder().decode(
        BackupPayload.self, from: JSONSerialization.data(withJSONObject: object))
      _ = try BackupRestoreService.restore(
        decoded.validated(), existingCharts: [chart], existingInsights: [], modelContext: context,
        shortcutDefaults: nil)
      XCTAssertEqual(
        try context.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [observation.id])
      XCTAssertEqual(
        try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.id), [review.id])
    }
  }

  func test還原替換父命盤時移除未包含的不相容觀察與回顧() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "待取消提醒"
    let review = ObservationTestSupport.review(observation: observation)
    let originalObservationRevision = observation.modifiedAt
    context.insert(chart)
    context.insert(observation)
    context.insert(review)
    try context.save()
    let replacementProfile = BirthProfile(
      localDate: LocalDate(year: 1991, month: 7, day: 16),
      localTime: LocalTime(hour: 11, minute: 30),
      timeZoneIdentifier: "Asia/Taipei"
    )
    let ruleSet = RuleSetIdentity.taiwanTraditionalSanheV1
    let incomingChart = BackupChartDTO(
      id: chart.id,
      name: "替換後命盤",
      birthProfile: replacementProfile,
      ruleSetID: ruleSet.id,
      ruleSetVersion: ruleSet.version,
      appSchemaVersion: SavedChart.schemaVersion,
      createdAt: chart.createdAt,
      updatedAt: chart.updatedAt
    )
    let payload = try BackupPayload(charts: [incomingChart], insights: []).validated()
    var cancelled: [String] = []

    _ = try BackupRestoreService.restore(
      payload,
      existingCharts: [chart],
      existingInsights: [],
      modelContext: context,
      restoredAt: Date.now.addingTimeInterval(60),
      shortcutDefaults: nil,
      cancelReminder: { identifier in
        if let identifier { cancelled.append(identifier) }
      }
    )

    XCTAssertEqual(try chart.birthProfile(), replacementProfile)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservation>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<SavedObservationReview>()).isEmpty)
    let deletions = try context.fetch(FetchDescriptor<CloudDeletion>())
    XCTAssertEqual(
      deletions.filter { $0.entityType == RecordType.observation }.map(\.entityID),
      [observation.id]
    )
    XCTAssertEqual(
      deletions.filter { $0.entityType == RecordType.review }.map(\.entityID),
      [review.id]
    )
    XCTAssertGreaterThan(
      try XCTUnwrap(deletions.first { $0.entityID == observation.id }).deletedAt,
      originalObservationRevision
    )
    XCTAssertEqual(cancelled, ["待取消提醒"])
  }

  func test還原替換父命盤時保留依據仍相容的觀察與回顧() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "應保留提醒"
    let review = ObservationTestSupport.review(observation: observation)
    context.insert(chart)
    context.insert(observation)
    context.insert(review)
    try context.save()
    let originalProfile = try chart.birthProfile()
    let replacementProfile = BirthProfile(
      localDate: originalProfile.localDate,
      localTime: LocalTime(
        hour: originalProfile.localTime.hour,
        minute: originalProfile.localTime.minute + 1
      ),
      calendarIdentifier: originalProfile.calendarIdentifier,
      timeZoneIdentifier: originalProfile.timeZoneIdentifier
    )
    let incomingChart = BackupChartDTO(
      id: chart.id,
      name: "同時辰替換命盤",
      birthProfile: replacementProfile,
      ruleSetID: chart.ruleSetID,
      ruleSetVersion: chart.ruleSetVersion,
      appSchemaVersion: SavedChart.schemaVersion,
      createdAt: chart.createdAt,
      updatedAt: chart.updatedAt
    )
    let payload = try BackupPayload(charts: [incomingChart], insights: []).validated()
    var cancelled: [String] = []

    _ = try BackupRestoreService.restore(
      payload,
      existingCharts: [chart],
      existingInsights: [],
      modelContext: context,
      shortcutDefaults: nil,
      cancelReminder: { identifier in
        if let identifier { cancelled.append(identifier) }
      }
    )

    XCTAssertEqual(try chart.birthProfile(), replacementProfile)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [observation.id]
    )
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservationReview>()).map(\.id), [review.id]
    )
    XCTAssertTrue(try context.fetch(FetchDescriptor<CloudDeletion>()).isEmpty)
    XCTAssertTrue(cancelled.isEmpty)
  }

  func test未知版本缺少集合重複ID及孤兒回顧全部拒絕() throws {
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let review = ObservationTestSupport.review(observation: observation)
    let payload = try ObservationTestSupport.payload(
      chart: chart, observations: [observation], reviews: [review])
    XCTAssertThrowsError(
      try ObservationTestSupport.changing(payload, key: "schemaVersion", to: 999))
    XCTAssertThrowsError(try ObservationTestSupport.changing(payload, key: "observations", to: nil))
    let duplicate = try ObservationTestSupport.payload(
      chart: chart, observations: [observation, observation])
    XCTAssertThrowsError(try duplicate.validate()) { error in
      XCTAssertEqual(error as? ObservationError, .duplicateID)
    }
    let orphan = try ObservationTestSupport.payload(
      chart: chart, observations: [], reviews: [review])
    XCTAssertThrowsError(try orphan.validate()) { error in
      XCTAssertEqual(error as? ObservationError, .missingParent)
    }
    let duplicateReviews = try ObservationTestSupport.payload(
      chart: chart, observations: [observation], reviews: [review, review])
    XCTAssertThrowsError(try duplicateReviews.validate())
  }

  func test備份觀察快照規則與Fact必須符合父命盤() throws {
    let chart = try ObservationTestSupport.chart()
    let snapshot = try ObservationTestSupport.snapshot(chart: chart)
    let wrongRuleSetSnapshot = ObservationSnapshot(
      selectedText: snapshot.selectedText,
      initialThought: snapshot.initialThought,
      source: snapshot.source,
      locationID: snapshot.locationID,
      contentVersion: snapshot.contentVersion,
      ruleSetID: "其他規則",
      ruleSetVersion: snapshot.ruleSetVersion,
      facts: snapshot.facts,
      seeds: snapshot.seeds
    )
    let fact = try XCTUnwrap(snapshot.facts.first)
    let forgedFact = ChartFact(
      id: fact.id,
      category: fact.category,
      subject: fact.subject,
      value: fact.value,
      displayText: "不是父命盤重新計算出的事實"
    )
    let wrongFactSnapshot = ObservationSnapshot(
      selectedText: snapshot.selectedText,
      initialThought: snapshot.initialThought,
      source: snapshot.source,
      locationID: snapshot.locationID,
      contentVersion: snapshot.contentVersion,
      ruleSetID: snapshot.ruleSetID,
      ruleSetVersion: snapshot.ruleSetVersion,
      facts: [forgedFact] + Array(snapshot.facts.dropFirst()),
      seeds: snapshot.seeds
    )
    let seed = try XCTUnwrap(snapshot.seeds.first)
    let forgedSeed = InterpretationSeed(
      id: "\(seed.id).forged",
      category: seed.category,
      meaning: "不是父命盤 builder 產生的解讀",
      evidenceFactIDs: seed.evidenceFactIDs
    )
    let wrongSeedSnapshot = ObservationSnapshot(
      selectedText: forgedSeed.meaning,
      initialThought: snapshot.initialThought,
      source: snapshot.source,
      locationID: "interpretation.\(forgedSeed.id)",
      contentVersion: snapshot.contentVersion,
      ruleSetID: snapshot.ruleSetID,
      ruleSetVersion: snapshot.ruleSetVersion,
      facts: snapshot.facts,
      seeds: [forgedSeed]
    )

    for invalidSnapshot in [wrongRuleSetSnapshot, wrongFactSnapshot, wrongSeedSnapshot] {
      try invalidSnapshot.validate()
      let observation = try SavedObservation(chartID: chart.id, snapshot: invalidSnapshot)
      let payload = try ObservationTestSupport.payload(chart: chart, observations: [observation])
      XCTAssertThrowsError(try payload.validate()) { error in
        XCTAssertEqual(error as? ObservationError, .invalidSnapshot)
      }
    }
  }

  func test歷史內容版本允許Fact顯示文案更新但仍核對結構化依據() throws {
    let chart = try ObservationTestSupport.chart()
    let snapshot = try ObservationTestSupport.snapshot(chart: chart)
    let fact = try XCTUnwrap(snapshot.facts.first)
    let archivedFact = ChartFact(
      id: fact.id,
      category: fact.category,
      subject: fact.subject,
      value: fact.value,
      displayText: "舊版保存的顯示文案"
    )
    let archivedSnapshot = ObservationSnapshot(
      selectedText: snapshot.selectedText,
      initialThought: snapshot.initialThought,
      source: snapshot.source,
      locationID: snapshot.locationID,
      contentVersion: "歷史內容版本",
      ruleSetID: snapshot.ruleSetID,
      ruleSetVersion: snapshot.ruleSetVersion,
      facts: [archivedFact] + Array(snapshot.facts.dropFirst()),
      seeds: snapshot.seeds
    )
    let observation = try SavedObservation(chartID: chart.id, snapshot: archivedSnapshot)
    let payload = try ObservationTestSupport.payload(chart: chart, observations: [observation])

    XCTAssertNoThrow(try payload.validate())
  }

  func test父命盤Evidence有重複FactID時安全比對失敗() throws {
    let chart = try ObservationTestSupport.chart()
    let snapshot = try ObservationTestSupport.snapshot(chart: chart)
    let fact = try XCTUnwrap(snapshot.facts.first)
    let evidence = ObservationParentChartEvidence(
      ruleSetID: chart.ruleSetID,
      ruleSetVersion: chart.ruleSetVersion,
      facts: snapshot.facts + [fact]
    )

    XCTAssertFalse(evidence.matches(snapshot))
  }

  func test不可變內容衝突在修改命盤或取消提醒前拒絕() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    observation.reminderIdentifier = "有效舊提醒"
    context.insert(chart)
    context.insert(observation)
    try context.save()
    let different = try ObservationTestSupport.observation(
      chart: chart, id: observation.id, thought: "不能覆寫")
    let payload = try ObservationTestSupport.payload(chart: chart, observations: [different])
      .validated()
    var cancelled: [String?] = []
    XCTAssertThrowsError(
      try BackupRestoreService.restore(
        payload, existingCharts: [chart], existingInsights: [], modelContext: context,
        shortcutDefaults: nil, cancelReminder: { cancelled.append($0) }
      )
    ) { error in XCTAssertEqual(error as? ObservationError, .immutableConflict) }
    XCTAssertEqual(observation.snapshot?.initialThought, "原始想法不可覆寫")
    XCTAssertEqual(observation.reminderIdentifier, "有效舊提醒")
    XCTAssertTrue(cancelled.isEmpty)
  }

  func testSave失敗回復命盤筆記快照Tombstone且不取消提醒() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let chart = try ObservationTestSupport.chart()
    let originalName = chart.name
    let note = SavedInsight(
      chartID: chart.id, kind: .note, locationID: "chart.general", title: "舊筆記", content: "仍應保留",
      reminderIdentifier: "有效提醒")
    let observation = try ObservationTestSupport.observation(chart: chart)
    context.insert(chart)
    context.insert(note)
    context.insert(observation)
    let deletion = CloudDeletion(entityID: chart.id, entityType: "SavedChart")
    context.insert(deletion)
    try context.save()
    let incoming = try ObservationTestSupport.observation(chart: chart)
    let payload = try ObservationTestSupport.payload(chart: chart, observations: [incoming])
      .validated()
    var cancelled = false
    XCTAssertThrowsError(
      try BackupRestoreService.restore(
        payload, existingCharts: [chart], existingInsights: [note], modelContext: context,
        shortcutDefaults: nil, cancelReminder: { _ in cancelled = true },
        save: { _ in throw ObservationTestSupport.Failure.simulated }
      ))
    let reloaded = ModelContext(container)
    XCTAssertEqual(try reloaded.fetch(FetchDescriptor<SavedChart>()).first?.name, originalName)
    XCTAssertEqual(try reloaded.fetch(FetchDescriptor<SavedInsight>()).first?.content, "仍應保留")
    XCTAssertEqual(
      try reloaded.fetch(FetchDescriptor<SavedObservation>()).map(\.id), [observation.id])
    XCTAssertEqual(try reloaded.fetch(FetchDescriptor<CloudDeletion>()).count, 1)
    XCTAssertFalse(cancelled)
  }

  func test還原相同內容時保留較新的傳入修改時間() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let snapshot = try ObservationTestSupport.snapshot(chart: chart)
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let localModifiedAt = createdAt.addingTimeInterval(60)
    let restoredAt = createdAt.addingTimeInterval(120)
    let incomingModifiedAt = createdAt.addingTimeInterval(180)
    let observationID = UUID()
    let reviewID = UUID()
    let localObservation = try SavedObservation(
      id: observationID,
      chartID: chart.id,
      snapshot: snapshot,
      createdAt: createdAt,
      modifiedAt: localModifiedAt
    )
    let localReview = SavedObservationReview(
      id: reviewID,
      observationID: observationID,
      chartID: chart.id,
      content: "同一份回顧",
      outcome: .matches,
      createdAt: createdAt,
      modifiedAt: localModifiedAt
    )
    context.insert(chart)
    context.insert(localObservation)
    context.insert(localReview)
    try context.save()
    let incomingObservation = try SavedObservation(
      id: observationID,
      chartID: chart.id,
      snapshot: snapshot,
      createdAt: createdAt,
      modifiedAt: incomingModifiedAt
    )
    let incomingReview = SavedObservationReview(
      id: reviewID,
      observationID: observationID,
      chartID: chart.id,
      content: "同一份回顧",
      outcome: .matches,
      createdAt: createdAt,
      modifiedAt: incomingModifiedAt
    )
    let payload = try ObservationTestSupport.payload(
      chart: chart,
      observations: [incomingObservation],
      reviews: [incomingReview]
    ).validated()

    _ = try BackupRestoreService.restore(
      payload,
      existingCharts: [chart],
      existingInsights: [],
      modelContext: context,
      restoredAt: restoredAt,
      shortcutDefaults: nil
    )

    XCTAssertEqual(localObservation.modifiedAt, incomingModifiedAt)
    XCTAssertEqual(localReview.modifiedAt, incomingModifiedAt)
  }

  func test同一備份重試不重複回顧且不覆寫既有原文() throws {
    let container = try ObservationTestSupport.container()
    let context = ModelContext(container)
    let chart = try ObservationTestSupport.chart()
    let observation = try ObservationTestSupport.observation(chart: chart)
    let review = ObservationTestSupport.review(observation: observation)
    context.insert(chart)
    try context.save()
    let payload = try ObservationTestSupport.payload(
      chart: chart, observations: [observation], reviews: [review]
    ).validated()
    for _ in 0..<2 {
      _ = try BackupRestoreService.restore(
        payload, existingCharts: [chart], existingInsights: [], modelContext: context,
        shortcutDefaults: nil)
    }
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservation>()).count, 1)
    XCTAssertEqual(try context.fetch(FetchDescriptor<SavedObservationReview>()).count, 1)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<SavedObservation>()).first?.snapshot, observation.snapshot)
  }
}
