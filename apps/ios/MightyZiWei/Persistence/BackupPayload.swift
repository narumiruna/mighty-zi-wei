import Foundation

/// 備份檔內唯一允許的命盤來源資料。
struct BackupChartDTO: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let birthProfile: BirthProfile
    let ruleSetID: String
    let ruleSetVersion: Int
    let appSchemaVersion: Int
    let tags: [String]?
    let isPinned: Bool?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        name: String,
        birthProfile: BirthProfile,
        ruleSetID: String,
        ruleSetVersion: Int,
        appSchemaVersion: Int,
        tags: [String] = [],
        isPinned: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.birthProfile = birthProfile
        self.ruleSetID = ruleSetID
        self.ruleSetVersion = ruleSetVersion
        self.appSchemaVersion = appSchemaVersion
        self.tags = tags
        self.isPinned = isPinned
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
            tags: savedChart.tags,
            isPinned: savedChart.isPinned,
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
            tags: tags ?? [],
            isPinned: isPinned ?? false,
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
        savedChart.tags = tags ?? []
        savedChart.isPinned = isPinned ?? false
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
    let evidenceSeedIDs: [String]
    let evidenceFactIDs: [String]
    let reviewDate: Date?
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
        evidenceSeedIDs: [String] = [],
        evidenceFactIDs: [String] = [],
        reviewDate: Date? = nil,
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
        self.evidenceSeedIDs = evidenceSeedIDs
        self.evidenceFactIDs = evidenceFactIDs
        self.reviewDate = reviewDate
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
            evidenceSeedIDs: savedInsight.evidenceSeedIDs,
            evidenceFactIDs: savedInsight.evidenceFactIDs,
            reviewDate: savedInsight.reviewDate,
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
            evidenceSeedIDs: evidenceSeedIDs,
            evidenceFactIDs: evidenceFactIDs,
            reviewDate: reviewDate,
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
        savedInsight.evidenceSeedIDsData = (try? BackupJSONCoding.encoder().encode(evidenceSeedIDs)) ?? Data("[]".utf8)
        savedInsight.evidenceFactIDsData = (try? BackupJSONCoding.encoder().encode(evidenceFactIDs)) ?? Data("[]".utf8)
        savedInsight.reviewDate = reviewDate
        savedInsight.reminderIdentifier = nil
        savedInsight.createdAt = createdAt
        savedInsight.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case chartID
        case kind
        case locationID
        case title
        case body
        case marker
        case evidenceSeedIDs
        case evidenceFactIDs
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
        body = try container.decode(String.self, forKey: .body)
        marker = try container.decode(String.self, forKey: .marker)
        evidenceSeedIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .evidenceSeedIDs
        ) ?? []
        evidenceFactIDs = try container.decode([String].self, forKey: .evidenceFactIDs)
        reviewDate = try container.decodeIfPresent(Date.self, forKey: .reviewDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct BackupExportSnapshot: Sendable {
    let charts: [BackupChartDTO]
    let insights: [BackupInsightDTO]

    init(savedCharts: [SavedChart], insights: [BackupInsightDTO] = []) throws {
        charts = try savedCharts.map(BackupChartDTO.init(savedChart:))
        self.insights = insights
    }

    init(savedCharts: [SavedChart], savedInsights: [SavedInsight]) throws {
        charts = try savedCharts.map(BackupChartDTO.init(savedChart:))
        insights = savedInsights.map(BackupInsightDTO.init(savedInsight:))
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
    ) {
        self.schemaVersion = schemaVersion
        self.charts = charts
        self.insights = insights
    }

    init(savedCharts: [SavedChart], insights: [BackupInsightDTO] = []) throws {
        let snapshot = try BackupExportSnapshot(
            savedCharts: savedCharts,
            insights: insights
        )
        self.init(charts: snapshot.charts, insights: snapshot.insights)
    }

    init(savedCharts: [SavedChart], savedInsights: [SavedInsight]) throws {
        let snapshot = try BackupExportSnapshot(
            savedCharts: savedCharts,
            savedInsights: savedInsights
        )
        self.init(charts: snapshot.charts, insights: snapshot.insights)
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BackupError.unsupportedPayloadSchema(schemaVersion)
        }

        let currentRuleSet = RuleSetIdentity.taiwanTraditionalSanheV1
        var chartIDs = Set<UUID>()
        var validFactIDsByChartID: [UUID: Set<String>] = [:]
        var seedsByChartID: [UUID: [InterpretationSeed]] = [:]
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
            let facts = ChartFactBuilder().makeFacts(from: resolvedChart)
            validFactIDsByChartID[chart.id] = Set(facts.map(\.id))
            seedsByChartID[chart.id] = InterpretationSeedBuilder().makeSeeds(from: facts)
        }

        var insightIDs = Set<UUID>()
        var bookmarkLocations = Set<BackupBookmarkLocation>()
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
            guard let kind = SavedInsight.Kind(rawValue: insight.kind) else {
                throw BackupError.invalidInsightKind(insight.kind)
            }
            if kind == .bookmark {
                let location = BackupBookmarkLocation(
                    chartID: insight.chartID,
                    locationID: insight.locationID
                )
                guard bookmarkLocations.insert(location).inserted else {
                    throw BackupError.duplicateBookmarkLocation(
                        chartID: insight.chartID,
                        locationID: insight.locationID
                    )
                }
            }
            guard SavedInsight.Marker(rawValue: insight.marker) != nil else {
                throw BackupError.invalidInsightMarker(insight.marker)
            }
            guard !insight.locationID.isEmpty else {
                throw BackupError.invalidInsightLocation
            }
            let seeds = seedsByChartID[insight.chartID] ?? []
            let validSeedIDs = Set(seeds.map(\.id))
            guard Set(insight.evidenceSeedIDs).count == insight.evidenceSeedIDs.count,
                  insight.evidenceSeedIDs.allSatisfy(validSeedIDs.contains) else {
                throw BackupError.invalidEvidenceSeedID
            }
            let validFactIDs = validFactIDsByChartID[insight.chartID] ?? []
            guard PersistedInterpretationEvidenceValidator().isValid(
                seedIDs: insight.evidenceSeedIDs,
                factIDs: insight.evidenceFactIDs,
                seeds: seeds,
                validFactIDs: validFactIDs
            ) else {
                throw BackupError.invalidEvidenceFactID
            }
        }
    }

    func validated() throws -> ValidatedBackupPayload {
        try validate()
        return ValidatedBackupPayload(payload: self)
    }
}

private struct BackupBookmarkLocation: Hashable {
    let chartID: UUID
    let locationID: String
}

struct ValidatedBackupPayload: Sendable {
    let payload: BackupPayload

    var schemaVersion: Int { payload.schemaVersion }
    var charts: [BackupChartDTO] { payload.charts }
    var insights: [BackupInsightDTO] { payload.insights }

    fileprivate init(payload: BackupPayload) {
        self.payload = payload
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
