import Foundation
import SwiftData

struct BackupRestoreResult: Equatable, Sendable {
    let chartCount: Int
    let insightCount: Int
}

@MainActor
enum BackupRestoreService {
    static func restore(
        _ payload: ValidatedBackupPayload,
        existingCharts: [SavedChart],
        existingInsights: [SavedInsight],
        modelContext: ModelContext,
        restoredAt: Date = .now,
        shortcutDefaults: UserDefaults? = UserDefaults(
            suiteName: ReviewReminderScheduler.sharedDefaultsSuite
        ),
        cancelReminder: (String?) -> Void = {
            ReviewReminderScheduler().cancel(identifier: $0)
        },
        scheduleReminder: (
            UUID,
            String,
            String,
            Date
        ) async throws -> String? = { insightID, chartName, title, date in
            try await ReviewReminderScheduler().scheduleSyncedReminder(
                insightID: insightID,
                chartName: chartName,
                title: title,
                date: date
            )
        }
    ) async throws -> BackupRestoreResult {
        let validatedCharts = try payload.makeSavedCharts()
        let validatedChartsByID = Dictionary(
            uniqueKeysWithValues: validatedCharts.map { ($0.id, $0) }
        )

        let chartIDs = Set(payload.charts.map(\.id))
        let restoredInsightIDs = Set(payload.insights.map(\.id))
        let restoredKeys = Set(
            chartIDs.map { RestoredEntityKey(entityID: $0, entityType: "SavedChart") }
                + restoredInsightIDs.map {
                    RestoredEntityKey(entityID: $0, entityType: "SavedInsight")
                }
        )
        let matchingDeletions = try modelContext.fetch(FetchDescriptor<CloudDeletion>())
            .filter {
                restoredKeys.contains(
                    RestoredEntityKey(entityID: $0.entityID, entityType: $0.entityType)
                )
            }
        let restorationRevision = matchingDeletions.reduce(restoredAt) { revision, deletion in
            deletion.deletedAt >= revision
                ? deletion.deletedAt.addingTimeInterval(0.001)
                : revision
        }
        var chartsByID = Dictionary(uniqueKeysWithValues: existingCharts.map { ($0.id, $0) })
        var insightsByID = Dictionary(uniqueKeysWithValues: existingInsights.map { ($0.id, $0) })
        var reminderIdentifiersToCancel: [String] = []

        for insight in existingInsights where
            chartIDs.contains(insight.chartID) && !restoredInsightIDs.contains(insight.id) {
            ICloudSyncService.recordDeletion(
                entityID: insight.id,
                entityType: "SavedInsight",
                modelContext: modelContext
            )
            if let identifier = insight.reminderIdentifier {
                reminderIdentifiersToCancel.append(identifier)
            }
            modelContext.delete(insight)
            insightsByID.removeValue(forKey: insight.id)
        }

        for chartDTO in payload.charts {
            let chart: SavedChart
            if let existing = chartsByID[chartDTO.id] {
                try chartDTO.apply(to: existing)
                chart = existing
            } else {
                chart = validatedChartsByID[chartDTO.id]!
                modelContext.insert(chart)
                chartsByID[chart.id] = chart
            }
            chart.updatedAt = restorationRevision
        }

        for insightDTO in payload.insights {
            let restoredInsight: SavedInsight
            if let existing = insightsByID[insightDTO.id] {
                if let identifier = existing.reminderIdentifier {
                    reminderIdentifiersToCancel.append(identifier)
                }
                insightDTO.apply(to: existing)
                restoredInsight = existing
            } else {
                restoredInsight = insightDTO.makeSavedInsight()
                modelContext.insert(restoredInsight)
                insightsByID[restoredInsight.id] = restoredInsight
            }
            restoredInsight.updatedAt = restorationRevision
        }

        matchingDeletions.forEach(modelContext.delete)

        var newReminderIdentifiers: [String] = []
        do {
            for insightID in restoredInsightIDs {
                guard let insight = insightsByID[insightID],
                      let reviewDate = insight.reviewDate,
                      let chartName = chartsByID[insight.chartID]?.name else { continue }
                let identifier = try await scheduleReminder(
                    insight.id,
                    chartName,
                    insight.title,
                    reviewDate
                )
                insight.reminderIdentifier = identifier
                if let identifier {
                    newReminderIdentifiers.append(identifier)
                }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            newReminderIdentifiers.forEach { cancelReminder($0) }
            throw error
        }

        reminderIdentifiersToCancel.forEach { cancelReminder($0) }
        PinnedChartShortcut.reconcile(
            charts: Array(chartsByID.values),
            defaults: shortcutDefaults
        )

        return BackupRestoreResult(
            chartCount: payload.charts.count,
            insightCount: payload.insights.count
        )
    }
}

private struct RestoredEntityKey: Hashable {
    let entityID: UUID
    let entityType: String
}
