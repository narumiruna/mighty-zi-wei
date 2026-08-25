import SwiftData

struct BackupRestoreResult: Equatable, Sendable {
    let chartCount: Int
    let insightCount: Int
}

@MainActor
enum BackupRestoreService {
    static func restore(
        _ payload: BackupPayload,
        existingCharts: [SavedChart],
        existingInsights: [SavedInsight],
        modelContext: ModelContext
    ) throws -> BackupRestoreResult {
        try payload.validate()
        let validatedCharts = try payload.makeSavedCharts()
        let validatedChartsByID = Dictionary(
            uniqueKeysWithValues: validatedCharts.map { ($0.id, $0) }
        )

        let chartIDs = Set(payload.charts.map(\.id))
        let restoredInsightIDs = Set(payload.insights.map(\.id))
        var chartsByID = Dictionary(uniqueKeysWithValues: existingCharts.map { ($0.id, $0) })
        var insightsByID = Dictionary(uniqueKeysWithValues: existingInsights.map { ($0.id, $0) })

        for insight in existingInsights where
            chartIDs.contains(insight.chartID) && !restoredInsightIDs.contains(insight.id) {
            modelContext.delete(insight)
            insightsByID.removeValue(forKey: insight.id)
        }

        for chartDTO in payload.charts {
            if let existing = chartsByID[chartDTO.id] {
                try chartDTO.apply(to: existing)
            } else {
                let chart = validatedChartsByID[chartDTO.id]!
                modelContext.insert(chart)
                chartsByID[chart.id] = chart
            }
        }

        for insightDTO in payload.insights {
            if let existing = insightsByID[insightDTO.id] {
                insightDTO.apply(to: existing)
            } else {
                let insight = insightDTO.makeSavedInsight()
                modelContext.insert(insight)
                insightsByID[insight.id] = insight
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return BackupRestoreResult(
            chartCount: payload.charts.count,
            insightCount: payload.insights.count
        )
    }
}
