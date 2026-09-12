import Foundation

struct BackupExportSnapshot: Sendable {
  let charts: [BackupChartDTO]
  let insights: [BackupInsightDTO]
  let observations: [ObservationPayload]
  let reviews: [ObservationReviewPayload]

  init(savedCharts: [SavedChart], insights: [BackupInsightDTO] = []) throws {
    charts = try savedCharts.map(BackupChartDTO.init(savedChart:))
    self.insights = insights
    observations = []
    reviews = []
  }

  init(
    savedCharts: [SavedChart], savedInsights: [SavedInsight],
    savedObservations: [SavedObservation] = [], savedReviews: [SavedObservationReview] = []
  ) throws {
    charts = try savedCharts.map(BackupChartDTO.init(savedChart:))
    insights = savedInsights.map(BackupInsightDTO.init(savedInsight:))
    observations = try savedObservations.map(ObservationPayload.init)
    reviews = try savedReviews.map(ObservationReviewPayload.init)
  }
}

struct BackupPayload: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 3

  let schemaVersion: Int
  let charts: [BackupChartDTO]
  let insights: [BackupInsightDTO]
  let observations: [ObservationPayload]
  let reviews: [ObservationReviewPayload]

  init(
    schemaVersion: Int = BackupPayload.currentSchemaVersion,
    charts: [BackupChartDTO],
    insights: [BackupInsightDTO],
    observations: [ObservationPayload] = [],
    reviews: [ObservationReviewPayload] = []
  ) {
    self.schemaVersion = schemaVersion
    self.charts = charts
    self.insights = insights
    self.observations = observations
    self.reviews = reviews
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

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case charts
    case insights
    case observations
    case reviews
  }

  private enum InsightCodingKeys: String, CodingKey {
    case evidenceSeedIDs
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
      throw BackupError.unsupportedPayloadSchema(schemaVersion)
    }
    charts = try container.decode([BackupChartDTO].self, forKey: .charts)

    if schemaVersion >= 2 {
      var encodedInsights = try container.nestedUnkeyedContainer(forKey: .insights)
      while !encodedInsights.isAtEnd {
        let insight = try encodedInsights.nestedContainer(keyedBy: InsightCodingKeys.self)
        _ = try insight.decode([String].self, forKey: .evidenceSeedIDs)
      }
    }

    insights = try container.decode([BackupInsightDTO].self, forKey: .insights)
    if schemaVersion >= 3 {
      observations = try container.decode([ObservationPayload].self, forKey: .observations)
      reviews = try container.decode([ObservationReviewPayload].self, forKey: .reviews)
    } else {
      observations =
        try container.decodeIfPresent([ObservationPayload].self, forKey: .observations) ?? []
      reviews =
        try container.decodeIfPresent([ObservationReviewPayload].self, forKey: .reviews) ?? []
      guard observations.isEmpty, reviews.isEmpty else { throw BackupError.malformedBackup }
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func validate() throws {
    guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
      throw BackupError.unsupportedPayloadSchema(schemaVersion)
    }
    guard schemaVersion >= 3 || (observations.isEmpty && reviews.isEmpty) else {
      throw BackupError.malformedBackup
    }
    let currentRuleSet = RuleSetIdentity.taiwanTraditionalSanheV1
    var chartIDs = Set<UUID>()
    var parentCharts: [UUID: ObservationParentChartEvidence] = [:]
    var validFactIDsByChartID: [UUID: Set<String>] = [:]
    var seedsByChartID: [UUID: [InterpretationSeed]] = [:]
    for chart in charts {
      guard chartIDs.insert(chart.id).inserted else {
        throw BackupError.duplicateChartID(chart.id)
      }
      guard chart.ruleSetID == currentRuleSet.id,
        chart.ruleSetVersion == currentRuleSet.version
      else {
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
      parentCharts[chart.id] = ObservationParentChartEvidence(
        ruleSetID: chart.ruleSetID,
        ruleSetVersion: chart.ruleSetVersion,
        facts: facts
      )
      validFactIDsByChartID[chart.id] = Set(facts.map(\.id))
      seedsByChartID[chart.id] = InterpretationSeedBuilder().makeSeeds(from: facts)
    }
    try ObservationGraphValidator().validate(
      observations: observations,
      reviews: reviews,
      parentCharts: parentCharts
    )

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
        insight.evidenceSeedIDs.allSatisfy(validSeedIDs.contains)
      else {
        throw BackupError.invalidEvidenceSeedID
      }
      let validFactIDs = validFactIDsByChartID[insight.chartID] ?? []
      guard
        PersistedInterpretationEvidenceValidator().isValid(
          seedIDs: insight.evidenceSeedIDs,
          factIDs: insight.evidenceFactIDs,
          seeds: seeds,
          validFactIDs: validFactIDs
        )
      else {
        throw BackupError.invalidEvidenceFactID
      }
    }
  }

  func validated() throws -> ValidatedBackupPayload {
    try validate()
    let payload =
      schemaVersion == Self.currentSchemaVersion
      ? self : BackupPayload(charts: charts, insights: insights)
    return ValidatedBackupPayload(payload: payload)
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
  var observations: [ObservationPayload] { payload.observations }
  var reviews: [ObservationReviewPayload] { payload.reviews }

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
