import Foundation

/// 備份檔內唯一允許的命盤來源資料。
struct BackupChartDTO: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let birthProfile: BirthProfile
    let ruleSetID: String
    let ruleSetVersion: Int
    let appSchemaVersion: Int
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        name: String,
        birthProfile: BirthProfile,
        ruleSetID: String,
        ruleSetVersion: Int,
        appSchemaVersion: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.birthProfile = birthProfile
        self.ruleSetID = ruleSetID
        self.ruleSetVersion = ruleSetVersion
        self.appSchemaVersion = appSchemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(savedChart: SavedChart) throws {
        self.init(
            id: savedChart.id,
            name: savedChart.name,
            birthProfile: try savedChart.birthProfile(),
            ruleSetID: savedChart.ruleSetID,
            ruleSetVersion: savedChart.ruleSetVersion,
            appSchemaVersion: savedChart.appSchemaVersion,
            createdAt: savedChart.createdAt,
            updatedAt: savedChart.updatedAt
        )
    }

    func makeSavedChart() throws -> SavedChart {
        SavedChart(
            id: id,
            name: name,
            birthProfileData: try BackupJSONCoding.encoder().encode(birthProfile),
            ruleSetID: ruleSetID,
            ruleSetVersion: ruleSetVersion,
            appSchemaVersion: appSchemaVersion,
            chartCacheData: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(to savedChart: SavedChart) throws {
        savedChart.name = name
        savedChart.birthProfileData = try BackupJSONCoding.encoder().encode(birthProfile)
        savedChart.ruleSetID = ruleSetID
        savedChart.ruleSetVersion = ruleSetVersion
        savedChart.appSchemaVersion = appSchemaVersion
        savedChart.chartCacheData = nil
        savedChart.createdAt = createdAt
        savedChart.updatedAt = updatedAt
    }
}

/// 筆記、標記或收藏共用的可攜式資料格式。
struct BackupInsightDTO: Codable, Equatable, Sendable {
    let id: UUID
    let chartID: UUID
    let kind: String
    let locationID: String
    let title: String
    let body: String
    let marker: String
    let evidenceFactIDs: [String]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        chartID: UUID,
        kind: String,
        locationID: String,
        title: String,
        body: String,
        marker: String = SavedInsight.Marker.none.rawValue,
        evidenceFactIDs: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.chartID = chartID
        self.kind = kind
        self.locationID = locationID
        self.title = title
        self.body = body
        self.marker = marker
        self.evidenceFactIDs = evidenceFactIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(savedInsight: SavedInsight) {
        self.init(
            id: savedInsight.id,
            chartID: savedInsight.chartID,
            kind: savedInsight.kindRawValue,
            locationID: savedInsight.locationID,
            title: savedInsight.title,
            body: savedInsight.content,
            marker: savedInsight.markerRawValue,
            evidenceFactIDs: savedInsight.evidenceFactIDs,
            createdAt: savedInsight.createdAt,
            updatedAt: savedInsight.updatedAt
        )
    }

    func makeSavedInsight() -> SavedInsight {
        SavedInsight(
            id: id,
            chartID: chartID,
            kind: SavedInsight.Kind(rawValue: kind)!,
            locationID: locationID,
            title: title,
            content: body,
            marker: SavedInsight.Marker(rawValue: marker)!,
            evidenceFactIDs: evidenceFactIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(to savedInsight: SavedInsight) {
        savedInsight.chartID = chartID
        savedInsight.kindRawValue = kind
        savedInsight.locationID = locationID
        savedInsight.title = title
        savedInsight.content = body
        savedInsight.markerRawValue = marker
        savedInsight.evidenceFactIDsData = (try? BackupJSONCoding.encoder().encode(evidenceFactIDs)) ?? Data("[]".utf8)
        savedInsight.createdAt = createdAt
        savedInsight.updatedAt = updatedAt
    }
}

struct BackupPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let charts: [BackupChartDTO]
    let insights: [BackupInsightDTO]

    init(
        schemaVersion: Int = BackupPayload.currentSchemaVersion,
        charts: [BackupChartDTO],
        insights: [BackupInsightDTO]
    ) throws {
        self.schemaVersion = schemaVersion
        self.charts = charts
        self.insights = insights
        try validate()
    }

    init(savedCharts: [SavedChart], insights: [BackupInsightDTO] = []) throws {
        try self.init(
            charts: savedCharts.map(BackupChartDTO.init(savedChart:)),
            insights: insights
        )
    }

    init(savedCharts: [SavedChart], savedInsights: [SavedInsight]) throws {
        try self.init(
            charts: savedCharts.map(BackupChartDTO.init(savedChart:)),
            insights: savedInsights.map(BackupInsightDTO.init(savedInsight:))
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BackupError.unsupportedPayloadSchema(schemaVersion)
        }

        let currentRuleSet = RuleSetIdentity.taiwanTraditionalSanheV1
        var chartIDs = Set<UUID>()
        var validFactIDsByChartID: [UUID: Set<String>] = [:]
        for chart in charts {
            guard chartIDs.insert(chart.id).inserted else {
                throw BackupError.duplicateChartID(chart.id)
            }
            guard chart.ruleSetID == currentRuleSet.id,
                  chart.ruleSetVersion == currentRuleSet.version else {
                throw BackupError.unsupportedChartRuleSet(
                    chartID: chart.id,
                    ruleSetID: chart.ruleSetID,
                    ruleSetVersion: chart.ruleSetVersion
                )
            }
            guard chart.appSchemaVersion == SavedChart.schemaVersion else {
                throw BackupError.unsupportedChartSchema(
                    chartID: chart.id,
                    schemaVersion: chart.appSchemaVersion
                )
            }
            guard let resolvedChart = try? ZiWeiCalculator().calculate(chart.birthProfile) else {
                throw BackupError.invalidChartData(chart.id)
            }
            validFactIDsByChartID[chart.id] = Set(
                ChartFactBuilder().makeFacts(from: resolvedChart).map(\.id)
            )
        }

        var insightIDs = Set<UUID>()
        for insight in insights {
            guard insightIDs.insert(insight.id).inserted else {
                throw BackupError.duplicateInsightID(insight.id)
            }
            guard chartIDs.contains(insight.chartID) else {
                throw BackupError.missingInsightChart(
                    insightID: insight.id,
                    chartID: insight.chartID
                )
            }
            guard SavedInsight.Kind(rawValue: insight.kind) != nil else {
                throw BackupError.invalidInsightKind(insight.kind)
            }
            guard SavedInsight.Marker(rawValue: insight.marker) != nil else {
                throw BackupError.invalidInsightMarker(insight.marker)
            }
            guard !insight.locationID.isEmpty else {
                throw BackupError.invalidInsightLocation
            }
            let validFactIDs = validFactIDsByChartID[insight.chartID] ?? []
            guard insight.evidenceFactIDs.allSatisfy(validFactIDs.contains) else {
                throw BackupError.invalidEvidenceFactID
            }
        }
    }

    func validated() throws -> ValidatedBackupPayload {
        try validate()
        return ValidatedBackupPayload(payload: self)
    }
}

struct ValidatedBackupPayload: Sendable {
    let schemaVersion: Int
    let charts: [BackupChartDTO]
    let insights: [BackupInsightDTO]

    fileprivate init(payload: BackupPayload) {
        schemaVersion = payload.schemaVersion
        charts = payload.charts
        insights = payload.insights
    }

    func makeSavedCharts() throws -> [SavedChart] {
        try charts.map { try $0.makeSavedChart() }
    }

    func makeSavedInsights() -> [SavedInsight] {
        insights.map { $0.makeSavedInsight() }
    }
}

enum BackupJSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
