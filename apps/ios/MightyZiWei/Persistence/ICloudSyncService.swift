import CloudKit
import Foundation
import Observation
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
protocol ICloudSynchronizing {
    func sync(
        charts: [SavedChart],
        insights: [SavedInsight],
        deletions: [CloudDeletion],
        modelContext: ModelContext
    ) async throws -> ICloudSyncResult
}

@MainActor
@Observable
final class ICloudSynchronizer {
    private let service: any ICloudSynchronizing

    init(service: any ICloudSynchronizing = ICloudSyncService()) {
        self.service = service
    }

    func sync(
        charts: [SavedChart],
        insights: [SavedInsight],
        deletions: [CloudDeletion],
        modelContext: ModelContext
    ) async throws -> ICloudSyncResult {
        _ = (charts, insights, deletions)
        let synchronizationContext = ModelContext(modelContext.container)
        synchronizationContext.autosaveEnabled = false
        let latestCharts = try synchronizationContext.fetch(FetchDescriptor<SavedChart>())
        let latestInsights = try synchronizationContext.fetch(FetchDescriptor<SavedInsight>())
        let latestDeletions = try synchronizationContext.fetch(FetchDescriptor<CloudDeletion>())
        return try await service.sync(
            charts: latestCharts,
            insights: latestInsights,
            deletions: latestDeletions,
            modelContext: synchronizationContext
        )
    }
}

enum ICloudSyncFailureState: Equatable, Sendable {
    case accountUnavailable
    case partialRemote

    var message: String {
        switch self {
        case .accountUnavailable:
            "同步未完成。請確認已登入 iCloud 並允許此 App 使用 iCloud，再重試。"
        case .partialRemote:
            "同步未完成，iCloud 可能已收到部分資料。本機資料仍保留，你可以安全地重試。"
        }
    }

    init(error: any Error) {
        if let syncError = error as? ICloudSyncService.SyncError,
           syncError == .iCloudUnavailable {
            self = .accountUnavailable
        } else if let cloudError = error as? CKError,
                  cloudError.code == .notAuthenticated
                    || cloudError.code == .permissionFailure {
            self = .accountUnavailable
        } else {
            self = .partialRemote
        }
    }
}

struct CloudLocalTombstonePlan: Equatable, Sendable {
    let chartIDs: Set<UUID>
    let insightIDs: Set<UUID>
}

struct CloudTombstoneUploadPolicy: Sendable {
    func shouldUpload(localDeletedAt: Date, remoteDeletedAt: Date?) -> Bool {
        guard let remoteDeletedAt else { return true }
        return localDeletedAt > remoteDeletedAt
    }
}

struct CloudBookmarkRevision: Equatable, Sendable {
    let id: UUID
    let chartID: UUID
    let locationID: String
    let updatedAt: Date
}

struct CloudBookmarkDeduplicationPlan: Equatable, Sendable {
    let duplicateIDs: Set<UUID>
}

struct CloudBookmarkDeduplicator: Sendable {
    func makePlan(
        localInsights: [SavedInsight],
        remoteInsights: [CloudInsightPayload]
    ) -> CloudBookmarkDeduplicationPlan {
        let localRevisions = localInsights.compactMap { insight -> CloudBookmarkRevision? in
            guard insight.kind == .bookmark else { return nil }
            return CloudBookmarkRevision(
                id: insight.id,
                chartID: insight.chartID,
                locationID: insight.locationID,
                updatedAt: insight.updatedAt
            )
        }
        let remoteRevisions = remoteInsights.compactMap { insight -> CloudBookmarkRevision? in
            guard insight.kind == SavedInsight.Kind.bookmark.rawValue else { return nil }
            return CloudBookmarkRevision(
                id: insight.id,
                chartID: insight.chartID,
                locationID: insight.locationID,
                updatedAt: insight.updatedAt
            )
        }
        return makePlan(revisions: localRevisions + remoteRevisions)
    }

    func makePlan(revisions: [CloudBookmarkRevision]) -> CloudBookmarkDeduplicationPlan {
        let groups = Dictionary(grouping: revisions) {
            CloudBookmarkLocation(chartID: $0.chartID, locationID: $0.locationID)
        }
        var duplicateIDs = Set<UUID>()
        for group in groups.values {
            let uniqueRevisions = Dictionary(grouping: group, by: \.id).values.compactMap {
                $0.max { first, second in first.updatedAt < second.updatedAt }
            }
            guard uniqueRevisions.count > 1 else { continue }
            let ordered = uniqueRevisions.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            duplicateIDs.formUnion(ordered.dropFirst().map(\.id))
        }
        return CloudBookmarkDeduplicationPlan(duplicateIDs: duplicateIDs)
    }
}

