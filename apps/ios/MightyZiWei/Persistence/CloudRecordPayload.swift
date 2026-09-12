import CloudKit
import Foundation

enum RecordType {
  static let chart = "SavedChart"
  static let insight = "SavedInsight"
  static let deletion = "DeletedRecord"
  static let observation = "SavedObservation"
  static let review = "SavedObservationReview"
  static let observationDeletion = "ObservationDeletedRecord"
}

typealias DeletionKey = CloudEntityKey

struct CloudEntityKey: Hashable {
  let type: String
  let id: UUID
}

struct CloudContentRecordReference: Equatable, Sendable {
  let recordType: String
  let recordName: String

  init?(entityType: String, entityID: UUID) {
    guard entityType == RecordType.chart || entityType == RecordType.insight else {
      return nil
    }
    recordType = entityType
    recordName = entityID.uuidString
  }
}

struct CloudChartPayload: Codable {
  let id: UUID
  let name: String
  let profile: BirthProfile
  let ruleSetID: String
  let ruleSetVersion: Int
  let appSchemaVersion: Int
  let tags: [String]
  let isPinned: Bool
  let createdAt: Date
  let updatedAt: Date

  init(_ chart: SavedChart) throws {
    id = chart.id
    name = chart.name
    profile = try chart.birthProfile()
    ruleSetID = chart.ruleSetID
    ruleSetVersion = chart.ruleSetVersion
    appSchemaVersion = chart.appSchemaVersion
    tags = chart.tags
    isPinned = chart.isPinned
    createdAt = chart.createdAt
    updatedAt = chart.updatedAt
  }

  init?(record: CKRecord) {
    guard let data = record["payload"] as? Data,
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self = value
  }

  func validate() throws {
    let current = RuleSetIdentity.taiwanTraditionalSanheV1
    guard ruleSetID == current.id,
      ruleSetVersion == current.version,
      appSchemaVersion == SavedChart.schemaVersion,
      (try? ZiWeiCalculator().calculate(profile)) != nil
    else {
      throw ICloudSyncService.SyncError.invalidRemoteData
    }
  }

  func record(existing: CKRecord? = nil) throws -> CKRecord {
    let record =
      existing
      ?? CKRecord(
        recordType: RecordType.chart,
        recordID: CKRecord.ID(recordName: id.uuidString)
      )
    record["payload"] = try JSONEncoder().encode(self)
    return record
  }

