import CloudKit
import Foundation
import SwiftData

enum CloudConflictWinner: Equatable, Sendable {
    case local
    case remote
}

struct CloudConflictResolver: Sendable {
    func isDeleted(contentUpdatedAt: Date, deletedAt: Date?) -> Bool {
        guard let deletedAt else { return false }
        return deletedAt >= contentUpdatedAt
    }

    func winner(localUpdatedAt: Date, remoteUpdatedAt: Date) -> CloudConflictWinner {
        remoteUpdatedAt > localUpdatedAt ? .remote : .local
    }
}

struct ICloudSyncResult: Equatable, Sendable {
    let uploadedCount: Int
    let downloadedCount: Int
    let conflictCount: Int
}

@MainActor
final class ICloudSyncService {
    static let enabledKey = "icloud.sync.enabled"

    enum SyncError: LocalizedError {
        case iCloudUnavailable
        case invalidRemoteData

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                "目前無法使用私人 iCloud 資料庫。請確認已登入 iCloud 並允許此 App 使用 iCloud。"
            case .invalidRemoteData:
                "iCloud 中有無法驗證的同步資料，因此未套用該筆內容。"
            }
        }
    }

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init(container: CKContainer = .default()) {
        self.container = container
    }

    func sync(
        charts: [SavedChart],
        insights: [SavedInsight],
        deletions: [CloudDeletion],
        modelContext: ModelContext
    ) async throws -> ICloudSyncResult {
        guard try await container.accountStatus() == .available else {
            throw SyncError.iCloudUnavailable
        }

        let deletionRecords = try await fetchRecords(type: RecordType.deletion)
        let chartRecords = try await fetchRecords(type: RecordType.chart)
        let insightRecords = try await fetchRecords(type: RecordType.insight)
        let remoteDeletions = deletionRecords.compactMap(CloudDeletionPayload.init(record:))
        let remoteCharts = chartRecords.compactMap(CloudChartPayload.init(record:))
        let remoteInsights = insightRecords.compactMap(CloudInsightPayload.init(record:))
        guard remoteDeletions.count == deletionRecords.count,
              remoteCharts.count == chartRecords.count,
              remoteInsights.count == insightRecords.count,
              Set(remoteCharts.map(\.id)).count == remoteCharts.count,
              Set(remoteInsights.map(\.id)).count == remoteInsights.count,
              Set(remoteDeletions.map {
                  DeletionKey(type: $0.entityType, id: $0.entityID)
              }).count == remoteDeletions.count,
              remoteDeletions.allSatisfy(\.isValid) else {
            throw SyncError.invalidRemoteData
        }
        try remoteCharts.forEach { try $0.validate() }
        let chartRecordsByID = Dictionary(
            uniqueKeysWithValues: zip(remoteCharts, chartRecords).map { ($0.id, $1) }
        )
        let insightRecordsByID = Dictionary(
            uniqueKeysWithValues: zip(remoteInsights, insightRecords).map { ($0.id, $1) }
        )
        let deletionRecordsByKey = Dictionary(
            uniqueKeysWithValues: zip(remoteDeletions, deletionRecords).map {
                (DeletionKey(type: $0.entityType, id: $0.entityID), $1)
            }
        )
        var uploaded = 0
        var downloaded = 0
        var conflicts = 0
        var reminderIdentifiersToCancel = Set<String>()

        var allDeletions: [DeletionKey: CloudDeletion] = [:]
        for deletion in deletions {
            let key = DeletionKey(type: deletion.entityType, id: deletion.entityID)
            if allDeletions[key]?.deletedAt ?? .distantPast < deletion.deletedAt {
                allDeletions[key] = deletion
            }
        }
        for payload in remoteDeletions {
            let key = DeletionKey(type: payload.entityType, id: payload.entityID)
            if let existing = allDeletions[key] {
                if payload.deletedAt > existing.deletedAt {
                    existing.deletedAt = payload.deletedAt
                    downloaded += 1
                }
            } else {
                let deletion = payload.makeModel()
                modelContext.insert(deletion)
                allDeletions[key] = deletion
                downloaded += 1
            }
        }

        var chartsByID = Dictionary(uniqueKeysWithValues: charts.map { ($0.id, $0) })
        for remote in remoteCharts {
            let tombstone = allDeletions[DeletionKey(type: RecordType.chart, id: remote.id)]
            if CloudConflictResolver().isDeleted(
                contentUpdatedAt: remote.updatedAt,
                deletedAt: tombstone?.deletedAt
            ) {
                if let local = chartsByID.removeValue(forKey: remote.id) {
                    insights.filter { $0.chartID == local.id }.forEach { insight in
                        if let identifier = insight.reminderIdentifier {
                            reminderIdentifiersToCancel.insert(identifier)
                        }
                        modelContext.delete(insight)
                    }
                    modelContext.delete(local)
                    downloaded += 1
                }
                continue
            }
            if let local = chartsByID[remote.id] {
                if CloudConflictResolver().winner(
                    localUpdatedAt: local.updatedAt,
                    remoteUpdatedAt: remote.updatedAt
                ) == .remote {
                    try remote.apply(to: local)
                    downloaded += 1
                    conflicts += 1
                } else if local.updatedAt > remote.updatedAt {
                    try await database.save(try CloudChartPayload(local).record(
                        existing: chartRecordsByID[remote.id]
                    ))
                    uploaded += 1
                    conflicts += 1
                }
            } else {
                let local = try remote.makeModel()
                modelContext.insert(local)
                chartsByID[local.id] = local
                downloaded += 1
            }
        }
        let remoteChartIDs = Set(remoteCharts.map(\.id))
        for chart in charts where !remoteChartIDs.contains(chart.id) {
            let tombstone = allDeletions[DeletionKey(type: RecordType.chart, id: chart.id)]
            guard tombstone == nil || tombstone!.deletedAt < chart.updatedAt else { continue }
            try await database.save(try CloudChartPayload(chart).record())
            uploaded += 1
        }

        var insightsByID = Dictionary(uniqueKeysWithValues: insights.map { ($0.id, $0) })
        for remote in remoteInsights {
            guard remote.isStructurallyValid else { throw SyncError.invalidRemoteData }
            let tombstone = allDeletions[DeletionKey(type: RecordType.insight, id: remote.id)]
            if CloudConflictResolver().isDeleted(
                contentUpdatedAt: remote.updatedAt,
                deletedAt: tombstone?.deletedAt
            ) {
                if let local = insightsByID.removeValue(forKey: remote.id) {
                    if let identifier = local.reminderIdentifier {
                        reminderIdentifiersToCancel.insert(identifier)
                    }
                    modelContext.delete(local)
                    downloaded += 1
                }
                continue
            }
            guard let linkedChart = chartsByID[remote.chartID] else { continue }
            let validFactIDs = Set(
                ChartFactBuilder().makeFacts(from: try linkedChart.resolvedChart()).map(\.id)
            )
            guard remote.evidenceFactIDs.allSatisfy(validFactIDs.contains) else {
                throw SyncError.invalidRemoteData
            }
            if let local = insightsByID[remote.id] {
                if CloudConflictResolver().winner(
                    localUpdatedAt: local.updatedAt,
                    remoteUpdatedAt: remote.updatedAt
                ) == .remote {
                    if let identifier = local.reminderIdentifier {
                        reminderIdentifiersToCancel.insert(identifier)
                    }
                    remote.apply(to: local)
                    downloaded += 1
                    conflicts += 1
                } else if local.updatedAt > remote.updatedAt {
                    try await database.save(CloudInsightPayload(local).record(
                        existing: insightRecordsByID[remote.id]
                    ))
                    uploaded += 1
                    conflicts += 1
                }
            } else {
                let local = remote.makeModel()
                modelContext.insert(local)
                insightsByID[local.id] = local
                downloaded += 1
            }
        }
        let remoteInsightIDs = Set(remoteInsights.map(\.id))
        for insight in insights where
            !remoteInsightIDs.contains(insight.id) && chartsByID[insight.chartID] != nil {
            let tombstone = allDeletions[DeletionKey(type: RecordType.insight, id: insight.id)]
            guard tombstone == nil || tombstone!.deletedAt < insight.updatedAt else { continue }
            try await database.save(CloudInsightPayload(insight).record())
            uploaded += 1
        }

        for (key, deletion) in allDeletions {
            try await database.save(CloudDeletionPayload(deletion).record(
                existing: deletionRecordsByKey[key]
            ))
            uploaded += 1
            if deletionWins(
                key: key,
                deletion: deletion,
                chartsByID: chartsByID,
                insightsByID: insightsByID
            ) {
                try await deleteContentRecord(for: key)
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        reminderIdentifiersToCancel.forEach {
            ReviewReminderScheduler().cancel(identifier: $0)
        }
        return ICloudSyncResult(
            uploadedCount: uploaded,
            downloadedCount: downloaded,
            conflictCount: conflicts
        )
    }

    static func recordDeletion(
        entityID: UUID,
        entityType: String,
        modelContext: ModelContext
    ) {
        modelContext.insert(CloudDeletion(
            entityID: entityID,
            entityType: entityType
        ))
    }

    private func deletionWins(
        key: DeletionKey,
        deletion: CloudDeletion,
        chartsByID: [UUID: SavedChart],
        insightsByID: [UUID: SavedInsight]
    ) -> Bool {
        let contentUpdatedAt: Date?
        switch key.type {
        case RecordType.chart:
            contentUpdatedAt = chartsByID[key.id]?.updatedAt
        case RecordType.insight:
            contentUpdatedAt = insightsByID[key.id]?.updatedAt
        default:
            return false
        }
        guard let contentUpdatedAt else { return true }
        return CloudConflictResolver().isDeleted(
            contentUpdatedAt: contentUpdatedAt,
            deletedAt: deletion.deletedAt
        )
    }

    private func deleteContentRecord(for key: DeletionKey) async throws {
        guard let reference = CloudContentRecordReference(
            entityType: key.type,
            entityID: key.id
        ) else {
            throw SyncError.invalidRemoteData
        }
        do {
            try await database.deleteRecord(
                withID: CKRecord.ID(recordName: reference.recordName)
            )
        } catch let error as CKError where error.code == .unknownItem {
            // 已刪除的內容視為成功，保留 tombstone 供其他裝置同步。
        }
    }

    private func fetchRecords(type: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let result: ([(CKRecord.ID, Result<CKRecord, any Error>)], CKQueryOperation.Cursor?)
            if let cursor {
                result = try await database.records(continuingMatchFrom: cursor)
            } else {
                result = try await database.records(
                    matching: CKQuery(recordType: type, predicate: NSPredicate(value: true))
                )
            }
            for (_, recordResult) in result.0 {
                switch recordResult {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    throw error
                }
            }
            cursor = result.1
        } while cursor != nil
        return records
    }
}