private struct CloudBookmarkLocation: Hashable {
    let chartID: UUID
    let locationID: String
}

struct CloudLocalTombstonePlanner {
    func makePlan(
        charts: [SavedChart],
        insights: [SavedInsight],
        deletions: [CloudDeletion],
        remoteChartUpdatedAt: [UUID: Date] = [:],
        remoteInsightUpdatedAt: [UUID: Date] = [:]
    ) -> CloudLocalTombstonePlan {
        var latestDeletionDates: [CloudEntityKey: Date] = [:]
        for deletion in deletions {
            let key = CloudEntityKey(type: deletion.entityType, id: deletion.entityID)
            latestDeletionDates[key] = max(
                latestDeletionDates[key] ?? .distantPast,
                deletion.deletedAt
            )
        }
        let resolver = CloudConflictResolver()
        let chartIDs: Set<UUID> = Set(charts.compactMap { chart -> UUID? in
            let deletedAt = latestDeletionDates[
                CloudEntityKey(type: RecordType.chart, id: chart.id)
            ]
            guard let deletedAt,
                  resolver.isDeleted(
                      contentUpdatedAt: chart.updatedAt,
                      deletedAt: deletedAt
                  ),
                  remoteChartUpdatedAt[chart.id].map({ $0 <= deletedAt }) ?? true else {
                return nil
            }
            return chart.id
        })
        let insightIDs: Set<UUID> = Set(insights.compactMap { insight -> UUID? in
            if chartIDs.contains(insight.chartID) { return insight.id }
            let deletedAt = latestDeletionDates[
                CloudEntityKey(type: RecordType.insight, id: insight.id)
            ]
            guard let deletedAt,
                  resolver.isDeleted(
                      contentUpdatedAt: insight.updatedAt,
                      deletedAt: deletedAt
                  ),
                  remoteInsightUpdatedAt[insight.id].map({ $0 <= deletedAt }) ?? true else {
                return nil
            }
            return insight.id
        })
        return CloudLocalTombstonePlan(chartIDs: chartIDs, insightIDs: insightIDs)
    }
}

@MainActor
@Observable
final class ICloudSyncCoordinator {
    enum Status: Equatable {
        case idle
        case waiting
        case syncing
        case synced(ICloudSyncResult)
        case incomplete(ICloudSyncFailureState)
    }

    typealias Operation = @MainActor () async throws -> ICloudSyncResult

    private(set) var isSyncing = false
    private(set) var status: Status = .idle
    private var waiters: [UUID: CheckedContinuation<ICloudSyncResult, any Error>] = [:]
    private var pendingOperation: (id: UUID, operation: Operation)?
    var waitingCallerCount: Int { waiters.count }

    func markEnabledWaiting() {
        guard !isSyncing else { return }
        status = .waiting
    }

    func markDisabled() {
        guard !isSyncing else { return }
        status = .idle
    }

    func synchronize(
        operation: @escaping Operation
    ) async throws -> ICloudSyncResult {
        if isSyncing {
            let identifier = UUID()
            pendingOperation = (identifier, operation)
            return try await waitForCurrentSync(identifier: identifier)
        }

        isSyncing = true
        status = .syncing
        var currentOperation = operation
        var combinedResult = ICloudSyncResult(
            uploadedCount: 0,
            downloadedCount: 0,
            conflictCount: 0
        )
        do {
            while true {
                let result = try await currentOperation()
                combinedResult = ICloudSyncResult(
                    uploadedCount: combinedResult.uploadedCount + result.uploadedCount,
                    downloadedCount: combinedResult.downloadedCount + result.downloadedCount,
                    conflictCount: combinedResult.conflictCount + result.conflictCount
                )
                guard let trailing = pendingOperation else { break }
                pendingOperation = nil
                currentOperation = trailing.operation
            }
            isSyncing = false
            status = .synced(combinedResult)
            resumeWaiters(with: .success(combinedResult))
            return combinedResult
        } catch {
            isSyncing = false
            pendingOperation = nil
            status = .incomplete(ICloudSyncFailureState(error: error))
            resumeWaiters(with: .failure(error))
            throw error
        }
    }