  func makeModel() throws -> SavedChart {
    SavedChart(
      id: id,
      name: name,
      birthProfileData: try JSONEncoder().encode(profile),
      ruleSetID: ruleSetID,
      ruleSetVersion: ruleSetVersion,
      appSchemaVersion: appSchemaVersion,
      chartCacheData: nil,
      tags: tags,
      isPinned: isPinned,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  func apply(to chart: SavedChart) throws {
    chart.name = name
    chart.birthProfileData = try JSONEncoder().encode(profile)
    chart.ruleSetID = ruleSetID
    chart.ruleSetVersion = ruleSetVersion
    chart.appSchemaVersion = appSchemaVersion
    chart.chartCacheData = nil
    chart.tags = tags
    chart.isPinned = isPinned
    chart.createdAt = createdAt
    chart.updatedAt = updatedAt
  }
}

struct CloudInsightPayload: Codable {
  let id: UUID
  let chartID: UUID
  let kind: String
  let locationID: String
  let title: String
  let content: String
  let marker: String
  let evidenceSeedIDs: [String]
  let evidenceFactIDs: [String]
  let contentVersion: String?
  let reviewDate: Date?
  let createdAt: Date
  let updatedAt: Date

  init(_ insight: SavedInsight) {
    id = insight.id
    chartID = insight.chartID
    kind = insight.kindRawValue
    locationID = insight.locationID
    title = insight.title
    content = insight.content
    marker = insight.markerRawValue
    evidenceSeedIDs = insight.evidenceSeedIDs
    evidenceFactIDs = insight.evidenceFactIDs
    contentVersion = insight.interpretationContentVersion
    reviewDate = insight.reviewDate
    createdAt = insight.createdAt
    updatedAt = insight.updatedAt
  }

  init?(record: CKRecord) {
    guard let data = record["payload"] as? Data,
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self = value
  }

  var isStructurallyValid: Bool {
    SavedInsight.Kind(rawValue: kind) != nil
      && SavedInsight.Marker(rawValue: marker) != nil
      && !locationID.isEmpty
  }

  func hasValidEvidence(
    seeds: [InterpretationSeed],
    validFactIDs: Set<String>
  ) -> Bool {
    PersistedInterpretationEvidenceValidator().isValid(
      seedIDs: evidenceSeedIDs,
      factIDs: evidenceFactIDs,
      seeds: seeds,
      validFactIDs: validFactIDs
    )
  }

  func record(existing: CKRecord? = nil) throws -> CKRecord {
    let record =
      existing
      ?? CKRecord(
        recordType: RecordType.insight,
        recordID: CKRecord.ID(recordName: id.uuidString)
      )
    record["payload"] = try JSONEncoder().encode(self)
    return record
  }

  func makeModel() -> SavedInsight {
    SavedInsight(
      id: id,
      chartID: chartID,
      kind: SavedInsight.Kind(rawValue: kind) ?? .note,
      locationID: locationID,
      title: title,
      content: content,
      marker: SavedInsight.Marker(rawValue: marker) ?? .none,
      evidenceSeedIDs: evidenceSeedIDs,
      evidenceFactIDs: evidenceFactIDs,
      interpretationContentVersion: contentVersion,
      reviewDate: reviewDate,
      reminderIdentifier: nil,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  func apply(to insight: SavedInsight) {
    insight.chartID = chartID
    insight.kindRawValue = kind
    insight.locationID = locationID
    insight.title = title
    insight.content = content
    insight.markerRawValue = marker
    insight.setEvidence(
      seedIDs: evidenceSeedIDs,
      factIDs: evidenceFactIDs,
      contentVersion: contentVersion
    )
    insight.reviewDate = reviewDate
    insight.createdAt = createdAt
    insight.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case chartID
    case kind
    case locationID
    case title
    case content
    case marker
    case evidenceSeedIDs
    case evidenceFactIDs
    case contentVersion
    case reviewDate
    case createdAt
    case updatedAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    chartID = try container.decode(UUID.self, forKey: .chartID)
    kind = try container.decode(String.self, forKey: .kind)
    locationID = try container.decode(String.self, forKey: .locationID)
    title = try container.decode(String.self, forKey: .title)
    content = try container.decode(String.self, forKey: .content)
    marker = try container.decode(String.self, forKey: .marker)
    evidenceSeedIDs =
      try container.decodeIfPresent(
        [String].self,
        forKey: .evidenceSeedIDs
      ) ?? []
    evidenceFactIDs = try container.decode([String].self, forKey: .evidenceFactIDs)
    contentVersion = try container.decodeIfPresent(String.self, forKey: .contentVersion)
    reviewDate = try container.decodeIfPresent(Date.self, forKey: .reviewDate)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
  }
}

struct CloudDeletionPayload: Codable {
  let id: UUID
  let entityID: UUID
  let entityType: String
  let deletedAt: Date

  init(_ deletion: CloudDeletion) {
    id = deletion.id
    entityID = deletion.entityID
    entityType = deletion.entityType
    deletedAt = deletion.deletedAt
  }

  init?(record: CKRecord) {
    guard let data = record["payload"] as? Data,
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self = value
  }

  var isValid: Bool {
    entityType == RecordType.chart || entityType == RecordType.insight
  }

  func record(existing: CKRecord? = nil) throws -> CKRecord {
    let record =
      existing
      ?? CKRecord(
        recordType: RecordType.deletion,
        recordID: CKRecord.ID(recordName: "\(entityType)-\(entityID.uuidString)")
      )
    record["payload"] = try JSONEncoder().encode(self)
    return record
  }

  func makeModel() -> CloudDeletion {
    CloudDeletion(
      id: id,
      entityID: entityID,
      entityType: entityType,
      deletedAt: deletedAt
    )
  }
}