private enum RecordType {
    static let chart = "SavedChart"
    static let insight = "SavedInsight"
    static let deletion = "DeletedRecord"
}

private struct DeletionKey: Hashable {
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

private struct CloudChartPayload: Codable {
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
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    func validate() throws {
        let current = RuleSetIdentity.taiwanTraditionalSanheV1
        guard ruleSetID == current.id,
              ruleSetVersion == current.version,
              appSchemaVersion == SavedChart.schemaVersion,
              (try? ZiWeiCalculator().calculate(profile)) != nil else {
            throw ICloudSyncService.SyncError.invalidRemoteData
        }
    }

    func record(existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(
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

private struct CloudInsightPayload: Codable {
    let id: UUID
    let chartID: UUID
    let kind: String
    let locationID: String
    let title: String
    let content: String
    let marker: String
    let evidenceFactIDs: [String]
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
        evidenceFactIDs = insight.evidenceFactIDs
        reviewDate = insight.reviewDate
        createdAt = insight.createdAt
        updatedAt = insight.updatedAt
    }

    init?(record: CKRecord) {
        guard let data = record["payload"] as? Data,
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    var isStructurallyValid: Bool {
        SavedInsight.Kind(rawValue: kind) != nil
            && SavedInsight.Marker(rawValue: marker) != nil
            && !locationID.isEmpty
    }

    func record(existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(
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
            evidenceFactIDs: evidenceFactIDs,
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
        insight.evidenceFactIDsData = (try? JSONEncoder().encode(evidenceFactIDs)) ?? Data("[]".utf8)
        insight.reviewDate = reviewDate
        insight.reminderIdentifier = nil
        insight.createdAt = createdAt
        insight.updatedAt = updatedAt
    }
}

private struct CloudDeletionPayload: Codable {
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
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    var isValid: Bool {
        entityType == RecordType.chart || entityType == RecordType.insight
    }

    func record(existing: CKRecord? = nil) throws -> CKRecord {
        let record = existing ?? CKRecord(
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