    private func waitForCurrentSync(identifier: UUID) async throws -> ICloudSyncResult {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(identifier)
            }
        }
    }

    private func cancelWaiter(_ identifier: UUID) {
        if pendingOperation?.id == identifier {
            pendingOperation = nil
        }
        waiters.removeValue(forKey: identifier)?.resume(
            throwing: CancellationError()
        )
    }

    private func resumeWaiters(
        with result: Result<ICloudSyncResult, any Error>
    ) {
        let currentWaiters = waiters.values
        waiters.removeAll()
        for waiter in currentWaiters {
            switch result {
            case .success(let value): waiter.resume(returning: value)
            case .failure(let error): waiter.resume(throwing: error)
            }
        }
    }
}

@MainActor
enum CloudSyncMutationTransaction {
    static func run<Result>(
        modelContext: ModelContext,
        onRollback: () -> Void = {},
        operation: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation()
        } catch {
            modelContext.rollback()
            onRollback()
            throw error
        }
    }
}

@MainActor
final class ICloudSyncService: ICloudSynchronizing {
    static let enabledKey = "icloud.sync.enabled"

    enum SyncError: LocalizedError, Equatable {
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

    private let providedContainer: CKContainer?
    private var container: CKContainer { providedContainer ?? .default() }
    private var database: CKDatabase { container.privateCloudDatabase }

