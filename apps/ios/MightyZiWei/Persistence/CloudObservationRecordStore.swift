import CloudKit
import Foundation

struct CloudObservationState: Sendable {
  var observations: [ObservationPayload] = []
  var reviews: [ObservationReviewPayload] = []
  var deletions: [CloudObservationDeletion] = []
}

struct CloudObservationDeletion: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let entityID: UUID
  let entityType: String
  let deletedAt: Date

  init(entityID: UUID, entityType: String, deletedAt: Date) {
    schemaVersion = 1
    self.entityID = entityID
    self.entityType = entityType
    self.deletedAt = deletedAt
  }

  func validate() throws {
    guard schemaVersion == 1 else { throw ObservationError.unsupportedSchema(schemaVersion) }
    guard entityType == RecordType.observation || entityType == RecordType.review else {
      throw ICloudSyncService.SyncError.invalidRemoteData
    }
  }
}

@MainActor
protocol CloudObservationRecordStoring {
  func fetch() async throws -> CloudObservationState
  func saveObservation(_ payload: ObservationPayload) async throws
  func saveReview(_ payload: ObservationReviewPayload) async throws
  func saveDeletion(_ payload: CloudObservationDeletion) async throws
  func deleteRecord(type: String, id: UUID) async throws
}

@MainActor
final class CloudObservationRecordStore: CloudObservationRecordStoring {
  private let database: CKDatabase
  private var existingRecords: [String: CKRecord] = [:]

  init(database: CKDatabase) { self.database = database }

  func fetch() async throws -> CloudObservationState {
    existingRecords.removeAll()
    return try await CloudObservationState(
      observations: fetchPayloads(type: RecordType.observation),
      reviews: fetchPayloads(type: RecordType.review),
      deletions: fetchPayloads(type: RecordType.observationDeletion)
    )
  }

  func saveObservation(_ payload: ObservationPayload) async throws {
    try await save(
      payload, type: RecordType.observation,
      name: Self.recordName(type: RecordType.observation, id: payload.id))
  }

  func saveReview(_ payload: ObservationReviewPayload) async throws {
    try await save(
      payload, type: RecordType.review,
      name: Self.recordName(type: RecordType.review, id: payload.id))
  }

  func saveDeletion(_ payload: CloudObservationDeletion) async throws {
    try await save(
      payload, type: RecordType.observationDeletion,
      name: "ObservationDeleted-\(payload.entityType)-\(payload.entityID.uuidString)"
    )
  }

  func deleteRecord(type: String, id: UUID) async throws {
    do {
      try await database.deleteRecord(
        withID: CKRecord.ID(recordName: Self.recordName(type: type, id: id)))
    } catch let error as CKError where error.code == .unknownItem {
      // 固定識別碼的冪等刪除。
    }
  }

  static func recordName(type: String, id: UUID) -> String { "\(type)-\(id.uuidString)" }

  private func save(_ payload: some Encodable, type: String, name: String) async throws {
    let record =
      existingRecords[name] ?? CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name))
    record["payload"] = try JSONEncoder().encode(payload)
    existingRecords[name] = try await database.save(record)
  }

  private func fetchPayloads<Payload: Decodable>(type: String) async throws -> [Payload] {
    var values: [Payload] = []
    var cursor: CKQueryOperation.Cursor?
    repeat {
      let result: ([(CKRecord.ID, Result<CKRecord, any Error>)], CKQueryOperation.Cursor?)
      if let cursor {
        result = try await database.records(continuingMatchFrom: cursor)
      } else {
        result = try await database.records(
          matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)))
      }
      for (_, value) in result.0 {
        let record = try value.get()
        guard let data = record["payload"] as? Data else {
          throw ICloudSyncService.SyncError.invalidRemoteData
        }
        values.append(try JSONDecoder().decode(Payload.self, from: data))
        existingRecords[record.recordID.recordName] = record
      }
      cursor = result.1
    } while cursor != nil
    return values
  }
}
