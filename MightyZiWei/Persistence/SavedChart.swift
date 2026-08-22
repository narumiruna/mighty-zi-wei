import Foundation
import SwiftData

@Model
final class SavedChart {
    static let schemaVersion = 1

    @Attribute(.unique) var id: UUID
    var name: String
    var birthProfileData: Data
    var ruleSetID: String
    var ruleSetVersion: Int
    var appSchemaVersion: Int
    var chartCacheData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        birthProfileData: Data,
        ruleSetID: String,
        ruleSetVersion: Int,
        appSchemaVersion: Int = SavedChart.schemaVersion,
        chartCacheData: Data?,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.birthProfileData = birthProfileData
        self.ruleSetID = ruleSetID
        self.ruleSetVersion = ruleSetVersion
        self.appSchemaVersion = appSchemaVersion
        self.chartCacheData = chartCacheData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func make(name: String, profile: BirthProfile, chart: ZiWeiChart) throws -> SavedChart {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SavedChart(
            name: normalizedName(name, profile: profile),
            birthProfileData: try encoder.encode(profile),
            ruleSetID: chart.ruleSet.id,
            ruleSetVersion: chart.ruleSet.version,
            chartCacheData: try encoder.encode(chart)
        )
    }

    func birthProfile() throws -> BirthProfile {
        try JSONDecoder().decode(BirthProfile.self, from: birthProfileData)
    }

    func resolvedChart() throws -> ZiWeiChart {
        let current = RuleSetIdentity.taiwanTraditionalSanheV1
        if ruleSetID == current.id,
           ruleSetVersion == current.version,
           appSchemaVersion == Self.schemaVersion,
           let chartCacheData,
           let cached = try? JSONDecoder().decode(ZiWeiChart.self, from: chartCacheData) {
            return cached
        }

        let profile = try birthProfile()
        let chart = try ZiWeiCalculator().calculate(profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        chartCacheData = try encoder.encode(chart)
        ruleSetID = chart.ruleSet.id
        ruleSetVersion = chart.ruleSet.version
        appSchemaVersion = Self.schemaVersion
        updatedAt = .now
        return chart
    }

    func rename(to proposedName: String) throws {
        name = Self.normalizedName(proposedName, profile: try birthProfile())
        updatedAt = .now
    }

    private static func normalizedName(_ value: String, profile: BirthProfile) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "\(profile.localDate.year)/\(profile.localDate.month)/\(profile.localDate.day) 命盤"
    }
}