    init(container: CKContainer? = nil) {
        providedContainer = container
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
        let remoteDeletionsByKey = Dictionary(
            uniqueKeysWithValues: remoteDeletions.map {
                (DeletionKey(type: $0.entityType, id: $0.entityID), $0)
            }
        )
        var newlyScheduledReminderIdentifiers = Set<String>()
        return try await CloudSyncMutationTransaction.run(
            modelContext: modelContext,
            onRollback: {
                newlyScheduledReminderIdentifiers.forEach {
                    ReviewReminderScheduler().cancel(identifier: $0)
                }
            }
        ) {
        var uploaded = 0
        var downloaded = 0
        var conflicts = 0
        var reminderIdentifiersToCancel = Set<String>()
        var insightIDsToReconcileReminders = Set<UUID>()

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
        var insightsByID = Dictionary(uniqueKeysWithValues: insights.map { ($0.id, $0) })
        let localTombstonePlan = CloudLocalTombstonePlanner().makePlan(
            charts: charts,
            insights: insights,
            deletions: Array(allDeletions.values),
            remoteChartUpdatedAt: Dictionary(
                uniqueKeysWithValues: remoteCharts.map { ($0.id, $0.updatedAt) }
            ),
            remoteInsightUpdatedAt: Dictionary(
                uniqueKeysWithValues: remoteInsights.map { ($0.id, $0.updatedAt) }
            )
        )
        for insightID in localTombstonePlan.insightIDs {
            guard let insight = insightsByID.removeValue(forKey: insightID) else { continue }
            if let identifier = insight.reminderIdentifier {
                reminderIdentifiersToCancel.insert(identifier)
            }
            modelContext.delete(insight)
            downloaded += 1
        }
        for chartID in localTombstonePlan.chartIDs {
            guard let chart = chartsByID.removeValue(forKey: chartID) else { continue }
            modelContext.delete(chart)
            downloaded += 1
        }

        for remote in remoteCharts {
            let tombstone = allDeletions[DeletionKey(type: RecordType.chart, id: remote.id)]
            if CloudConflictResolver().isDeleted(
                contentUpdatedAt: remote.updatedAt,
                deletedAt: tombstone?.deletedAt
            ), chartsByID[remote.id] == nil {
                continue
            }
            if let local = chartsByID[remote.id] {
                if CloudConflictResolver().winner(
                    localUpdatedAt: local.updatedAt,
                    remoteUpdatedAt: remote.updatedAt
                ) == .remote {
                    try remote.apply(to: local)
                    insightsByID.values
                        .filter { $0.chartID == local.id && $0.reviewDate != nil }
                        .forEach { insightIDsToReconcileReminders.insert($0.id) }
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
        for chart in chartsByID.values where !remoteChartIDs.contains(chart.id) {
            try await database.save(try CloudChartPayload(chart).record())
            uploaded += 1
        }

        var remoteInsightsToReconcile = remoteInsights.filter { remote in
            guard chartsByID[remote.chartID] != nil else { return false }
            let tombstone = allDeletions[DeletionKey(type: RecordType.insight, id: remote.id)]
            return !CloudConflictResolver().isDeleted(
                contentUpdatedAt: remote.updatedAt,
                deletedAt: tombstone?.deletedAt
            ) || insightsByID[remote.id] != nil
        }
        for remote in remoteInsightsToReconcile {
            guard remote.isStructurallyValid,
                  let linkedChart = chartsByID[remote.chartID] else {
                throw SyncError.invalidRemoteData
            }
            let validFactIDs = Set(
                ChartFactBuilder().makeFacts(from: try linkedChart.resolvedChart()).map(\.id)
            )
            guard remote.evidenceFactIDs.allSatisfy(validFactIDs.contains) else {
                throw SyncError.invalidRemoteData
            }
        }

        let bookmarkPlan = CloudBookmarkDeduplicator().makePlan(
            localInsights: Array(insightsByID.values),
            remoteInsights: remoteInsightsToReconcile
        )
        conflicts += bookmarkPlan.duplicateIDs.count
        for duplicateID in bookmarkPlan.duplicateIDs {
            if let duplicate = insightsByID.removeValue(forKey: duplicateID) {
                if let identifier = duplicate.reminderIdentifier {
                    reminderIdentifiersToCancel.insert(identifier)
                }
                modelContext.delete(duplicate)
                downloaded += 1
            }
            if insightRecordsByID[duplicateID] != nil {
                try await deleteContentRecord(for: DeletionKey(
                    type: RecordType.insight,
                    id: duplicateID
                ))
                uploaded += 1
            }
        }
        remoteInsightsToReconcile.removeAll {
            bookmarkPlan.duplicateIDs.contains($0.id)
        }

        for remote in remoteInsightsToReconcile {
            if let local = insightsByID[remote.id] {
                if CloudConflictResolver().winner(
                    localUpdatedAt: local.updatedAt,
                    remoteUpdatedAt: remote.updatedAt
                ) == .remote {
                    remote.apply(to: local)
                    insightIDsToReconcileReminders.insert(local.id)
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
                insightIDsToReconcileReminders.insert(local.id)
                downloaded += 1
            }
        }
        let remoteInsightIDs = Set(remoteInsightsToReconcile.map(\.id))
        for insight in insightsByID.values where
            !remoteInsightIDs.contains(insight.id) && chartsByID[insight.chartID] != nil {
            try await database.save(CloudInsightPayload(insight).record())
            uploaded += 1
        }

        let tombstonePolicy = CloudTombstoneUploadPolicy()
        for (key, deletion) in allDeletions {
            if tombstonePolicy.shouldUpload(
                localDeletedAt: deletion.deletedAt,
                remoteDeletedAt: remoteDeletionsByKey[key]?.deletedAt
            ) {
                try await database.save(CloudDeletionPayload(deletion).record(
                    existing: deletionRecordsByKey[key]
                ))
                uploaded += 1
            }
            if deletionWins(
                key: key,
                deletion: deletion,
                chartsByID: chartsByID,
                insightsByID: insightsByID
            ), contentRecordExists(
                for: key,
                chartRecordsByID: chartRecordsByID,
                insightRecordsByID: insightRecordsByID
            ) {
                try await deleteContentRecord(for: key)
            }
        }

        for insightID in insightIDsToReconcileReminders {
            guard let insight = insightsByID[insightID],
                  let chartName = chartsByID[insight.chartID]?.name else { continue }
            let oldIdentifier = insight.reminderIdentifier
            let newIdentifier: String?
            if let reviewDate = insight.reviewDate {
                newIdentifier = try await ReviewReminderScheduler().scheduleSyncedReminder(
                    insightID: insight.id,
                    chartName: chartName,
                    title: insight.title,
                    date: reviewDate
                )
            } else {
                newIdentifier = nil
            }
            insight.reminderIdentifier = newIdentifier
            if let oldIdentifier, oldIdentifier != newIdentifier {
                reminderIdentifiersToCancel.insert(oldIdentifier)
            }
            if let newIdentifier, newIdentifier != oldIdentifier {
                newlyScheduledReminderIdentifiers.insert(newIdentifier)
            }
        }

        try modelContext.save()
        newlyScheduledReminderIdentifiers.removeAll()
        reminderIdentifiersToCancel.forEach {
            ReviewReminderScheduler().cancel(identifier: $0)
        }
        return ICloudSyncResult(
            uploadedCount: uploaded,
            downloadedCount: downloaded,
            conflictCount: conflicts
        )
        }
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

    private func contentRecordExists(
        for key: DeletionKey,
        chartRecordsByID: [UUID: CKRecord],
        insightRecordsByID: [UUID: CKRecord]
    ) -> Bool {
        switch key.type {
        case RecordType.chart:
            chartRecordsByID[key.id] != nil
        case RecordType.insight:
            insightRecordsByID[key.id] != nil
        default:
            false
        }
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

private typealias DeletionKey = CloudEntityKey

private struct CloudEntityKey: Hashable {
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

struct CloudInsightPayload: Codable {
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
